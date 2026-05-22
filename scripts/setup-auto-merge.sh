#!/usr/bin/env bash
# setup-auto-merge.sh — Configure auto-merge for a component repo in rhods-devops-infra
#
# Usage:
#   ./scripts/setup-auto-merge.sh [--jira-url <url>] [--existing-pr-url <url>]
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN
#
# Required when --jira-url is provided:
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional:
#   RHODS_DEVOPS_INFRA_REPO_URL — override default repo URL

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

RDI_URL="${RHODS_DEVOPS_INFRA_REPO_URL:-https://github.com/red-hat-data-services/rhods-devops-infra.git}"
echo "RDI_URL resolved to: $RDI_URL"
RDI_PATH=$(echo "$RDI_URL" | sed 's|https://github.com/||;s|\.git$||')

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
REPO_URL=$(grep -m1 'repo_url:' "$WORKDIR/component_onboarding_details.yaml" | awk '{print $2}')
[[ -z "$REPO_URL" ]] && {
  echo "ERROR: Missing 'repo_url' field." >&2; exit 1
}

REPO_NAME="${REPO_URL##*/}"
REPO_NAME="${REPO_NAME%.git}"

eval "$(bash "$SCRIPTS_DIR/detect_repo_upstream.sh" --repo-url "$REPO_URL")"

echo "REPO_NAME        : $REPO_NAME"
echo "REPO_URL         : $REPO_URL"
echo "UPSTREAM_REPO_URL: $UPSTREAM_REPO_URL"

# ── Fast-path check ───────────
fetch_file_content() {
  local path="$1"
  curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${RDI_PATH}/contents/${path}?ref=main" \
    | python3 -c \
      "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d['content']).decode())" \
      2>/dev/null || true
}

USM_CONTENT=$(fetch_file_content "src/config/upstream-source-map.yaml")
MRSM_CONTENT=$(fetch_file_content "src/config/main-release-source-map.yaml")

USM_HAS_ENTRY=false
MRSM_HAS_ENTRY=false
[[ -n "$USM_CONTENT" ]] && echo "$USM_CONTENT" | grep -qF "name: ${REPO_NAME}" && USM_HAS_ENTRY=true
[[ -n "$MRSM_CONTENT" ]] && echo "$MRSM_CONTENT" | grep -qF "name: ${REPO_NAME}" && MRSM_HAS_ENTRY=true

if [[ "$USM_HAS_ENTRY" == "true" && "$MRSM_HAS_ENTRY" == "true" ]]; then
  echo "Entry '${REPO_NAME}' already exists in both config files. Nothing to do."
  if [[ -n "$JIRA_URL" ]]; then
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --add-label "auto-merge-setup-done" \
      --comment "Auto-merge config for '${REPO_NAME}' already exists in ${RDI_PATH}."
  fi
  exit 0
fi

# ── Set up playpen ────────────
cd "$WORKDIR"

PLAYPEN_ARGS=(
  --src-url "$RDI_URL"
  --src-branch "main"
  --sparse-files "src/config .github/workflows"
)
[[ -n "$JIRA_ID" ]] && PLAYPEN_ARGS+=(--dest-branch "$JIRA_ID")

PLAYPEN_OUTPUT=$(bash "$SCRIPTS_DIR/setup_github_playpen.sh" "${PLAYPEN_ARGS[@]}") || {
  echo "ERROR: Clone or push failed." >&2; exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)

# ── Edit four target files ────

# 6a. upstream-source-map.yaml
USM_FILE="$CLONE_DIR/src/config/upstream-source-map.yaml"
[[ -f "$USM_FILE" ]] || { echo "ERROR: upstream-source-map.yaml not found." >&2; exit 1; }

if ! grep -qF "name: ${REPO_NAME}" "$USM_FILE"; then
  cat >> "$USM_FILE" <<EOF
- name: ${REPO_NAME}
  automerge: 'yes'
  src:
    url: ${UPSTREAM_REPO_URL}.git
    branch: main
  dest:
    url: ${REPO_URL}.git
    branch: main
EOF
  grep -qF "name: ${REPO_NAME}" "$USM_FILE" || {
    echo "ERROR: Verification failed for upstream-source-map.yaml." >&2; exit 1
  }
  echo "${REPO_NAME} added to upstream-source-map.yaml."
fi

# 6b. main-release-source-map.yaml
MRSM_FILE="$CLONE_DIR/src/config/main-release-source-map.yaml"
[[ -f "$MRSM_FILE" ]] || { echo "ERROR: main-release-source-map.yaml not found." >&2; exit 1; }

if ! grep -qF "name: ${REPO_NAME}" "$MRSM_FILE"; then
  cat >> "$MRSM_FILE" <<EOF
- name: ${REPO_NAME}
  automerge: 'yes'
  repo-url: ${REPO_URL}.git
