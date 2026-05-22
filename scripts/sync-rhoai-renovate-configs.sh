#!/usr/bin/env bash
# sync-rhoai-renovate-configs.sh — Trigger and monitor the sync-renovate-configs workflow
#
# Usage:
#   ./scripts/sync-rhoai-renovate-configs.sh [--jira-url <url>]
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN (needs repo + actions:write scope)
#
# Required when --jira-url is provided:
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional:
#   RHOAI_KONFLUX_CENTRAL_REPO_URL — override default repo URL
#   JIRA_SERVER — override default Jira server

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

JIRA_URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jira-url) JIRA_URL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -n "$JIRA_URL" ]]; then
  eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "$JIRA_URL")"
else
  JIRA_ID=""
fi

RKC_URL="${RHOAI_KONFLUX_CENTRAL_REPO_URL:-https://github.com/red-hat-data-services/konflux-central.git}"
RKC_PATH=$(echo "$RKC_URL" | sed 's|https://github.com/||;s|\.git$||')
WORKFLOW_FILE=".github/workflows/sync-renovate-configs.yml"
WORKFLOW_REF="main"

echo "RKC_URL       : $RKC_URL"
echo "RKC_PATH      : $RKC_PATH"
echo "JIRA_URL      : ${JIRA_URL:-(not provided)}"
echo "WORKFLOW_FILE : $WORKFLOW_FILE"

# ── Check prerequisites ──────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "GITHUB_USER GITHUB_TOKEN" \
  --tools "uv"

if [[ -n "$JIRA_URL" ]]; then
  bash "$SCRIPTS_DIR/check_prerequisites.sh" \
    --env "JIRA_USER_EMAIL JIRA_API_TOKEN"
fi

# ── Trigger workflow ─────────────────────────────────────────────────────────

trigger_workflow() {
  local attempt max_attempts=3
  for attempt in $(seq 1 $max_attempts); do
    echo "Triggering workflow (attempt $attempt/$max_attempts)..."
    RUN_ID=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" trigger \
      --repo-url "$RKC_URL" \
      --workflow "$WORKFLOW_FILE" \
      --ref "$WORKFLOW_REF" \
      --input "dry_run=false" \
      --input "renovate-config=all" 2>&1) && break

    if echo "$RUN_ID" | grep -q "403"; then
      echo "ERROR: Permission denied (HTTP 403). GITHUB_TOKEN needs 'actions:write' scope."
      exit 1
    fi
    if echo "$RUN_ID" | grep -q "404"; then
      echo "ERROR: Workflow or repo not found (HTTP 404). Verify RKC_URL: $RKC_URL"
      exit 1
    fi
    if [[ $attempt -eq $max_attempts ]]; then
      echo "ERROR: Could not dispatch workflow after $max_attempts attempts."
      exit 1
    fi
    sleep 10
  done

  echo "Workflow run triggered. Run ID: $RUN_ID"
  echo "Run URL: https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}"
}

trigger_workflow

# ── Update Jira: triggered ───────────────────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "renovate-sync-triggered" \
    --comment "sync-renovate-configs workflow triggered (Run #${RUN_ID}).

Workflow run: https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}

Monitoring in progress (max 30 minutes)..."
fi

# ── Monitor workflow ─────────────────────────────────────────────────────────

monitor_workflow() {
  MONITOR_OUTPUT=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" monitor \
    --repo-url "$RKC_URL" \
    --run-id "$RUN_ID" \
    --timeout 30 \
    --poll-interval 60)
  WORKFLOW_STATUS="${MONITOR_OUTPUT#status=}"
}

monitor_workflow

handle_result() {
  case "$WORKFLOW_STATUS" in
    success)
      echo "Workflow run $RUN_ID completed successfully."
      ;;
    failure)
      FAILURE_LOGS=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" get-step-logs \
        --repo-url "$RKC_URL" \
        --run-id "$RUN_ID" \
        --step "Sync" 2>/dev/null) || FAILURE_LOGS="(could not fetch logs)"
      echo "Workflow run $RUN_ID FAILED."
      echo "Log excerpt:"
      echo "$FAILURE_LOGS" | head -50
      return 1
      ;;
    cancelled)
      if [[ -n "$JIRA_URL" ]]; then
        uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
          --remove-label "renovate-sync-triggered" \
          --comment "sync-renovate-configs workflow run #${RUN_ID} was cancelled."
      fi
      echo "ERROR: Workflow run $RUN_ID was cancelled."
      exit 1
      ;;
    timeout)
      if [[ -n "$JIRA_URL" ]]; then
        uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
          --comment "sync-renovate-configs workflow run #${RUN_ID} monitoring timed out after 30 minutes."
      fi
      echo "WARNING: Workflow run $RUN_ID has not completed after 30 minutes."
      echo "Run URL: https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}"
      exit 1
      ;;
  esac
}

if ! handle_result; then
  echo "Retrying automatically..."
  trigger_workflow
  monitor_workflow
  if ! handle_result; then
    if [[ -n "$JIRA_URL" ]]; then
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --add-label "renovate-sync-failed" \
        --remove-label "renovate-sync-triggered" \
        --comment "sync-renovate-configs workflow failed on second attempt.

Run URL: https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}"
    fi
    echo "ERROR: Workflow failed on second attempt. Manual investigation required."
    exit 1
  fi
fi

# ── Update Jira: success ─────────────────────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "renovate-sync-done" \
    --remove-label "renovate-sync-triggered" \
    --comment "[step:renovate_sync] sync-renovate-configs workflow completed successfully.

Run URL: https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}

Renovate config has been synced to all registered component repositories."
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Done."
echo "  Workflow : $WORKFLOW_FILE"
echo "  Repo     : $RKC_URL"
echo "  Run ID   : $RUN_ID"
echo "  Status   : success"
echo "  Run URL  : https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}"
echo "  Jira     : ${JIRA_ID:-(none)} — label: renovate-sync-done"
