#!/usr/bin/env bash
# setup-auto-merge.sh — Configures auto-merge for component Konflux CI PRs
#
# Usage:
#   ./scripts/setup-auto-merge.sh <component-name> [<jira-url>] [--existing-pr-url <url>]
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN
#
# Optional env vars (when jira-url provided):
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional env vars:
#   RHODS_DEVOPS_INFRA_REPO_URL (default: https://github.com/red-hat-data-services/rhods-devops-infra.git)
#   JIRA_SERVER (default: https://redhat.atlassian.net)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

COMPONENT_NAME=""
JIRA_URL=""
EXISTING_PR_URL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --existing-pr-url)
      EXISTING_PR_URL="$2"
      shift 2
      ;;
    *)
      if [[ -z "$COMPONENT_NAME" ]]; then
        COMPONENT_NAME="$1"
      elif [[ -z "$JIRA_URL" ]]; then
        JIRA_URL="$1"
      else
        echo "ERROR: Unexpected argument '$1'"
        exit 1
      fi
      shift
      ;;
  esac
done

[[ -z "$COMPONENT_NAME" ]] && {
  echo "Usage: $0 <component-name> [<jira-url>] [--existing-pr-url <url>]"
  exit 1
}

# Idempotency fast-path
if [[ -n "$EXISTING_PR_URL" ]]; then
  echo "PR already raised: $EXISTING_PR_URL"
  exit 0
fi

# Parse Jira URL (if provided)
JIRA_ID=""
if [[ -n "$JIRA_URL" ]]; then
  eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "$JIRA_URL")"
  echo "JIRA_URL : $JIRA_URL"
  echo "JIRA_ID  : $JIRA_ID"
fi

echo "COMPONENT_NAME : $COMPONENT_NAME"

# ── Check prerequisites ───────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "GITHUB_USER GITHUB_TOKEN" --tools "uv git gh"

if [[ -n "$JIRA_URL" ]]; then
  bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "JIRA_USER_EMAIL JIRA_API_TOKEN"
fi

# ── Set up working directory ──────────────────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "$JIRA_URL")"
else
  WORKDIR="/tmp/setup-auto-merge-${COMPONENT_NAME}-$$"
  mkdir -p "$WORKDIR"
fi

echo "Working directory: $WORKDIR"

# ── Get component YAML (if Jira provided) ─────────────────────────────────────