EOF
  grep -qF "name: ${REPO_NAME}" "$MRSM_FILE" || {
    echo "ERROR: Verification failed for main-release-source-map.yaml." >&2; exit 1
  }
  echo "${REPO_NAME} added to main-release-source-map.yaml."
fi

# 6c. upstream-auto-merge.yaml
UAM_FILE="$CLONE_DIR/.github/workflows/upstream-auto-merge.yaml"
[[ -f "$UAM_FILE" ]] || { echo "ERROR: upstream-auto-merge.yaml not found." >&2; exit 1; }

if ! grep -qF "${REPO_NAME}" "$UAM_FILE"; then
  OPTIONS_LINE=$(grep -n 'repositories:' "$UAM_FILE" | head -1 | cut -d: -f1)
  OPTIONS_START=$(awk -v start="$OPTIONS_LINE" 'NR>start && /options:/{print NR; exit}' "$UAM_FILE")
  INDENT=$(awk -v start="$OPTIONS_START" 'NR>start && /^\s*- /{match($0,/^[[:space:]]*/); print substr($0,1,RLENGTH); exit}' "$UAM_FILE")
  LAST_OPT=$(awk -v start="$OPTIONS_START" -v indent="$INDENT" \
    'NR>start { if ($0 ~ "^" indent "- ") last=NR; else if (last) { print last; exit } } END { if (last) print last }' "$UAM_FILE")
  awk -v line="$LAST_OPT" -v entry="${INDENT}- ${REPO_NAME}" \
    'NR==line{print; print entry; next}1' "$UAM_FILE" > "${UAM_FILE}.tmp" && mv "${UAM_FILE}.tmp" "$UAM_FILE"
  echo "${REPO_NAME} added to upstream-auto-merge.yaml."
fi

# 6d. main-release-auto-merge.yaml
MRAM_FILE="$CLONE_DIR/.github/workflows/main-release-auto-merge.yaml"
[[ -f "$MRAM_FILE" ]] || { echo "ERROR: main-release-auto-merge.yaml not found." >&2; exit 1; }

if ! grep -qF "${REPO_NAME}" "$MRAM_FILE"; then
  OPTIONS_LINE=$(grep -n 'repositories:' "$MRAM_FILE" | head -1 | cut -d: -f1)
  OPTIONS_START=$(awk -v start="$OPTIONS_LINE" 'NR>start && /options:/{print NR; exit}' "$MRAM_FILE")
  INDENT=$(awk -v start="$OPTIONS_START" 'NR>start && /^\s*- /{match($0,/^[[:space:]]*/); print substr($0,1,RLENGTH); exit}' "$MRAM_FILE")
  LAST_OPT=$(awk -v start="$OPTIONS_START" -v indent="$INDENT" \
    'NR>start { if ($0 ~ "^" indent "- ") last=NR; else if (last) { print last; exit } } END { if (last) print last }' "$MRAM_FILE")
  awk -v line="$LAST_OPT" -v entry="${INDENT}- ${REPO_NAME}" \
    'NR==line{print; print entry; next}1' "$MRAM_FILE" > "${MRAM_FILE}.tmp" && mv "${MRAM_FILE}.tmp" "$MRAM_FILE"
  echo "${REPO_NAME} added to main-release-auto-merge.yaml."
fi

# ── Commit and push ───────────
bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files     "src/config/upstream-source-map.yaml src/config/main-release-source-map.yaml .github/workflows/upstream-auto-merge.yaml .github/workflows/main-release-auto-merge.yaml" \
  --message   "Configure auto-merge for ${REPO_NAME}

Adds '${REPO_NAME}' to upstream and main-release source maps
and registers it in both auto-merge workflows.

Related: ${JIRA_ID:-no-jira}" \
  --branch    "$DEST_BRANCH" || {
  echo "ERROR: Could not push." >&2; exit 1
}

# ── Raise PR (up to 3 attempts) ──
MAX_ATTEMPTS=3
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
    --src-url "$RDI_URL" \
    --src-branch "$DEST_BRANCH" \
    --dest-url "$RDI_URL" \
    --dest-branch "main" \
    --title "Configure auto-merge for ${REPO_NAME}" \
    --description "Sets up auto-merge for \`${REPO_NAME}\` in ${RDI_PATH}.

| Field | Value |
|-------|-------|
| Component repo  | \`${REPO_URL}\` |
| Upstream repo   | \`${UPSTREAM_REPO_URL}\` |

**Files changed:**
- \`src/config/upstream-source-map.yaml\`
- \`src/config/main-release-source-map.yaml\`
- \`.github/workflows/upstream-auto-merge.yaml\`
- \`.github/workflows/main-release-auto-merge.yaml\`

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
    --add-label "auto-merge-pr-raised" \
    --comment "GitHub PR raised to configure auto-merge for '${REPO_NAME}' in ${RDI_PATH}.

PR URL: $PR_URL"
fi

echo ""
echo "Done."
echo "  PR raised: $PR_URL"
