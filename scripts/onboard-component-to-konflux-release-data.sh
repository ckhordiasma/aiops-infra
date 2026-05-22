#!/usr/bin/env bash
# onboard-component-to-konflux-release-data.sh — Onboard a component to Konflux via konflux-release-data MR
#
# Usage:
#   ./scripts/onboard-component-to-konflux-release-data.sh --jira-url <url> [--existing-mr-url <url>]
#
# Required env vars:
#   GITLAB_USER    — GitLab username
#   GITLAB_TOKEN   — GitLab personal access token (api + write_repository)
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional:
#   KONFLUX_RELEASE_DATA_REPO_URL — override default konflux-release-data URL
#   EXT_OC_TOKEN — token for external Konflux cluster (stone-prd-rh01, ODH)
#   INT_OC_TOKEN — token for internal Konflux cluster (stone-prod-p02, RHOAI)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

JIRA_URL=""
JIRA_ID=""
EXISTING_MR_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jira-url)        JIRA_URL="$2"; shift 2 ;;
    --existing-mr-url) EXISTING_MR_URL="$2"; shift 2 ;;
    --workdir)       WORKDIR="$2"; shift 2 ;;
    -*)                echo "ERROR: Unknown flag: $1" >&2; exit 1 ;;
    *)
      if [[ -z "$JIRA_URL" ]]; then
        JIRA_URL="$1"; shift
      else
        echo "ERROR: Unexpected positional argument: $1" >&2; exit 1
      fi
      ;;
  esac
done

# ── Idempotency fast-path ────────────────────────────────────────────────────

if [[ -n "$EXISTING_MR_URL" ]]; then
  echo "MR already raised: $EXISTING_MR_URL"
  exit 0
fi

# ── Parse Jira URL ───────────────────────────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "${JIRA_URL:-}")"
[[ -z "$JIRA_URL" ]] && {
  echo "ERROR: Jira URL is required." >&2
  echo "  Usage: ./scripts/onboard-component-to-konflux-release-data.sh --jira-url <url>" >&2
  exit 1
}
echo "JIRA_URL : $JIRA_URL"
echo "JIRA_ID  : $JIRA_ID"

# ── Resolve KRD URL ──────────────────────────────────────────────────────────

KRD_URL="${KONFLUX_RELEASE_DATA_REPO_URL:-https://gitlab.cee.redhat.com/releng/konflux-release-data.git}"
echo "KONFLUX_RELEASE_DATA_REPO_URL=${KONFLUX_RELEASE_DATA_REPO_URL:-(not set, using default)}"
echo "KRD_URL resolved to: $KRD_URL"

# ── Check prerequisites ──────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "GITLAB_USER GITLAB_TOKEN JIRA_USER_EMAIL JIRA_API_TOKEN" \
  --tools "uv oc yamllint kustomize"

# Resolve kustomize binary
KUSTOMIZE_BIN="kustomize"
if ! command -v kustomize &>/dev/null && [[ -x "${HOME}/.local/bin/kustomize" ]]; then
  KUSTOMIZE_BIN="${HOME}/.local/bin/kustomize"
  export PATH="${HOME}/.local/bin:${PATH}"
fi

# ── Set up working directory ─────────────────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "$JIRA_URL")"
echo "Working directory: $WORKDIR"

# ── Fetch Jira details and component YAML ────────────────────────────────────

