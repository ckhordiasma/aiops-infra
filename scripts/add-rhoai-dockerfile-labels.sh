#!/usr/bin/env bash
# add-rhoai-dockerfile-labels.sh — Check/add mandatory RHOAI Dockerfile labels
#
# Usage:
#   ./scripts/add-rhoai-dockerfile-labels.sh [--jira-url <url>]
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN
#
# Required when --jira-url is provided:
#   JIRA_USER_EMAIL, JIRA_API_TOKEN

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────
JIRA_URL=""
JIRA_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jira-url) JIRA_URL="$2"; shift 2 ;;
    *)
      if [[ -z "$JIRA_URL" && "$1" == *"/browse/"* ]]; then
        JIRA_URL="$1"; shift
      else
        echo "Unknown argument: $1" >&2; exit 1
      fi
      ;;
  esac
done

eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "${JIRA_URL:-}")"

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
eval "$(bash "$SCRIPTS_DIR/parse_component_details.sh" \
  --workdir     "$WORKDIR" \
  --jira-id     "${JIRA_ID:-}" \
  --scripts-dir "$SCRIPTS_DIR")"

YAML_FILE="$WORKDIR/component_onboarding_details.yaml"
CONTEXT_PATH=$(grep -m1   'context_path:'     "$YAML_FILE" | awk '{print $2}')
DOCKERFILE_PATH=$(grep -m1 'dockerfile_path:' "$YAML_FILE" | awk '{print $2}')

for _field in CONTEXT_PATH DOCKERFILE_PATH; do
  [[ -z "${!_field:-}" ]] && {
    echo "ERROR: Missing required field '$_field'." >&2; exit 1
  }
done

# Derive paths
CLEAN_CTX="${CONTEXT_PATH#./}"
if [[ -z "$CLEAN_CTX" || "$CLEAN_CTX" == "." ]]; then
  DOCKERFILE_REPO_PATH="$DOCKERFILE_PATH"
else
  DOCKERFILE_REPO_PATH="${CLEAN_CTX}/${DOCKERFILE_PATH}"
fi

REPO_PATH=$(echo "$REPO_URL" | sed 's|https://github.com/||;s|\.git$||')

LABEL_NAME="rhoai/${COMPONENT_NAME}-rhel9"
LABEL_COMPONENT="${COMPONENT_NAME}-rhel9"
LABEL_DEFAULT="$COMPONENT_NAME"

echo "DOCKERFILE_REPO_PATH: $DOCKERFILE_REPO_PATH"
echo "Expected name label: $LABEL_NAME"

# ── Fast-path label check ─────
DOCKERFILE_TMPFILE=$(mktemp)
HTTP_STATUS=$(curl -s -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3.raw" \
  "https://api.github.com/repos/${REPO_PATH}/contents/${DOCKERFILE_REPO_PATH}?ref=main" \
  -o "$DOCKERFILE_TMPFILE" 2>/dev/null || echo "000")

if [[ "$HTTP_STATUS" == "200" ]]; then
  MISSING_LABELS=""
  grep -q "name=\"${LABEL_NAME}\"" "$DOCKERFILE_TMPFILE" || MISSING_LABELS="${MISSING_LABELS}name,"
  grep -q "com.redhat.component=\"${LABEL_COMPONENT}\"" "$DOCKERFILE_TMPFILE" || MISSING_LABELS="${MISSING_LABELS}com.redhat.component,"
  grep -q "summary=\"${LABEL_DEFAULT}\"" "$DOCKERFILE_TMPFILE" || MISSING_LABELS="${MISSING_LABELS}summary,"
  grep -q "description=\"${LABEL_DEFAULT}\"" "$DOCKERFILE_TMPFILE" || MISSING_LABELS="${MISSING_LABELS}description,"
  grep -q "maintainer=\"${LABEL_DEFAULT}\"" "$DOCKERFILE_TMPFILE" || MISSING_LABELS="${MISSING_LABELS}maintainer,"
  grep -q "io.k8s.display-name=\"${LABEL_DEFAULT}\"" "$DOCKERFILE_TMPFILE" || MISSING_LABELS="${MISSING_LABELS}io.k8s.display-name,"
  grep -q "io.k8s.description=\"${LABEL_DEFAULT}\"" "$DOCKERFILE_TMPFILE" || MISSING_LABELS="${MISSING_LABELS}io.k8s.description,"

  if [[ -z "$MISSING_LABELS" ]]; then
    echo "All 7 mandatory RHOAI labels are already correct."
    if [[ -n "$JIRA_URL" ]]; then
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --add-label "dockerfile-labels-present" \
        --comment "All mandatory RHOAI Dockerfile labels are already present in ${DOCKERFILE_REPO_PATH}. No changes needed."
    fi
    rm -f "$DOCKERFILE_TMPFILE"
    exit 0
  fi

  echo "Missing/incorrect labels: ${MISSING_LABELS%,}"