if [[ -n "$JIRA_URL" && ! -f "$WORKDIR/component_onboarding_details.yaml" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
    "$JIRA_URL" component_onboarding_details.yaml || {
    echo "WARN: Could not download component_onboarding_details.yaml from Jira."
    echo "  Continuing with provided component name."
  }
fi

# ── Parse component repository URL (if YAML available) ────────────────────────

COMPONENT_REPO_URL=""
if [[ -f "$WORKDIR/component_onboarding_details.yaml" ]]; then
  YAML_FILE="$WORKDIR/component_onboarding_details.yaml"
  COMPONENT_REPO_URL=$(grep -m1 'repo_url:' "$YAML_FILE" | awk '{print $2}' || echo "")
fi

# Extract owner/repo from URL
if [[ -n "$COMPONENT_REPO_URL" ]]; then
  COMPONENT_REPO_PATH=$(echo "$COMPONENT_REPO_URL" | sed 's|https://github.com/||;s|\.git$||')
  REPO_OWNER=$(echo "$COMPONENT_REPO_PATH" | cut -d/ -f1)
  REPO_NAME=$(echo "$COMPONENT_REPO_PATH" | cut -d/ -f2)
else
  # Default to red-hat-data-services
  REPO_OWNER="red-hat-data-services"
  REPO_NAME="$COMPONENT_NAME"
  COMPONENT_REPO_PATH="$REPO_OWNER/$REPO_NAME"
fi

echo "COMPONENT_REPO   : $COMPONENT_REPO_PATH"

# ── Resolve devops infra repository URL ──────────────────────────────────────

DEVOPS_INFRA_URL="${RHODS_DEVOPS_INFRA_REPO_URL:-https://github.com/red-hat-data-services/rhods-devops-infra.git}"
DEVOPS_INFRA_PATH=$(echo "$DEVOPS_INFRA_URL" | sed 's|https://github.com/||;s|\.git$||')

echo "DEVOPS_INFRA_URL : $DEVOPS_INFRA_URL"
echo "DEVOPS_INFRA_PATH: $DEVOPS_INFRA_PATH"

# ── Set up GitHub playpen (fork + clone) ──────────────────────────────────────

cd "$WORKDIR"

BRANCH_NAME="${JIRA_ID:-setup-auto-merge-${COMPONENT_NAME}}"

PLAYPEN_OUTPUT=$(bash "$SCRIPTS_DIR/setup_github_playpen.sh" \
  --src-url "$DEVOPS_INFRA_URL" \
  --dest-url "$DEVOPS_INFRA_URL" \
  --src-branch main \
  --dest-branch "$BRANCH_NAME") || {
  echo "ERROR: Playpen setup failed. See details above."
  echo "  Check GITHUB_TOKEN has 'repo' scope and fork/clone access."
  exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)

echo "Clone directory: $CLONE_DIR"
echo "Branch: $DEST_BRANCH"

# ── Locate auto-merge configuration file ─────────────────────────────────────

CONFIG_FILE=""
for candidate in "auto-merge-config.yaml" "config/auto-merge.yaml" ".github/auto-merge.yaml"; do
  if [[ -f "$CLONE_DIR/$candidate" ]]; then
    CONFIG_FILE="$CLONE_DIR/$candidate"
    break
  fi
done

if [[ -z "$CONFIG_FILE" ]]; then
  echo "ERROR: Could not locate auto-merge configuration file in $CLONE_DIR."
  echo "  Checked: auto-merge-config.yaml, config/auto-merge.yaml, .github/auto-merge.yaml"
  echo "  The repository structure may have changed. Update this script accordingly."
  exit 1
fi

echo "Config file: $CONFIG_FILE"

# ── Check if component already configured ─────────────────────────────────────

if grep -qF "$COMPONENT_NAME" "$CONFIG_FILE"; then
  echo "'$COMPONENT_NAME' already configured in auto-merge config — skipping edit."
else
  # Add component to auto-merge configuration
  # Note: This is a simplified example - actual format depends on the config file structure

  cat >> "$CONFIG_FILE" <<EOF

  - name: ${COMPONENT_NAME}
    owner: ${REPO_OWNER}
    repo: ${REPO_NAME}
    auto_merge:
      enabled: true
      required_checks:
        - konflux-ci
        - build-and-test
      merge_method: squash
EOF

  echo "Auto-merge configuration added for '$COMPONENT_NAME'."
fi

# ── Commit and push ───────────────────────────────────────────────────────────

CONFIG_FILE_REL=$(realpath --relative-to="$CLONE_DIR" "$CONFIG_FILE")

bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files "$CONFIG_FILE_REL" \
  --message "Enable auto-merge for ${COMPONENT_NAME}

Configures auto-merge for ${COMPONENT_NAME} Konflux CI pull requests.

Component: ${COMPONENT_NAME}
Repository: ${COMPONENT_REPO_PATH}

Related: ${JIRA_ID:-(none)}" \
  --branch "$DEST_BRANCH" || {
  echo "ERROR: Could not push branch '$DEST_BRANCH'. See details above."
  exit 1
}

# ── Raise PR ──────────────────────────────────────────────────────────────────

PR_DESCRIPTION="Configures auto-merge for ${COMPONENT_NAME} Konflux CI pull requests.

## Component details

| Field | Value |
|-------|-------|
| \`component_name\` | \`${COMPONENT_NAME}\` |
| \`repository\` | \`${COMPONENT_REPO_PATH}\` |

**File changed:** \`${CONFIG_FILE_REL}\`"

if [[ -n "$JIRA_URL" ]]; then
  PR_DESCRIPTION="${PR_DESCRIPTION}
**Jira:** $JIRA_URL"
fi

PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
  --src-url "$DEVOPS_INFRA_URL" \
  --src-branch "$DEST_BRANCH" \
  --dest-url "$DEVOPS_INFRA_URL" \
  --dest-branch main \
  --title "Enable auto-merge for ${COMPONENT_NAME}" \
  --description "$PR_DESCRIPTION") || {
  echo "ERROR: Could not create PR."
  exit 1
}

echo "PR raised: $PR_URL"

# ── Jira updates (if applicable) ──────────────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "auto-merge-pr-raised" \
    --comment "[step:auto_merge] GitHub PR raised to enable auto-merge for '${COMPONENT_NAME}'.

PR URL: $PR_URL

File changed: ${CONFIG_FILE_REL}
Repository: ${COMPONENT_REPO_PATH}

Auto-merge will be active for Konflux CI PRs once the configuration is merged."
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "Done."
echo ""
echo "  ${CONFIG_FILE_REL}   — ${COMPONENT_NAME} auto-merge configured"
echo "  GitHub PR                    : $PR_URL"
if [[ -n "$JIRA_URL" ]]; then
  echo "  Jira                         : ${JIRA_ID} — label: auto-merge-pr-raised"
fi
