#!/usr/bin/env bash
# create-pull-pipelines-in-rhoai-konflux-central.sh — Add pull-request PipelineRun to rhoai-konflux-central
#
# Usage:
#   ./scripts/create-pull-pipelines-in-rhoai-konflux-central.sh [--jira-url <url>] [--existing-pr-url <url>]
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN
#
# Required when --jira-url is provided:
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional:
#   RHOAI_KONFLUX_CENTRAL_REPO_URL — override default repo URL

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────
JIRA_URL=""
JIRA_ID=""
EXISTING_PR_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jira-url)        JIRA_URL="$2"; shift 2 ;;
    --existing-pr-url) EXISTING_PR_URL="$2"; shift 2 ;;
    --workdir)         WORKDIR="$2"; shift 2 ;;
    *)
      if [[ -z "$JIRA_URL" && "$1" == *"/browse/"* ]]; then
        JIRA_URL="$1"; shift
      else
        echo "Unknown argument: $1" >&2; exit 1
      fi
      ;;
  esac
done

if [[ -n "$EXISTING_PR_URL" ]]; then
  echo "PR already raised: $EXISTING_PR_URL"
  exit 0
fi

if [[ -n "$JIRA_URL" && "$JIRA_URL" != *"/browse/"* ]]; then
  echo "ERROR: Invalid Jira URL." >&2; exit 1
fi
[[ -n "$JIRA_URL" ]] && JIRA_ID="${JIRA_URL##*/}"

RKC_URL="${RHOAI_KONFLUX_CENTRAL_REPO_URL:-https://github.com/red-hat-data-services/konflux-central.git}"
echo "RKC_URL resolved to: $RKC_URL"
RKC_PATH=$(echo "$RKC_URL" | sed 's|https://github.com/||;s|\.git$||')

# ── Check prerequisites ──────
bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "GITHUB_USER GITHUB_TOKEN" \
  --tools "uv git curl"

if [[ -n "$JIRA_URL" ]]; then
  bash "$SCRIPTS_DIR/check_prerequisites.sh" \
    --env "JIRA_USER_EMAIL JIRA_API_TOKEN"
fi

# ── Set up working directory ──
eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "${JIRA_URL:-}")"
echo "Working directory: $WORKDIR"

# ── Get component YAML ────────
if [[ -f "$WORKDIR/component_onboarding_details.yaml" ]]; then
  echo "Using existing component_onboarding_details.yaml."
