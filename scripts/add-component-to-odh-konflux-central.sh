#!/usr/bin/env bash
# add-component-to-odh-konflux-central.sh — Adds Tekton PipelineRun YAMLs to odh-konflux-central
#
# Usage:
#   ./scripts/add-component-to-odh-konflux-central.sh <jira-url>
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN
#
# Required when jira-url is provided:
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional env vars:
#   ODH_KONFLUX_CENTRAL_REPO_URL (default: https://github.com/opendatahub-io/odh-konflux-central)
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

# Resolve ODH_KONFLUX_CENTRAL_URL
ODH_KONFLUX_CENTRAL_URL="${ODH_KONFLUX_CENTRAL_REPO_URL:-https://github.com/opendatahub-io/odh-konflux-central}"
echo "ODH_KONFLUX_CENTRAL_REPO_URL=${ODH_KONFLUX_CENTRAL_REPO_URL:-(not set, using default)}"
echo "ODH_KONFLUX_CENTRAL_URL resolved to: $ODH_KONFLUX_CENTRAL_URL"

echo "JIRA_URL: $JIRA_URL"
echo "JIRA_ID: $JIRA_ID"

# ── Check prerequisites ───────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "GITHUB_USER GITHUB_TOKEN JIRA_USER_EMAIL JIRA_API_TOKEN" --tools "uv git yamllint"

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

# ── Fork and clone odh-konflux-central ───────────────────────────────────────

echo "Forking odh-konflux-central..."
FORK_URL=$(uv run --script "$SCRIPTS_DIR/setup_github_fork.py" --github-repo-url "$ODH_KONFLUX_CENTRAL_URL")
echo "Fork: $FORK_URL"

echo "Cloning fork..."
git clone "$FORK_URL" odh-konflux-central
cd odh-konflux-central

# Add upstream remote
UPSTREAM_URL="$ODH_KONFLUX_CENTRAL_URL"
git remote add upstream "$UPSTREAM_URL" 2>/dev/null || true

# ── Create feature branch ─────────────────────────────────────────────────────

BRANCH_NAME="add-${COMPONENT_NAME}-pipelines"
echo "Creating branch: $BRANCH_NAME"

git fetch upstream
git checkout -b "$BRANCH_NAME" upstream/main

# ── Add PipelineRun YAMLs ─────────────────────────────────────────────────────

echo "Creating pipeline directory..."
mkdir -p "konflux/pipelines/$COMPONENT_NAME"

# Generate push.yaml
cat > "konflux/pipelines/$COMPONENT_NAME/push.yaml" <<EOF
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: $COMPONENT_NAME-push
spec:
  pipelineRef:
    name: docker-build
  params:
    - name: git-url
      value: $REPO_URL
    - name: revision
      value: $REPO_BRANCH
    - name: output-image
      value: \$(params.output-image)
    - name: path-context
      value: $CONTEXT_PATH
    - name: dockerfile
      value: $DOCKERFILE_PATH
EOF

# Generate main.yaml
cat > "konflux/pipelines/$COMPONENT_NAME/main.yaml" <<EOF
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: $COMPONENT_NAME-main
spec:
  pipelineRef:
    name: docker-build
  params:
    - name: git-url
      value: $REPO_URL
    - name: revision
      value: $REPO_BRANCH
    - name: output-image
      value: \$(params.output-image)
    - name: path-context
      value: $CONTEXT_PATH
    - name: dockerfile
      value: $DOCKERFILE_PATH
EOF

echo "Validating YAML files..."
yamllint "konflux/pipelines/$COMPONENT_NAME/"

# ── Update onboarder workflow ─────────────────────────────────────────────────

echo "Updating .github/workflows/update-component.yaml..."
WORKFLOW_FILE=".github/workflows/update-component.yaml"

# Use Python to edit YAML (safer than sed)
uv run --script "$SCRIPTS_DIR/edit_yaml.py" \
  --file "$WORKFLOW_FILE" \
  --path "on.workflow_dispatch.inputs.component.options" \
  --append "$COMPONENT_NAME"

# ── Commit and push ───────────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$WORKDIR/odh-konflux-central" \
  --files "konflux/pipelines/$COMPONENT_NAME/ $WORKFLOW_FILE" \
  --message "Add Konflux pipelines for $COMPONENT_NAME" \
  --branch "$BRANCH_NAME" \
  --remote origin

# ── Raise GitHub PR ───────────────────────────────────────────────────────────

echo "Raising GitHub PR..."
PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
  --src-url "$FORK_URL" \
  --src-branch "$BRANCH_NAME" \
  --dest-url "$UPSTREAM_URL" \
  --dest-branch main \
  --title "Add Konflux pipelines for $COMPONENT_NAME" \
  --description "Adds Tekton PipelineRun configurations for $COMPONENT_NAME.

Related Jira: $JIRA_URL")

echo "PR raised: $PR_URL"

# ── Update Jira ───────────────────────────────────────────────────────────────

echo "Updating Jira..."
uv run --script "$SCRIPTS_DIR/update_jira_issue.py" \
  --jira-url "$JIRA_URL" \
  --add-labels "okc-pr-raised" \
  --comment "ODH Konflux Central PR raised: $PR_URL"

echo "✓ Complete. PR: $PR_URL"