fi
rm -f "$DOCKERFILE_TMPFILE"

# ── Set up playpen ────────────
cd "$WORKDIR"
PLAYPEN_OUTPUT=$(bash "$SCRIPTS_DIR/setup_github_playpen.sh" \
  --src-url "$REPO_URL" \
  --dest-url "$REPO_URL" \
  --src-branch main \
  ${JIRA_ID:+--dest-branch "$JIRA_ID"} \
  --sparse-files "$DOCKERFILE_REPO_PATH") || {
  echo "ERROR: Clone or push failed." >&2; exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)

# ── Add labels ────────────────
[[ -f "$CLONE_DIR/$DOCKERFILE_REPO_PATH" ]] || {
  echo "ERROR: Dockerfile not found at $CLONE_DIR/$DOCKERFILE_REPO_PATH." >&2; exit 1
}

uv run --script "$SCRIPTS_DIR/update_dockerfile_labels.py" \
  "$CLONE_DIR/$DOCKERFILE_REPO_PATH" \
  --name      "$LABEL_NAME" \
  --component "$LABEL_COMPONENT" \
  --default   "$LABEL_DEFAULT" || {
  echo "ERROR: Could not update Dockerfile labels." >&2; exit 1
}

grep -q "name=\"${LABEL_NAME}\"" "$CLONE_DIR/$DOCKERFILE_REPO_PATH" || {
  echo "ERROR: Verification failed." >&2; exit 1
}
echo "All mandatory RHOAI labels confirmed present."

# ── Commit and push ───────────
bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files     "$DOCKERFILE_REPO_PATH" \
  --message   "Add mandatory RHOAI Dockerfile labels for $COMPONENT_NAME

Adds the required OCI/Red Hat labels to $DOCKERFILE_REPO_PATH.

Related: ${JIRA_ID:-no-jira}" \
  --branch    "$DEST_BRANCH" || {
  echo "ERROR: Could not push." >&2; exit 1
}

# ── Raise PR (up to 3 attempts) ──
MAX_ATTEMPTS=3
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
    --src-url "$REPO_URL" \
    --src-branch "$DEST_BRANCH" \
    --dest-url "$REPO_URL" \
    --dest-branch main \
    --title "Add mandatory RHOAI Dockerfile labels for $COMPONENT_NAME" \
    --description "Adds the seven mandatory RHOAI OCI labels to \`${DOCKERFILE_REPO_PATH}\`.

| Label | Value |
|-------|-------|
| \`name\` | \`${LABEL_NAME}\` |
| \`com.redhat.component\` | \`${LABEL_COMPONENT}\` |
| \`summary\` | \`${LABEL_DEFAULT}\` |
| \`description\` | \`${LABEL_DEFAULT}\` |
| \`maintainer\` | \`${LABEL_DEFAULT}\` |
| \`io.k8s.display-name\` | \`${LABEL_DEFAULT}\` |
| \`io.k8s.description\` | \`${LABEL_DEFAULT}\` |

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
    --add-label "dockerfile-labels-pr-raised" \
    --comment "GitHub PR raised to add mandatory RHOAI Dockerfile labels for '$COMPONENT_NAME'.

PR URL: $PR_URL
File changed: $DOCKERFILE_REPO_PATH"
fi

echo ""
echo "Done."
echo "  PR raised: $PR_URL"
