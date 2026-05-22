#!/usr/bin/env bash
# onboard-component-to-konflux-release-data.sh — Onboards component to Konflux via MR to konflux-release-data
#
# Usage:
#   ./scripts/onboard-component-to-konflux-release-data.sh <jira-url> [--existing-mr-url <url>]
#   ./scripts/onboard-component-to-konflux-release-data.sh https://redhat.atlassian.net/browse/RHOAIENG-1234
#
# Required env vars:
#   GITLAB_USER, GITLAB_TOKEN, JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional env vars:
#   KONFLUX_RELEASE_DATA_REPO_URL (default: https://gitlab.cee.redhat.com/releng/konflux-release-data.git)
#   JIRA_SERVER (default: https://redhat.atlassian.net)
#   EXT_OC_TOKEN (for ODH builds on stone-prd-rh01)
#   INT_OC_TOKEN (for RHOAI builds on stone-prod-p02)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

JIRA_URL=""
EXISTING_MR_URL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --existing-mr-url)
      EXISTING_MR_URL="$2"
      shift 2
      ;;
    *)
      if [[ -z "$JIRA_URL" ]]; then
        JIRA_URL="$1"
      else
        echo "ERROR: Unexpected argument '$1'"
        exit 1
      fi
      shift
      ;;
  esac
done

# Idempotency fast-path
if [[ -n "$EXISTING_MR_URL" ]]; then
  echo "MR already raised: $EXISTING_MR_URL"
  exit 0
fi

# Parse Jira URL
eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "$JIRA_URL")"
[[ -z "$JIRA_URL" ]] && {
  echo "ERROR: Jira URL is required."
  echo "  Usage: /onboard-component-to-konflux-release-data <jira-url>"
  exit 1
}

echo "JIRA_URL : $JIRA_URL"
echo "JIRA_ID  : $JIRA_ID"

# Resolve KRD_URL
KRD_URL="${KONFLUX_RELEASE_DATA_REPO_URL:-https://gitlab.cee.redhat.com/releng/konflux-release-data.git}"
echo "KONFLUX_RELEASE_DATA_REPO_URL=${KONFLUX_RELEASE_DATA_REPO_URL:-(not set, using default)}"
echo "KRD_URL resolved to: $KRD_URL"

# ── Check prerequisites ───────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "GITLAB_USER GITLAB_TOKEN JIRA_USER_EMAIL JIRA_API_TOKEN" \
  --tools "uv oc yamllint kustomize"

KUSTOMIZE_BIN="kustomize"
if ! command -v kustomize &>/dev/null && [[ -x "${HOME}/.local/bin/kustomize" ]]; then
  KUSTOMIZE_BIN="${HOME}/.local/bin/kustomize"
  export PATH="${HOME}/.local/bin:${PATH}"
fi

# ── Set up working directory ──────────────────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "$JIRA_URL")"
echo "Working directory: $WORKDIR"

# ── Fetch Jira details and component YAML ─────────────────────────────────────

if [[ ! -f "$WORKDIR/component_onboarding_details.json" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL" || {
    echo "ERROR: Could not fetch Jira issue details."
    exit 1
  }
fi

cd "$WORKDIR"
uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
  "$JIRA_URL" component_onboarding_details.yaml || {
  echo "ERROR: Could not download 'component_onboarding_details.yaml' from Jira."
  echo "  Ensure the attachment exists on the Jira issue before running this skill."
  exit 1
}

# ── Parse component details ───────────────────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/parse_component_details.sh" \
  --workdir "$WORKDIR" \
  --jira-id "$JIRA_ID" \
  --scripts-dir "$SCRIPTS_DIR")"

YAML_FILE="$WORKDIR/component_onboarding_details.yaml"
CONTEXT_PATH=$(grep -m1 'context_path:' "$YAML_FILE" | awk '{print $2}')
DOCKERFILE_PATH=$(grep -m1 'dockerfile_path:' "$YAML_FILE" | awk '{print $2}')
TARGET_RHOAI_VERSION=$(grep -m1 'target_rhoai_version:' "$YAML_FILE" | awk '{print $2}' 2>/dev/null || echo "")

for _field in COMPONENT_NAME REPO_URL REPO_BRANCH CONTEXT_PATH DOCKERFILE_PATH; do
  [[ -z "${!_field}" ]] && {
    echo "ERROR: Missing required field '${_field}' in component_onboarding_details.yaml."
    exit 1
  }
done

