#!/usr/bin/env bash
# add-rhoai-dockerfile-labels.sh — Adds mandatory RHOAI labels to Dockerfile
#
# Usage:
#   ./scripts/add-rhoai-dockerfile-labels.sh <jira-url>
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN
#
# Optional (when jira-url is provided):
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional env vars:
#   JIRA_SERVER (default: https://redhat.atlassian.net)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
  echo "ERROR: Jira URL is required"
  echo "Usage: $0 <jira-url>"
  exit 1
fi

JIRA_URL="$1"
JIRA_ID="${JIRA_URL##*/}"

echo "JIRA_URL: $JIRA_URL"
echo "JIRA_ID: $JIRA_ID"

# ── Check prerequisites ───────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "GITHUB_USER GITHUB_TOKEN" --tools "uv git curl"

JIRA_ENABLED=false
if [[ -n "${JIRA_USER_EMAIL:-}" && -n "${JIRA_API_TOKEN:-}" ]]; then
  JIRA_ENABLED=true
fi

# ── Fetch component details from Jira ────────────────────────────────────────

WORKDIR=$(mktemp -d)
trap "rm -rf '$WORKDIR'" EXIT

cd "$WORKDIR"

echo "Fetching Jira issue details..."
uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" --jira-url "$JIRA_URL" > jira_issue.json

echo "Downloading component_onboarding_details.yaml..."
uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
  --jira-url "$JIRA_URL" \
  --filename "component_onboarding_details.yaml" \
  > component_onboarding_details.yaml

# Parse component details
COMPONENT_NAME=$(grep -m1 'component_name:' component_onboarding_details.yaml | awk '{print $2}')
REPO_URL=$(grep -m1 'repo_url:' component_onboarding_details.yaml | awk '{print $2}')
REPO_BRANCH=$(grep -m1 'repo_branch:' component_onboarding_details.yaml | awk '{print $2}')
CONTEXT_PATH=$(grep -m1 'context_path:' component_onboarding_details.yaml | awk '{print $2}')
DOCKERFILE_PATH=$(grep -m1 'dockerfile_path:' component_onboarding_details.yaml | awk '{print $2}')

echo "Component: $COMPONENT_NAME"
echo "Repo: $REPO_URL @ $REPO_BRANCH"
echo "Context: $CONTEXT_PATH / $DOCKERFILE_PATH"

# ── Fetch Dockerfile from GitHub ─────────────────────────────────────────────

RAW_BASE="${REPO_URL/github.com/raw.githubusercontent.com}"
DOCKERFILE_URL="$RAW_BASE/$REPO_BRANCH/$CONTEXT_PATH/$DOCKERFILE_PATH"

echo "Fetching Dockerfile from: $DOCKERFILE_URL"
if ! curl -sf "$DOCKERFILE_URL" -o Dockerfile.original; then
  echo "ERROR: Failed to fetch Dockerfile. Check repo_url, repo_branch, context_path, and dockerfile_path."
  exit 1
fi

# ── Check for mandatory labels ───────────────────────────────────────────────

MANDATORY_LABELS=(
  "name"
  "com.redhat.component"
  "summary"
  "description"
  "maintainer"
  "io.k8s.display-name"
  "io.k8s.description"
)

MISSING_LABELS=()
for label in "${MANDATORY_LABELS[@]}"; do
  if ! grep -q "^LABEL.*${label}=" Dockerfile.original; then
    MISSING_LABELS+=("$label")
  fi
done

if [[ ${#MISSING_LABELS[@]} -eq 0 ]]; then
  echo "✓ All mandatory RHOAI labels are already present. No changes needed."
  exit 0
fi

echo "Missing labels: ${MISSING_LABELS[*]}"

# ── Parse repository owner and name ──────────────────────────────────────────

REPO_PATH="${REPO_URL#https://github.com/}"
REPO_OWNER="${REPO_PATH%%/*}"
REPO_NAME="${REPO_PATH#*/}"

echo "Repository: $REPO_OWNER/$REPO_NAME"

# ── Fork and clone component repository ──────────────────────────────────────

echo "Forking $REPO_OWNER/$REPO_NAME..."
FORK_URL=$(uv run --script "$SCRIPTS_DIR/setup_github_fork.py" --github-repo-url "$REPO_URL")
echo "Fork: $FORK_URL"

echo "Cloning fork..."
git clone "$FORK_URL" component-repo
cd component-repo

# Add upstream remote
git remote add upstream "$REPO_URL" 2>/dev/null || true

# ── Create feature branch ─────────────────────────────────────────────────────

BRANCH_NAME="add-rhoai-labels"
echo "Creating branch: $BRANCH_NAME from upstream/$REPO_BRANCH"

git fetch upstream
git checkout -b "$BRANCH_NAME" "upstream/$REPO_BRANCH"

# ── Add missing labels to Dockerfile ──────────────────────────────────────────

DOCKERFILE_FULL_PATH="$CONTEXT_PATH/$DOCKERFILE_PATH"
echo "Editing Dockerfile at: $DOCKERFILE_FULL_PATH"

# Use Python helper to add labels
uv run --script "$SCRIPTS_DIR/update_dockerfile_labels.py" \
  --dockerfile "$DOCKERFILE_FULL_PATH" \
  --component-name "$COMPONENT_NAME" \
  --missing-labels "${MISSING_LABELS[*]}"

# ── Commit and push ───────────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$WORKDIR/component-repo" \
  --files "$DOCKERFILE_FULL_PATH" \
  --message "Add mandatory RHOAI labels to Dockerfile" \
  --branch "$BRANCH_NAME" \
  --remote origin

# ── Raise GitHub PR ───────────────────────────────────────────────────────────

echo "Raising GitHub PR..."
PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
  --src-url "$FORK_URL" \
  --src-branch "$BRANCH_NAME" \
  --dest-url "$REPO_URL" \
  --dest-branch "$REPO_BRANCH" \
  --title "Add mandatory RHOAI labels to Dockerfile" \
  --description "Adds the following mandatory RHOAI labels to the Dockerfile:
$(printf '- %s\n' "${MISSING_LABELS[@]}")

Related Jira: $JIRA_URL")

echo "PR raised: $PR_URL"

# ── Update Jira (if enabled) ──────────────────────────────────────────────────

if [[ "$JIRA_ENABLED" == "true" ]]; then
  echo "Updating Jira..."
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" \
    --jira-url "$JIRA_URL" \
    --add-labels "dockerfile-labels-pr-raised" \
    --comment "Dockerfile labels PR raised: $PR_URL"
else
  echo "Jira credentials not provided. Skipping Jira update."
fi

echo "✓ Complete. PR: $PR_URL"
