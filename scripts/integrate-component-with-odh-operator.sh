#!/usr/bin/env bash
# integrate-component-with-odh-operator.sh — Integrates operator component with ODH/RHOAI operator repo
#
# Usage:
#   ./scripts/integrate-component-with-odh-operator.sh <jira-url> [--existing-pr-url <url>]
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional env vars:
#   ODH_OPERATOR_REPO_URL (default: derived from product_context)
#   JIRA_SERVER (default: https://redhat.atlassian.net)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

JIRA_URL=""
EXISTING_PR_URL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --existing-pr-url)
      EXISTING_PR_URL="$2"
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

[[ -z "$JIRA_URL" ]] && {
  echo "Usage: $0 <jira-url> [--existing-pr-url <url>]"
  exit 1
}

# Idempotency fast-path
if [[ -n "$EXISTING_PR_URL" ]]; then
  echo "PR already raised: $EXISTING_PR_URL"
  exit 0
fi

# Parse Jira URL
eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "$JIRA_URL")"
echo "JIRA_URL : $JIRA_URL"
echo "JIRA_ID  : $JIRA_ID"

# ── Check prerequisites ───────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "GITHUB_USER GITHUB_TOKEN JIRA_USER_EMAIL JIRA_API_TOKEN" --tools "uv git gh"

# ── Set up working directory ──────────────────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "$JIRA_URL")"
echo "Working directory: $WORKDIR"

# ── Get component YAML ────────────────────────────────────────────────────────

if [[ ! -f "$WORKDIR/component_onboarding_details.yaml" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
    "$JIRA_URL" component_onboarding_details.yaml || {
    echo "ERROR: Could not download 'component_onboarding_details.yaml'."
    echo "  Ensure the attachment exists on the Jira issue."
    exit 1
  }
fi

if [[ ! -f "$WORKDIR/component_onboarding_details.json" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL" || {
    echo "ERROR: Could not fetch Jira issue details."
    exit 1
  }
fi

# ── Parse YAML and derive variables ───────────────────────────────────────────

YAML_FILE="$WORKDIR/component_onboarding_details.yaml"

eval "$(bash "$SCRIPTS_DIR/parse_component_details.sh" \
  --workdir "$WORKDIR" \
  --jira-id "$JIRA_ID" \
  --scripts-dir "$SCRIPTS_DIR")"

echo "COMPONENT_NAME   : $COMPONENT_NAME"
echo "IS_OPERATOR      : $IS_OPERATOR"
echo "PRODUCT_CONTEXT  : $PRODUCT_CONTEXT"

# ── Check if component is an operator ─────────────────────────────────────────

if [[ "$IS_OPERATOR" != "true" ]]; then
  echo "Component is not an operator (is_operator: $IS_OPERATOR). Skipping operator integration."
  if [[ -n "$JIRA_URL" ]]; then
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --add-label "operator-integration-skipped" \
      --comment "Operator integration skipped: component is not an operator (is_operator: ${IS_OPERATOR}).

This step only applies to operator components."
  fi
  exit 0
fi

# ── Resolve operator repository URL ───────────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/resolve_operator_url.sh" --product-context "$PRODUCT_CONTEXT")"

echo "ODH_OPERATOR_URL  : $ODH_OPERATOR_URL"
echo "ODH_OPERATOR_PATH : $ODH_OPERATOR_PATH"

# Extract manifest path from YAML
MANIFESTS_PATH=$(grep -m1 'manifests_path:' "$YAML_FILE" | awk '{print $2}' || echo "manifests")

echo "MANIFESTS_PATH   : $MANIFESTS_PATH"

# ── Set up GitHub playpen (fork + clone) ──────────────────────────────────────

cd "$WORKDIR"

PLAYPEN_OUTPUT=$(bash "$SCRIPTS_DIR/setup_github_playpen.sh" \
  --src-url "$ODH_OPERATOR_URL" \
  --dest-url "$ODH_OPERATOR_URL" \
  --src-branch main \
  --dest-branch "$JIRA_ID" \
  --sparse-files "Makefile") || {
  echo "ERROR: Playpen setup failed. See details above."
  echo "  Check GITHUB_TOKEN has 'repo' scope and fork/clone access."
  exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)

echo "Clone directory: $CLONE_DIR"
echo "Branch: $DEST_BRANCH"

# ── Add Makefile entries ──────────────────────────────────────────────────────

MAKEFILE="$CLONE_DIR/Makefile"
[[ -f "$MAKEFILE" ]] || {
  echo "ERROR: Makefile not found in $CLONE_DIR."
  echo "  Verify ODH_OPERATOR_URL points to the correct operator repository."
  exit 1
}

# Check if component already referenced in Makefile
if grep -qF "$COMPONENT_NAME" "$MAKEFILE"; then
  echo "'$COMPONENT_NAME' already referenced in Makefile — skipping edit."
else
  # Add manifest copy entries
  # Note: The exact format depends on the repository's Makefile structure
  # This is a simplified example - actual implementation may need repository-specific logic

  echo "# Copy $COMPONENT_NAME manifests" >> "$MAKEFILE"
  echo "cp -r ../$COMPONENT_NAME/$MANIFESTS_PATH/* manifests/$COMPONENT_NAME/" >> "$MAKEFILE"

  echo "Makefile entries added for '$COMPONENT_NAME'."
fi

# ── Commit and push ───────────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files "Makefile" \
  --message "Add ${COMPONENT_NAME} manifest copy entries

Integrates ${COMPONENT_NAME} operator manifests with the operator repository.

Component: ${COMPONENT_NAME}
Manifests path: ${MANIFESTS_PATH}

Related: ${JIRA_ID}" \
  --branch "$DEST_BRANCH" || {
  echo "ERROR: Could not push branch '$DEST_BRANCH'. See details above."
  exit 1
}

# ── Raise PR ──────────────────────────────────────────────────────────────────

PR_URL=$(uv run --script "$SCRIPTS_DIR/raise_github_pr.py" \
  --src-url "$ODH_OPERATOR_URL" \
  --src-branch "$DEST_BRANCH" \
  --dest-url "$ODH_OPERATOR_URL" \
  --dest-branch main \
  --title "Add ${COMPONENT_NAME} to operator manifests" \
  --description "Integrates ${COMPONENT_NAME} operator manifests with the operator repository.

## Component details

| Field | Value |
|-------|-------|
| \`component_name\` | \`${COMPONENT_NAME}\` |
| \`manifests_path\` | \`${MANIFESTS_PATH}\` |
| \`product_context\` | \`${PRODUCT_CONTEXT}\` |

**File changed:** \`Makefile\`
**Jira:** $JIRA_URL") || {
  echo "ERROR: Could not create PR."
  exit 1
}

echo "PR raised: $PR_URL"

# ── Jira updates ──────────────────────────────────────────────────────────────

uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
  --add-label "operator-integration-pr-raised" \
  --comment "[step:operator_integration] GitHub PR raised to integrate '${COMPONENT_NAME}' with the operator repository.

PR URL: $PR_URL

File changed: Makefile
Manifests path: ${MANIFESTS_PATH}

The operator integration will be active once the PR is merged."

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "Done."
echo ""
echo "  Makefile                 — ${COMPONENT_NAME} entries added"
echo "  GitHub PR                : $PR_URL"
echo "  Jira                     : ${JIRA_ID} — label: operator-integration-pr-raised"
