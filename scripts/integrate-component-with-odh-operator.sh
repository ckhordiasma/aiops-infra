#!/usr/bin/env bash
# integrate-component-with-odh-operator.sh — Add component to operator manifests-config.yaml
#
# Usage:
#   ./scripts/integrate-component-with-odh-operator.sh --jira-url <url> [--existing-pr-url <url>]
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN, JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional:
#   ODH_OPERATOR_REPO_URL — override target operator repo

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

eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "${JIRA_URL:-}")"
[[ -z "$JIRA_URL" ]] && {
  echo "ERROR: Jira URL is required." >&2; exit 1
}

# ── Check prerequisites ──────
bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "GITHUB_USER GITHUB_TOKEN JIRA_USER_EMAIL JIRA_API_TOKEN" \
  --tools "uv git"

# ── Set up working directory ──
eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "$JIRA_URL")"
echo "Working directory: $WORKDIR"

# ── Fetch Jira and component YAML ──
if [[ ! -f "$WORKDIR/component_onboarding_details.json" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL" || {
    echo "ERROR: Could not fetch Jira details." >&2; exit 1
  }
fi

if [[ ! -f "$WORKDIR/component_onboarding_details.yaml" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
    "$JIRA_URL" component_onboarding_details.yaml || {
    echo "ERROR: Could not download YAML." >&2; exit 1
  }
fi

# ── Parse YAML ────────────────
YAML_FILE="$WORKDIR/component_onboarding_details.yaml"
COMPONENT_NAME=$(grep -m1 'component_name:' "$YAML_FILE" | awk '{print $2}')
PRODUCT_CONTEXT=$(grep -m1 'product_context:' "$YAML_FILE" | awk '{print $2}')
IS_OPERATOR=$(grep -m1 'is_operator:' "$YAML_FILE" | awk '{print $2}')
OPERATOR_MANIFEST_SRC_PATH=$(grep -m1 'operator_manifest_src_path:' "$YAML_FILE" | awk '{print $2}')
OPERATOR_MANIFEST_DEST_PATH=$(grep -m1 'operator_manifest_dest_path:' "$YAML_FILE" | awk '{print $2}')
REPO_URL=$(grep -m1 'repo_url:' "$YAML_FILE" | awk '{print $2}')
REPO_BRANCH=$(grep -m1 'repo_branch:' "$YAML_FILE" | awk '{print $2}')

for _field in COMPONENT_NAME PRODUCT_CONTEXT IS_OPERATOR REPO_URL REPO_BRANCH; do
  [[ -z "${!_field:-}" ]] && {
    echo "ERROR: Missing required field '$_field'." >&2; exit 1
  }
done

# Resolve operator URL
eval "$(bash "$SCRIPTS_DIR/resolve_operator_url.sh" \
  --product-context "$PRODUCT_CONTEXT")" || {
  echo "ERROR: Could not resolve operator URL." >&2; exit 1
}
echo "ODH_OPERATOR_URL:  $ODH_OPERATOR_URL"
echo "ODH_OPERATOR_PATH: $ODH_OPERATOR_PATH"

# ── is_operator gate ──────────
if [[ "${IS_OPERATOR,,}" == "false" ]]; then
  echo "$COMPONENT_NAME is not an operator (is_operator=false). No changes needed."
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "operator-changes-not-needed" \
    --comment "Skipping odh-operator integration for '$COMPONENT_NAME'. is_operator=false."
  exit 0
fi

# Validate operator fields
for _field in OPERATOR_MANIFEST_SRC_PATH OPERATOR_MANIFEST_DEST_PATH; do
  [[ -z "${!_field:-}" ]] && {
    echo "ERROR: is_operator=true but '$_field' is missing." >&2; exit 1
  }
done

# ── Fast-path check ───────────
MANIFESTS_TMPFILE=$(mktemp)
HTTP_STATUS=$(curl -s -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3.raw" \
  "https://api.github.com/repos/${ODH_OPERATOR_PATH}/contents/build/manifests-config.yaml?ref=main" \
  -o "$MANIFESTS_TMPFILE" 2>/dev/null || echo "000")

if [[ "$HTTP_STATUS" == "200" ]] && grep -q "^  ${COMPONENT_NAME}:" "$MANIFESTS_TMPFILE"; then
  echo "$COMPONENT_NAME already exists in manifests-config.yaml."
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "odh-operator-pr-raised" \
    --comment "'$COMPONENT_NAME' is already present in build/manifests-config.yaml. No changes needed."
  rm -f "$MANIFESTS_TMPFILE"
  exit 0
fi
rm -f "$MANIFESTS_TMPFILE"

# ── Set up playpen ────────────
cd "$WORKDIR"
PLAYPEN_OUTPUT=$(bash "$SCRIPTS_DIR/setup_github_playpen.sh" \
  --src-url "$ODH_OPERATOR_URL" \
  --src-branch main \
  --dest-branch "$JIRA_ID" \
  --sparse-files "build") || {
  echo "ERROR: Clone or push failed." >&2; exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)

# ── Update manifests-config.yaml ──
[[ -f "$CLONE_DIR/build/manifests-config.yaml" ]] || {
  echo "ERROR: build/manifests-config.yaml not found." >&2; exit 1
}

if grep -q "^  ${COMPONENT_NAME}:" "$CLONE_DIR/build/manifests-config.yaml" 2>/dev/null; then
  echo "$COMPONENT_NAME already in manifests-config.yaml — skipping edit."
else
  uv run --script "$SCRIPTS_DIR/edit_yaml.py" insert-map-key \
    "$CLONE_DIR/build/manifests-config.yaml" \
    --map-key "map" \
    --name "$COMPONENT_NAME" \
    --src  "$OPERATOR_MANIFEST_SRC_PATH" \
    --dest "$OPERATOR_MANIFEST_DEST_PATH" || {
    echo "ERROR: Could not insert component entry." >&2; exit 1
  }
fi

grep -q "^  ${COMPONENT_NAME}:" "$CLONE_DIR/build/manifests-config.yaml" || {
  echo "ERROR: $COMPONENT_NAME not found after insert." >&2; exit 1
}

# ── Commit and push ───────────
bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files     "build/manifests-config.yaml" \
  --message   "Add $COMPONENT_NAME to manifests-config.yaml" \
  --branch    "$DEST_BRANCH" || {
  echo "ERROR: Could not commit or push." >&2; exit 1
}

# ── Raise PR (up to 3 attempts) ──
MAX_ATTEMPTS=3
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
    --src-url "$ODH_OPERATOR_URL" \
    --src-branch "$DEST_BRANCH" \
    --dest-url "$ODH_OPERATOR_URL" \
    --dest-branch main \
    --title "Add $COMPONENT_NAME to manifests-config.yaml" \
    --description "Adds '$COMPONENT_NAME' to the operator manifests config map.

Component: $COMPONENT_NAME
Manifest source path: $OPERATOR_MANIFEST_SRC_PATH
Manifest dest path:   $OPERATOR_MANIFEST_DEST_PATH
Upstream repo: $REPO_URL @ $REPO_BRANCH
Jira: $JIRA_URL

**File changed:**
- \`build/manifests-config.yaml\` — added \`$COMPONENT_NAME\` entry under \`map:\`" 2>&1) && break

  echo "PR creation attempt $attempt failed: $PR_URL"
  if [[ $attempt -eq $MAX_ATTEMPTS ]]; then
    echo "ERROR: Could not create PR after $MAX_ATTEMPTS attempts." >&2; exit 1
  fi
  sleep 5
done

# ── Jira update ───────────────
uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
  --add-label "operator-pr-raised" \
  --comment "GitHub PR raised to add '$COMPONENT_NAME' to ${ODH_OPERATOR_PATH} manifests config.

PR URL: $PR_URL
File changed: build/manifests-config.yaml"

echo ""
echo "Done."
echo "  PR raised: $PR_URL"