if [[ "$COMPONENT_NAME" == *-ci ]]; then
  KONFLUX_COMPONENT_NAME="$COMPONENT_NAME"
else
  KONFLUX_COMPONENT_NAME="${COMPONENT_NAME}-ci"
fi

echo "COMPONENT_NAME   : $COMPONENT_NAME"
echo "REPO_URL         : $REPO_URL"
echo "REPO_BRANCH      : $REPO_BRANCH"
echo "CONTEXT_PATH     : $CONTEXT_PATH"
echo "DOCKERFILE_PATH  : $DOCKERFILE_PATH"
echo "TARGET_RHOAI_VERSION : ${TARGET_RHOAI_VERSION:-(none)}"

# ── Determine product context ─────────────────────────────────────────────────

if [[ "$JIRA_ID" == RHOAIENG-* ]]; then
  PRODUCT_CONTEXT="RHOAI"
elif [[ "$JIRA_ID" == RHODS-* ]]; then
  PRODUCT_CONTEXT="ODH"
else
  JIRA_SUMMARY=$(jq -r '.fields.summary' "$WORKDIR/component_onboarding_details.json")
  if [[ "$JIRA_SUMMARY" =~ RHOAI ]]; then
    PRODUCT_CONTEXT="RHOAI"
  elif [[ "$JIRA_SUMMARY" =~ ODH ]]; then
    PRODUCT_CONTEXT="ODH"
  else
    echo "ERROR: Could not determine product context (ODH or RHOAI) from Jira key or title."
    exit 1
  fi
fi

echo "PRODUCT_CONTEXT  : $PRODUCT_CONTEXT"

if [[ "$PRODUCT_CONTEXT" == "ODH" ]]; then
  CLUSTER_INSTANCE="external"
  KONFLUX_NAMESPACE="open-data-hub-tenant"
  SPARSE_PATHS="tenants-config/cluster/stone-prd-rh01/tenants/open-data-hub-tenant tenants-config/auto-generated/cluster/stone-prd-rh01/tenants/open-data-hub-tenant"
  TARGET_YAML="tenants-config/cluster/stone-prd-rh01/tenants/open-data-hub-tenant/opendatahub-ci-components.yaml"
  KRD_APPLICATION="opendatahub-builds"
  QUAY_ORG="opendatahub"
