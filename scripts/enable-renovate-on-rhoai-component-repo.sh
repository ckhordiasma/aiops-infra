#!/usr/bin/env bash
# enable-renovate-on-rhoai-component-repo.sh — Add a component repo to the Renovate config in rhoai-konflux-central
#
# Usage:
#   ./scripts/enable-renovate-on-rhoai-component-repo.sh [--jira-url <url>] [--existing-pr-url <url>]
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
    --jira-url)      JIRA_URL="$2"; shift 2 ;;
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

# Idempotency fast-path
if [[ -n "$EXISTING_PR_URL" ]]; then
  echo "PR already raised: $EXISTING_PR_URL"
  exit 0
fi

# Parse Jira URL
if [[ -n "$JIRA_URL" ]]; then
  if [[ "$JIRA_URL" != *"/browse/"* ]]; then
    echo "ERROR: Invalid Jira URL. Expected format: https://redhat.atlassian.net/browse/RHOAIENG-1234" >&2
    exit 1
  fi
  JIRA_ID="${JIRA_URL##*/}"
fi

# Resolve RKC_URL
RKC_URL="${RHOAI_KONFLUX_CENTRAL_REPO_URL:-https://github.com/red-hat-data-services/konflux-central.git}"
echo "RKC_URL resolved to: $RKC_URL"
RKC_PATH=$(echo "$RKC_URL" | sed 's|https://github.com/||;s|\.git$||')

echo "JIRA_URL : ${JIRA_URL:-(not provided)}"
echo "JIRA_ID  : ${JIRA_ID:-(not provided)}"
echo "RKC_URL  : $RKC_URL"
echo "RKC_PATH : $RKC_PATH"

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
  echo "Using existing component_onboarding_details.yaml from pipeline state."
elif [[ -n "$JIRA_URL" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
    "$JIRA_URL" component_onboarding_details.yaml || {
    echo "ERROR: Could not download 'component_onboarding_details.yaml'." >&2
    echo "  Ensure the attachment exists on the Jira issue." >&2
    exit 1
  }
else
  echo "ERROR: No component_onboarding_details.yaml found and no Jira URL provided." >&2
  exit 1
fi

# Fetch Jira details
if [[ -n "$JIRA_URL" && ! -f "$WORKDIR/component_onboarding_details.json" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL" || {
    echo "ERROR: Could not fetch Jira issue details." >&2
    exit 1
  }
fi

# ── Parse YAML ────────────────
REPO_URL=$(grep -m1 'repo_url:' "$WORKDIR/component_onboarding_details.yaml" | awk '{print $2}')
[[ -z "$REPO_URL" ]] && {
  echo "ERROR: Missing required field 'inputs.repo_url' in component_onboarding_details.yaml." >&2
  exit 1
}

REPO_NAME="${REPO_URL##*/}"
REPO_NAME="${REPO_NAME%.git}"
RENOVATE_ENTRY="red-hat-data-services/${REPO_NAME}"

echo "REPO_URL       : $REPO_URL"
echo "REPO_NAME      : $REPO_NAME"
echo "RENOVATE_ENTRY : $RENOVATE_ENTRY"

# ── Fast-path check ───────────
CONFIG_CONTENT=$(curl -sf \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  "https://raw.githubusercontent.com/${RKC_PATH}/main/config.yaml" 2>/dev/null || echo "")

if [[ -n "$CONFIG_CONTENT" ]] && echo "$CONFIG_CONTENT" | grep -qF "${RENOVATE_ENTRY}"; then
  echo "Entry '${RENOVATE_ENTRY}' already exists in renovate config. Nothing to do."
  if [[ -n "$JIRA_URL" ]]; then
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --add-label "renovate-changes-done" \
      --comment "Renovate config entry '${RENOVATE_ENTRY}' already exists in ${RKC_PATH} (config.yaml). No action needed."
  fi
  exit 0
fi

if [[ -z "$CONFIG_CONTENT" ]]; then
  echo "WARN: Could not fetch config.yaml from GitHub API. Proceeding to check via local clone."
fi

# ── Set up playpen ────────────
cd "$WORKDIR"
PLAYPEN_OUTPUT=$(bash "$SCRIPTS_DIR/setup_github_playpen.sh" \
  --src-url "$RKC_URL" \
  --src-branch "main" \
  --sparse-files "config.yaml") || {
  echo "ERROR: Clone or push failed." >&2
  exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)

# ── Edit config.yaml ─────────
uv run --script "$SCRIPTS_DIR/edit_yaml.py" append-renovate-repo \
  "$CLONE_DIR/config.yaml" \
  --renovate-config "renovate/default-renovate-distribution.json" \
  --name "$RENOVATE_ENTRY"

grep -qF "$RENOVATE_ENTRY" "$CLONE_DIR/config.yaml" || {
  echo "ERROR: Failed to add '$RENOVATE_ENTRY' to config.yaml" >&2; exit 1
}
echo "$RENOVATE_ENTRY added to sync-repositories in config.yaml."

# ── Commit and push ───────────
bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files     "config.yaml" \
  --message   "Enable Renovate for ${REPO_NAME}

Adds '${RENOVATE_ENTRY}' to the default Renovate distribution in config.yaml.

Related: ${JIRA_ID:-no-jira}" \
  --branch    "$DEST_BRANCH" || {
  echo "ERROR: Could not push branch '$DEST_BRANCH' to $RKC_URL." >&2
  exit 1
}

# ── Raise PR (up to 3 attempts) ──
MAX_ATTEMPTS=3
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
    --src-url "$RKC_URL" \
    --src-branch "$DEST_BRANCH" \
    --dest-url "$RKC_URL" \
    --dest-branch "main" \
    --title "Enable Renovate for ${REPO_NAME}" \
    --description "Adds '${RENOVATE_ENTRY}' to the default Renovate distribution in config.yaml.

## Details

| Field | Value |
|-------|-------|
| Component repo | \`${REPO_URL}\` |
| Renovate entry | \`${RENOVATE_ENTRY}\` |
| Distribution | \`renovate/default-renovate-distribution.json\` |

**Jira:** ${JIRA_URL:-(none)}" 2>&1) && break

  echo "PR creation attempt $attempt failed: $PR_URL"
  if [[ $attempt -eq $MAX_ATTEMPTS ]]; then
    echo "ERROR: Could not create PR after $MAX_ATTEMPTS attempts. Aborting." >&2
    exit 1
  fi
  # Re-push branch on "branch not found" errors
  if echo "$PR_URL" | grep -qi "branch not found"; then
    cd "$CLONE_DIR"
    git push origin "$DEST_BRANCH" 2>/dev/null || true
  fi
  sleep 5
done

# ── Jira update ───────────────
if [[ -n "$JIRA_URL" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "renovate-pr-raised" \
    --comment "[step:renovate] GitHub PR raised to enable Renovate for '${REPO_NAME}' in ${RKC_PATH}.

PR URL: $PR_URL
Entry added: ${RENOVATE_ENTRY}

Renovate will start managing dependencies in '${REPO_NAME}' once this PR is merged."
fi

# ── Done ──────────────────────
echo ""
echo "Done."
echo ""
echo "  config.yaml — entry added: ${RENOVATE_ENTRY}"
echo "  GitHub PR   : $PR_URL"
echo "  Jira        : ${JIRA_ID:-(none)} — label: renovate-pr-raised"
echo ""
echo "Renovate will now manage dependencies in '${REPO_NAME}' once the PR is merged."
echo "Source: ${REPO_URL}"