elif [[ -n "$JIRA_URL" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
    "$JIRA_URL" component_onboarding_details.yaml || {
    echo "ERROR: Could not download YAML." >&2; exit 1
  }
else
  echo "ERROR: No YAML found and no Jira URL provided." >&2; exit 1
fi

if [[ -n "$JIRA_URL" && ! -f "$WORKDIR/component_onboarding_details.json" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL" || true
fi

# ── Parse YAML ────────────────
YAML_FILE="$WORKDIR/component_onboarding_details.yaml"
COMPONENT_NAME=$(grep -m1 'component_name:' "$YAML_FILE" | awk '{print $2}')
REPO_URL=$(grep -m1 'repo_url:' "$YAML_FILE" | awk '{print $2}')
CONTEXT_PATH=$(grep -m1 'context_path:' "$YAML_FILE" | awk '{print $2}')
DOCKERFILE_PATH=$(grep -m1 'dockerfile_path:' "$YAML_FILE" | awk '{print $2}')

ARCHITECTURES=($(awk '/^  architectures:/{found=1;next} found && /^  - /{print $2} found && /^  [a-z]/{exit}' "$YAML_FILE"))
[[ ${#ARCHITECTURES[@]} -eq 0 ]] && ARCHITECTURES=($(grep -A20 'architectures:' "$YAML_FILE" | grep '^ *- ' | awk '{print $2}'))

for _field in COMPONENT_NAME REPO_URL CONTEXT_PATH DOCKERFILE_PATH; do
  [[ -z "${!_field:-}" ]] && {
    echo "ERROR: Missing required field '$_field'." >&2; exit 1
  }
done
[[ ${#ARCHITECTURES[@]} -eq 0 ]] && {
  echo "ERROR: Missing 'architectures' field." >&2; exit 1
}

# ── Derive variables ──────────
REPO_NAME="${REPO_URL##*/}"
REPO_NAME="${REPO_NAME%.git}"
PIPELINERUN_FILE="${COMPONENT_NAME}-pull-request.yaml"

if [[ "$CONTEXT_PATH" == "./" || "$CONTEXT_PATH" == "." ]]; then
  CONTEXT_PATH_NORMALIZED="."
else
  CONTEXT_PATH_NORMALIZED="$CONTEXT_PATH"
fi

PLATFORMS=()
for arch in "${ARCHITECTURES[@]}"; do
  case "$arch" in
    x86_64)  PLATFORMS+=("linux/x86_64") ;;
    arm64)   PLATFORMS+=("linux-m2xlarge/arm64") ;;
    ppc64le) PLATFORMS+=("linux/ppc64le") ;;
    s390x)   PLATFORMS+=("linux/s390x") ;;
    *) echo "WARN: Unknown architecture '$arch'" ;;
  esac
done
[[ ${#PLATFORMS[@]} -eq 0 ]] && { echo "ERROR: No valid architectures." >&2; exit 1; }

# ── Fast-path check ───────────
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${RKC_PATH}/contents/pipelineruns/${REPO_NAME}/.tekton/${PIPELINERUN_FILE}?ref=main" 2>/dev/null || echo "000")

if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "PipelineRun already exists. Nothing to do."
  if [[ -n "$JIRA_URL" ]]; then
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --add-label "rkc-pull-changes-done" \
      --comment "Pull-request PipelineRun '${PIPELINERUN_FILE}' already exists on 'main'."
  fi
  exit 0
fi

# ── Set up playpen ────────────
cd "$WORKDIR"
PLAYPEN_OUTPUT=$(bash "$SCRIPTS_DIR/setup_github_playpen.sh" \
  --src-url "$RKC_URL" \
  --src-branch "main" \
  ${JIRA_ID:+--dest-branch "$JIRA_ID"} \
  --sparse-files "pipelineruns/$REPO_NAME") || {
  echo "ERROR: Clone or push failed." >&2; exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)

# ── Create PipelineRun directory ──
TEKTON_DIR=$(find "$CLONE_DIR/pipelineruns/$REPO_NAME" -maxdepth 1 -iname ".tekton" -type d 2>/dev/null | head -1)
if [[ -z "$TEKTON_DIR" ]]; then
  TEKTON_DIR="$CLONE_DIR/pipelineruns/$REPO_NAME/.tekton"
  mkdir -p "$TEKTON_DIR"
fi
PIPELINERUN_PATH="$TEKTON_DIR/$PIPELINERUN_FILE"

# ── Detect prefetch-input ─────
eval "$(bash "$SCRIPTS_DIR/detect_prefetch_input.sh" \
  --repo-url "$REPO_URL" \
  --context-path "$CONTEXT_PATH_NORMALIZED")"

if [[ "$PREFETCH_INPUT" == "[]" ]]; then
  PREFETCH_PARAM_BLOCK=""
else
  PREFETCH_PARAM_BLOCK="  - name: prefetch-input
    value: |
      ${PREFETCH_INPUT}"
fi

# ── Write PipelineRun YAML ────
PLATFORM_LIST=""
for p in "${PLATFORMS[@]}"; do
  PLATFORM_LIST+="    - ${p}"$'\n'
done
PLATFORM_LIST="${PLATFORM_LIST%$'\n'}"

cat > "$PIPELINERUN_PATH" <<PIPELINERUN_EOF

apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  annotations:
    build.appstudio.openshift.io/repo: ${REPO_URL}?rev={{revision}}
    build.appstudio.redhat.com/commit_sha: '{{revision}}'
    build.appstudio.redhat.com/target_branch: '{{target_branch}}'
    build.appstudio.redhat.com/pull_request_number: "{{pull_request_number}}"
    pipelinesascode.tekton.dev/max-keep-runs: "3"
    pipelinesascode.tekton.dev/on-comment: "^/build-konflux"
    pipelinesascode.tekton.dev/on-label: "[kfbuild-all, kfbuild-${COMPONENT_NAME}]"
    pipelinesascode.tekton.dev/on-target-branch: "[{{target_branch}}]"
    pipelinesascode.tekton.dev/on-event: "[pull_request]"
    pipelinesascode.tekton.dev/cancel-in-progress: "true"
  labels:
    appstudio.openshift.io/application: automation
    appstudio.openshift.io/component: pull-request-pipelines-${COMPONENT_NAME}
    pipelines.appstudio.openshift.io/type: build
  name: ${COMPONENT_NAME}-on-pull-request-{{pull_request_number}}
  namespace: rhoai-tenant
spec:
  timeouts:
    pipeline: 8h
  params:
  - name: git-url
    value: '{{source_url}}'
  - name: revision
    value: '{{revision}}'
  - name: additional-tags
    value:
    - 'pr-{{pull_request_number}}-into-{{target_branch}}'
  - name: additional-labels
    value:
    - version=on-pr-{{revision}}
    - io.openshift.tags=${COMPONENT_NAME}
  - name: output-image
    value: quay.io/rhoai/pull-request-pipelines:${COMPONENT_NAME}-{{revision}}
  - name: build-platforms
    value:
${PLATFORM_LIST}
  - name: image-expires-after
    value: 5d
  - name: dockerfile
    value: ${DOCKERFILE_PATH}
  - name: path-context
    value: ${CONTEXT_PATH_NORMALIZED}
  - name: hermetic
    value: true
${PREFETCH_PARAM_BLOCK}
  - name: build-image-index
    value: true
  - name: enable-slack-failure-notification
    value: "false"
  - name: additional-build-secret
    value: "rhel-ai-private-index-auth"
  pipelineRef:
    resolver: git
    params:
    - name: url
      value: ${RKC_URL}
    - name: revision
      value: '{{ target_branch }}'
    - name: pathInRepo
      value: pipelines/multi-arch-container-build.yaml
  taskRunTemplate:
    serviceAccountName: build-pipeline-pull-request-pipelines
  workspaces:
  - name: git-auth
    secret:
      secretName: '{{ git_auth_secret }}'
status: {}
PIPELINERUN_EOF
echo "PipelineRun written to $PIPELINERUN_PATH"

# ── Commit and push ───────────
bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files     "pipelineruns/$REPO_NAME/.tekton/$PIPELINERUN_FILE" \
  --message   "Add ${COMPONENT_NAME} pull-request PipelineRun for ${REPO_NAME}

Adds Tekton pull-request PipelineRun for component '${COMPONENT_NAME}'.

Related: ${JIRA_ID:-no-jira}" \
  --branch    "$DEST_BRANCH" || {
  echo "ERROR: Could not push." >&2; exit 1
}

# ── Raise PR (up to 3 attempts) ──
MAX_ATTEMPTS=3
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
    --src-url "$RKC_URL" \
    --src-branch "$DEST_BRANCH" \
    --dest-url "$RKC_URL" \
    --dest-branch "main" \
    --title "Add ${COMPONENT_NAME} pull-request PipelineRun for ${REPO_NAME}" \
    --description "Adds Tekton pull-request PipelineRun for '${COMPONENT_NAME}'.

| Field | Value |
|-------|-------|
| Component | \`${COMPONENT_NAME}\` |
| Source repo | \`${REPO_URL}\` |
| File | \`pipelineruns/${REPO_NAME}/.tekton/${PIPELINERUN_FILE}\` |
| Platforms | ${PLATFORMS[*]} |

**Jira:** ${JIRA_URL:-(none)}" 2>&1) && break

  echo "PR creation attempt $attempt failed: $PR_URL"
  if [[ $attempt -eq $MAX_ATTEMPTS ]]; then
    echo "ERROR: Could not create PR after $MAX_ATTEMPTS attempts." >&2; exit 1
  fi
  sleep 5
done

# ── Jira update ───────────────
if [[ -n "$JIRA_URL" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "rkc-pull-pr-raised" \
    --comment "[step:pull_pipelines] GitHub PR raised to add pull-request PipelineRun for '${COMPONENT_NAME}'.

PR URL: $PR_URL
File: pipelineruns/${REPO_NAME}/.tekton/${PIPELINERUN_FILE}"
fi

echo ""
echo "Done."
echo "  PR raised: $PR_URL"