if [[ ! -f "$WORKDIR/component_onboarding_details.json" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL" || {
    echo "ERROR in Step 3a (Fetch Jira details): Could not fetch Jira issue. See details above. Aborting." >&2
    exit 1
  }
fi

if [[ ! -f "$WORKDIR/component_onboarding_details.yaml" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
    "$JIRA_URL" component_onboarding_details.yaml || {
    echo "ERROR in Step 3b (Download YAML): Could not download 'component_onboarding_details.yaml' from Jira." >&2
    echo "  Ensure the attachment exists on the Jira issue before running this skill." >&2
    exit 1
  }
fi

# ── Parse component details ─────────────────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/parse_component_details.sh" \
  --workdir     "$WORKDIR" \
  --jira-id     "$JIRA_ID" \
  --scripts-dir "$SCRIPTS_DIR")"
# Sets: COMPONENT_NAME, REPO_URL, REPO_BRANCH, PRODUCT_CONTEXT, QUAY_ORG, QUAY_VISIBILITY, QUAY_REPO_URI, IS_OPERATOR

YAML_FILE="$WORKDIR/component_onboarding_details.yaml"
CONTEXT_PATH=$(grep -m1     'context_path:'        "$YAML_FILE" | awk '{print $2}')
DOCKERFILE_PATH=$(grep -m1  'dockerfile_path:'     "$YAML_FILE" | awk '{print $2}')
TARGET_RHOAI_VERSION=$(grep -m1 'target_rhoai_version:' "$YAML_FILE" | awk '{print $2}' 2>/dev/null || echo "")

# Compute Konflux component name (ODH default)
if [[ "$COMPONENT_NAME" == *-ci ]]; then
  KONFLUX_COMPONENT_NAME="$COMPONENT_NAME"
else
  KONFLUX_COMPONENT_NAME="${COMPONENT_NAME}-ci"
fi

echo "COMPONENT_NAME    : $COMPONENT_NAME"
echo "REPO_URL          : $REPO_URL"
echo "REPO_BRANCH       : $REPO_BRANCH"
echo "CONTEXT_PATH      : $CONTEXT_PATH"
echo "DOCKERFILE_PATH   : $DOCKERFILE_PATH"
echo "PRODUCT_CONTEXT   : $PRODUCT_CONTEXT"

# ── Determine product context and set variables ─────────────────────────────

if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  CLUSTER_INSTANCE="internal"
  KONFLUX_NAMESPACE="rhoai-tenant"
  SPARSE_PATHS="tenants-config/cluster/stone-prod-p02/tenants/rhoai-tenant tenants-config/auto-generated/cluster/stone-prod-p02/tenants/rhoai-tenant"

  # Override KONFLUX_COMPONENT_NAME for RHOAI
  if [[ "$TARGET_RHOAI_VERSION" =~ ^([0-9]+)\.([0-9]+)-ea-([0-9]+)$ ]]; then
    KONFLUX_COMPONENT_NAME="${COMPONENT_NAME}-v${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-ea-${BASH_REMATCH[3]}"
  elif [[ "$TARGET_RHOAI_VERSION" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
    KONFLUX_COMPONENT_NAME="${COMPONENT_NAME}-v${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
  else
    echo "ERROR in Step 4 (RHOAI): Cannot parse target_rhoai_version '${TARGET_RHOAI_VERSION}'." >&2
    echo "  Expected x.y or x.y-ea-n (e.g. 3.4 or 3.4-ea-2)." >&2
    exit 1
  fi
else
  CLUSTER_INSTANCE="external"
  KONFLUX_NAMESPACE="open-data-hub-tenant"
  SPARSE_PATHS="tenants-config/cluster/stone-prd-rh01/tenants/open-data-hub-tenant tenants-config/auto-generated/cluster/stone-prd-rh01/tenants/open-data-hub-tenant"
  TARGET_YAML="tenants-config/cluster/stone-prd-rh01/tenants/open-data-hub-tenant/opendatahub-ci-components.yaml"
  KRD_APPLICATION="opendatahub-builds"
fi

echo "KONFLUX_COMPONENT_NAME : $KONFLUX_COMPONENT_NAME"

# ── Check if Konflux Component already exists ────────────────────────────────

set +e
bash "$SCRIPTS_DIR/check_konflux_component.sh" \
  "$KONFLUX_COMPONENT_NAME" "$KONFLUX_NAMESPACE" "$CLUSTER_INSTANCE"
CHECK_RC=$?
set -e

if [[ $CHECK_RC -eq 0 ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "konflux-component-created" \
    --comment "Konflux Component '$KONFLUX_COMPONENT_NAME' already exists in namespace '$KONFLUX_NAMESPACE'. No action needed."
  echo "Konflux Component already exists. Nothing to do."
  exit 0
elif [[ $CHECK_RC -eq 2 ]]; then
  echo "ERROR in Step 5: Could not check Konflux component status. Check VPN and EXT_OC_TOKEN/INT_OC_TOKEN." >&2
  exit 1
fi

# ── RHOAI: Parse version and set additional variables ────────────────────────

if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  if [[ -z "$TARGET_RHOAI_VERSION" ]]; then
    echo "ERROR in Step 8 (RHOAI): target_rhoai_version is missing from component_onboarding_details.yaml." >&2
    exit 1
  fi

  if [[ "$TARGET_RHOAI_VERSION" =~ ^([0-9]+)\.([0-9]+)-ea-([0-9]+)$ ]]; then
    VERSION_X="${BASH_REMATCH[1]}"
    VERSION_Y="${BASH_REMATCH[2]}"
    VERSION_N="${BASH_REMATCH[3]}"
    VERSION_NAME="v${VERSION_X}.${VERSION_Y}-ea.${VERSION_N}"
    RPA_VAR="v${VERSION_X}-${VERSION_Y}-ea-${VERSION_N}"
    KRD_APPLICATION="rhoai-v${VERSION_X}-${VERSION_Y}-ea-${VERSION_N}"
  elif [[ "$TARGET_RHOAI_VERSION" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
    VERSION_X="${BASH_REMATCH[1]}"
    VERSION_Y="${BASH_REMATCH[2]}"
    VERSION_N=""
    VERSION_NAME="v${VERSION_X}.${VERSION_Y}"
    RPA_VAR="v${VERSION_X}-${VERSION_Y}"
    KRD_APPLICATION="rhoai-v${VERSION_X}-${VERSION_Y}"
  else
    echo "ERROR in Step 8 (RHOAI): Cannot parse target_rhoai_version '${TARGET_RHOAI_VERSION}'." >&2
    exit 1
  fi

  TARGET_YAML="tenants-config/cluster/stone-prod-p02/tenants/rhoai-tenant/${VERSION_NAME}/ProjectDevelopmentStream-${VERSION_NAME}.yaml"

  # Normalize context path
  if [[ "$CONTEXT_PATH" == "./" || "$CONTEXT_PATH" == "." ]]; then
    CONTEXT_PATH_NORMALIZED="."
  else
    CONTEXT_PATH_NORMALIZED="$CONTEXT_PATH"
  fi

  # Add RPA config to sparse paths
  SPARSE_PATHS="$SPARSE_PATHS config/stone-prod-p02.hjvn.p1/product/ReleasePlanAdmission/rhoai"

  echo "VERSION_NAME    : $VERSION_NAME"
  echo "RPA_VAR         : $RPA_VAR"
  echo "TARGET_YAML     : $TARGET_YAML"
  echo "KRD_APPLICATION : $KRD_APPLICATION"
fi

# ── Set up playpen (sparse clone) ───────────────────────────────────────────

cd "$WORKDIR"

PLAYPEN_OUTPUT=$(GITLAB_SSL_VERIFY=false bash "$SCRIPTS_DIR/setup_gitlab_playpen.sh" \
  --src-url "$KRD_URL" \
  --src-branch main \
  --dest-branch "$JIRA_ID" \
  --sparse-files "$SPARSE_PATHS") || {
  echo "ERROR in Step 7 (Playpen setup): Clone or push failed. See details above." >&2
  echo "  Check VPN connectivity and GITLAB_TOKEN write_repository scope." >&2
  exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)
echo "Clone dir  : $CLONE_DIR"
echo "Dest branch: $DEST_BRANCH"

# ── Modify target YAML file (ODH) ───────────────────────────────────────────

if [[ "$PRODUCT_CONTEXT" == "ODH" ]]; then
  if grep -q "name: $KONFLUX_COMPONENT_NAME" "$CLONE_DIR/$TARGET_YAML" 2>/dev/null; then
    echo "Component entry '$KONFLUX_COMPONENT_NAME' already present in $TARGET_YAML -- skipping append."
  else
    COMPONENT_YAML=$(cat <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Component
metadata:
  annotations:
    build.appstudio.openshift.io/request: configure-pac-no-mr
    mintmaker.appstudio.redhat.com/disabled: "true"
    build.appstudio.openshift.io/pipeline: '{"name":"docker-build-multi-platform-oci-ta","bundle":"latest"}'
  name: ${KONFLUX_COMPONENT_NAME}
spec:
  application: ${KRD_APPLICATION}
  componentName: ${KONFLUX_COMPONENT_NAME}
  containerImage: quay.io/${QUAY_ORG}/${COMPONENT_NAME}
  source:
    git:
      context: ${CONTEXT_PATH}
      dockerfileUrl: ${DOCKERFILE_PATH}
      revision: ${REPO_BRANCH}
      url: ${REPO_URL}
EOF
)
    uv run --script "$SCRIPTS_DIR/edit_yaml.py" append-yaml-doc \
      "$CLONE_DIR/$TARGET_YAML" \
      --yaml-string "$COMPONENT_YAML" || {
      echo "ERROR in Step 8 (Modify YAML): Could not append Component document to $TARGET_YAML. See details above. Aborting." >&2
      exit 1
    }
  fi

  grep -q "name: $KONFLUX_COMPONENT_NAME" "$CLONE_DIR/$TARGET_YAML" \
    || { echo "ERROR: $KONFLUX_COMPONENT_NAME not found in $TARGET_YAML after append." >&2; exit 1; }
fi

# ── Modify RHOAI-specific files ─────────────────────────────────────────────

if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then

  # 8-RHOAI-1: ProjectDevelopmentStream
  PDS_FILE="$CLONE_DIR/$TARGET_YAML"
  if [[ ! -f "$PDS_FILE" ]]; then
    echo "ERROR in Step 8 (RHOAI): ProjectDevelopmentStream-${VERSION_NAME}.yaml not found." >&2
    echo "  Sprint onboarding for version '${VERSION_NAME}' is pending." >&2
    if [[ -n "$JIRA_URL" ]]; then
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --comment "Blocked: ProjectDevelopmentStream-${VERSION_NAME}.yaml not found in konflux-release-data. Sprint onboarding is pending."
    fi
    exit 1
  fi

  if grep -q "name: ${COMPONENT_NAME}-{{.versionName}}" "$PDS_FILE" 2>/dev/null; then
    echo "Component already present in ProjectDevelopmentStream -- skipping."
  else
    # Append to spec.resources using edit_yaml.py
    PDS_ENTRY=$(cat <<EOF
- apiVersion: appstudio.redhat.com/v1alpha1
  kind: Component
  metadata:
    annotations:
      build.appstudio.openshift.io/pipeline: '{"name":"docker-build-multi-platform-oci-ta","bundle":"latest"}'
      build.appstudio.openshift.io/request: configure-pac-no-mr
    name: ${COMPONENT_NAME}-{{.versionName}}
  spec:
    application: rhoai-{{.versionName}}
    build-nudges-ref:
      - odh-operator-{{.versionName}}
    componentName: ${COMPONENT_NAME}-{{.versionName}}
    containerImage: quay.io/rhoai/${COMPONENT_NAME}-rhel9
    source:
      git:
        context: ${CONTEXT_PATH_NORMALIZED}
        dockerfileUrl: ${DOCKERFILE_PATH}
        revision: "{{.branch}}"
        url: ${REPO_URL}
EOF
)
    uv run --script "$SCRIPTS_DIR/edit_yaml.py" append-pds-resource \
      "$PDS_FILE" \
      --yaml-string "$PDS_ENTRY" || {
      echo "ERROR in Step 8-RHOAI-1: Could not append to ProjectDevelopmentStream. Aborting." >&2
      exit 1
    }
  fi

  # 8-RHOAI-2: Stage RPA components
  STAGE_RPA_FILE="$CLONE_DIR/config/stone-prod-p02.hjvn.p1/product/ReleasePlanAdmission/rhoai/rhoai-onprem-${RPA_VAR}-components-stage.yaml"
  if [[ ! -f "$STAGE_RPA_FILE" ]]; then
    echo "ERROR in Step 8 (RHOAI): rhoai-onprem-${RPA_VAR}-components-stage.yaml not found." >&2
    echo "  Sprint onboarding for version '${VERSION_NAME}' is pending." >&2
    exit 1
  fi

  if grep -q "name: ${COMPONENT_NAME}-${RPA_VAR}" "$STAGE_RPA_FILE" 2>/dev/null; then
    echo "Entry already present in stage RPA -- skipping."
  else
    uv run --script "$SCRIPTS_DIR/edit_yaml.py" append-rpa-component \
      "$STAGE_RPA_FILE" \
      --array-key "spec.data.mapping.components" \
      --name "${COMPONENT_NAME}-${RPA_VAR}" \
      --url "registry.stage.redhat.io/rhoai/${COMPONENT_NAME}-rhel9"
  fi

  # 8-RHOAI-3: Prod RPA components
  PROD_RPA_FILE="$CLONE_DIR/config/stone-prod-p02.hjvn.p1/product/ReleasePlanAdmission/rhoai/rhoai-onprem-${RPA_VAR}-components-prod.yaml"
  if [[ ! -f "$PROD_RPA_FILE" ]]; then
    echo "ERROR in Step 8 (RHOAI): rhoai-onprem-${RPA_VAR}-components-prod.yaml not found." >&2
    echo "  Sprint onboarding for version '${VERSION_NAME}' is pending." >&2
    exit 1
  fi

  if grep -q "name: ${COMPONENT_NAME}-${RPA_VAR}" "$PROD_RPA_FILE" 2>/dev/null; then
    echo "Entry already present in prod RPA -- skipping."
  else
    uv run --script "$SCRIPTS_DIR/edit_yaml.py" append-rpa-component \
      "$PROD_RPA_FILE" \
      --array-key "spec.data.mapping.components" \
      --name "${COMPONENT_NAME}-${RPA_VAR}" \
      --url "registry.redhat.io/rhoai/${COMPONENT_NAME}-rhel9"
  fi

  # 8-RHOAI-4: Automation resources
  AUTOMATION_FILE="$CLONE_DIR/tenants-config/cluster/stone-prod-p02/tenants/rhoai-tenant/automation/resources.yaml"
  if [[ ! -f "$AUTOMATION_FILE" ]]; then
    echo "ERROR in Step 8 (RHOAI): automation/resources.yaml not found." >&2
    exit 1
  fi

  if grep -q "name: pull-request-pipelines-${COMPONENT_NAME}" "$AUTOMATION_FILE" 2>/dev/null; then
    echo "Pull-request pipeline entry already present -- skipping."
  else
    AUTOMATION_YAML=$(cat <<EOF
---
apiVersion: appstudio.redhat.com/v1alpha1
kind: Component
metadata:
  annotations:
    build.appstudio.openshift.io/request: configure-pac-no-mr
    build.appstudio.openshift.io/pipeline: '{"name":"docker-build-multi-platform-oci-ta","bundle":"latest"}'
  name: pull-request-pipelines-${COMPONENT_NAME}
spec:
  application: automation
  componentName: pull-request-pipelines-${COMPONENT_NAME}
  containerImage: quay.io/rhoai/pull-request-pipelines
  source:
    git:
      context: ${CONTEXT_PATH_NORMALIZED}
      dockerfileUrl: ${DOCKERFILE_PATH}
      url: ${REPO_URL}
EOF
)
    uv run --script "$SCRIPTS_DIR/edit_yaml.py" append-yaml-doc \
      "$AUTOMATION_FILE" \
      --yaml-string "$AUTOMATION_YAML" || {
      echo "ERROR in Step 8-RHOAI-4: Could not append to automation/resources.yaml. Aborting." >&2
      exit 1
    }

    grep -q "name: pull-request-pipelines-${COMPONENT_NAME}" "$AUTOMATION_FILE" \
      || { echo "ERROR: pull-request-pipelines-${COMPONENT_NAME} not found in automation/resources.yaml after append." >&2; exit 1; }
  fi
fi

# ── Build and verify manifests ───────────────────────────────────────────────

cd "$CLONE_DIR/tenants-config"
./build-manifests.sh "$KUSTOMIZE_BIN" || {
  echo "ERROR in Step 8d (build-manifests): Manifest generation failed. See output above." >&2
  exit 1
}

cd "$CLONE_DIR"
yamllint -s -f colored .gitlab-ci.yml .gitlab tenants-config/cluster || {
  echo "WARN: yamllint reported issues. Attempting to continue." >&2
}

# Stage and commit
cd "$CLONE_DIR"
git add -A
git -c commit.gpgsign=false commit -m "Add $KONFLUX_COMPONENT_NAME Component to konflux-release-data"

cd "$CLONE_DIR/tenants-config"
./verify-manifests.sh "$KUSTOMIZE_BIN" || {
  echo "ERROR in Step 8g (verify-manifests): Manifest verification failed. See output above." >&2
  exit 1
}

# Push
cd "$CLONE_DIR"
git push origin "$DEST_BRANCH" || {
  echo "Attempting unshallow fetch and retry..."
  git fetch --unshallow origin
  git push origin "$DEST_BRANCH" || {
    echo "ERROR: Push failed after unshallow. See details above." >&2
    exit 1
  }
}

# ── Raise MR (up to 3 attempts) ─────────────────────────────────────────────

MR_URL=""
for ATTEMPT in 1 2 3; do
  echo "Raising MR (attempt $ATTEMPT/3)..."
  set +e
  MR_URL=$(GITLAB_SSL_VERIFY=false uv run --script "$SCRIPTS_DIR/raise_gitlab_mr.py" \
    --src-url "$KRD_URL" \
    --src-branch "$DEST_BRANCH" \
    --dest-url "$KRD_URL" \
    --dest-branch main \
    --title "Add $KONFLUX_COMPONENT_NAME Component for $COMPONENT_NAME" \
    --description "Add Konflux Component '$KONFLUX_COMPONENT_NAME' to $TARGET_YAML.

Product: $PRODUCT_CONTEXT
Application: $KRD_APPLICATION
Container image: quay.io/$QUAY_ORG/$COMPONENT_NAME
Source repo: $REPO_URL @ $REPO_BRANCH
Jira: $JIRA_URL")
  MR_RC=$?
  set -e

  if [[ $MR_RC -eq 0 && -n "$MR_URL" ]]; then
    break
  fi

  echo "MR creation failed (attempt $ATTEMPT/3)." >&2
  if [[ $ATTEMPT -eq 3 ]]; then
    echo "ERROR in Step 9 (Raise MR): Could not create MR after 3 attempts. See errors above. Aborting." >&2
    exit 1
  fi
  sleep 5
done

# ── Jira updates ─────────────────────────────────────────────────────────────

uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
  --add-label "krd-mr-raised" \
  --comment "GitLab MR raised to create Konflux Component '$KONFLUX_COMPONENT_NAME'.

MR URL: $MR_URL

The Component will be provisioned on the Konflux cluster once this MR is merged."

# ── Done ──────────────────────────────────────────────────────────────────────

echo "MR raised: $MR_URL"