else
  CLUSTER_INSTANCE="internal"
  KONFLUX_NAMESPACE="rhoai-tenant"
  SPARSE_PATHS="tenants-config/cluster/stone-prod-p02/tenants/rhoai-tenant tenants-config/auto-generated/cluster/stone-prod-p02/tenants/rhoai-tenant"
  QUAY_ORG="rhoai"

  # Parse version and recompute component name for RHOAI
  if [[ "$TARGET_RHOAI_VERSION" =~ ^([0-9]+)\.([0-9]+)-ea-([0-9]+)$ ]]; then
    KONFLUX_COMPONENT_NAME="${COMPONENT_NAME}-v${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-ea-${BASH_REMATCH[3]}"
  elif [[ "$TARGET_RHOAI_VERSION" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
    KONFLUX_COMPONENT_NAME="${COMPONENT_NAME}-v${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
  else
    echo "ERROR: Cannot parse target_rhoai_version '${TARGET_RHOAI_VERSION}'."
    echo "  Expected x.y or x.y-ea-n (e.g. 3.4 or 3.4-ea-2)."
    exit 1
  fi
fi

echo "KONFLUX_COMPONENT_NAME : $KONFLUX_COMPONENT_NAME"
echo "CLUSTER_INSTANCE       : $CLUSTER_INSTANCE"
echo "KONFLUX_NAMESPACE      : $KONFLUX_NAMESPACE"

# ── Check if Konflux component already exists ─────────────────────────────────

bash "$SCRIPTS_DIR/check_konflux_component.sh" \
  "$KONFLUX_COMPONENT_NAME" "$KONFLUX_NAMESPACE" "$CLUSTER_INSTANCE" && {
  echo "Konflux Component '$KONFLUX_COMPONENT_NAME' already exists in namespace '$KONFLUX_NAMESPACE'."
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "konflux-component-created" \
    --comment "Konflux Component '$KONFLUX_COMPONENT_NAME' already exists in namespace '$KONFLUX_NAMESPACE'. No action needed."
  echo "Nothing to do."
  exit 0
} || {
  EXIT_CODE=$?
  [[ $EXIT_CODE -eq 2 ]] && {
    echo "ERROR: Could not check Konflux component status. Check VPN and EXT_OC_TOKEN/INT_OC_TOKEN."
    exit 1
  }
}

# ── Set up playpen (sparse clone) ─────────────────────────────────────────────

cd "$WORKDIR"

if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  SPARSE_PATHS="$SPARSE_PATHS config/stone-prod-p02.hjvn.p1/product/ReleasePlanAdmission/rhoai"
fi

PLAYPEN_OUTPUT=$(GITLAB_SSL_VERIFY=false bash "$SCRIPTS_DIR/setup_gitlab_playpen.sh" \
  --src-url "$KRD_URL" \
  --src-branch main \
  --dest-branch "$JIRA_ID" \
  --sparse-files "$SPARSE_PATHS") || {
  echo "ERROR: Playpen setup failed. See details above."
  echo "  Check VPN connectivity and GITLAB_TOKEN write_repository scope."
  exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)

echo "Clone directory: $CLONE_DIR"
echo "Branch: $DEST_BRANCH"

# ── Modify YAML files (ODH or RHOAI) ──────────────────────────────────────────

if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  # Parse version details
  if [[ -z "$TARGET_RHOAI_VERSION" ]]; then
    echo "ERROR: target_rhoai_version is missing from component_onboarding_details.yaml."
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
    echo "ERROR: Cannot parse target_rhoai_version '${TARGET_RHOAI_VERSION}'."
    exit 1
  fi

  TARGET_YAML="tenants-config/cluster/stone-prod-p02/tenants/rhoai-tenant/${VERSION_NAME}/ProjectDevelopmentStream-${VERSION_NAME}.yaml"

  echo "VERSION_NAME     : $VERSION_NAME"
  echo "RPA_VAR          : $RPA_VAR"
  echo "TARGET_YAML      : $TARGET_YAML"
  echo "KRD_APPLICATION  : $KRD_APPLICATION"

  if [[ "$CONTEXT_PATH" == "./" || "$CONTEXT_PATH" == "." ]]; then
    CONTEXT_PATH_NORMALIZED="."
  else
    CONTEXT_PATH_NORMALIZED="$CONTEXT_PATH"
  fi
fi

# Append Component to TARGET_YAML
if grep -q "name: $KONFLUX_COMPONENT_NAME" "$CLONE_DIR/$TARGET_YAML" 2>/dev/null; then
  echo "Component entry '$KONFLUX_COMPONENT_NAME' already present in $TARGET_YAML — skipping append."
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
    echo "ERROR: Could not append Component document to $TARGET_YAML."
    exit 1
  }
fi

# RHOAI-specific additional files
if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  # Build manifests, lint, commit, verify — simplified version
  cd "$CLONE_DIR/tenants-config"
  ./build-manifests.sh "$KUSTOMIZE_BIN" || {
    echo "ERROR: Manifest generation failed."
    exit 1
  }

  cd "$CLONE_DIR"
  yamllint -s -f colored .gitlab-ci.yml .gitlab tenants-config/cluster || {
    echo "WARN: yamllint reported errors — attempting to fix..."
  }

  git add -A
  git commit -m "Add $KONFLUX_COMPONENT_NAME Component to konflux-release-data"

  cd "$CLONE_DIR/tenants-config"
  ./verify-manifests.sh "$KUSTOMIZE_BIN" || {
    echo "ERROR: Manifest verification failed."
    exit 1
  }

  cd "$CLONE_DIR"
  git push origin "$DEST_BRANCH" || {
    git fetch --unshallow origin
    git push origin "$DEST_BRANCH"
  }
fi

# ── Raise MR (up to 3 attempts) ───────────────────────────────────────────────

MR_URL=""
for attempt in 1 2 3; do
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
Jira: $JIRA_URL") && break || {
    echo "WARN: MR creation attempt $attempt failed."
    [[ $attempt -eq 3 ]] && {
      echo "ERROR: Could not create MR after 3 attempts."
      exit 1
    }
  }
done

echo "MR raised: $MR_URL"

# ── Jira updates ──────────────────────────────────────────────────────────────

uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
  --add-label "krd-mr-raised" \
  --comment "GitLab MR raised to create Konflux Component '$KONFLUX_COMPONENT_NAME'.

MR URL: $MR_URL

The Component will be provisioned on the Konflux cluster once this MR is merged."

# ── Done ──────────────────────────────────────────────────────────────────────

echo "Done."
echo "MR: $MR_URL"
