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

if [[ -n "$JIRA_URL" && "$JIRA_URL" != *"/browse/"* ]]; then
  echo "ERROR: Invalid Jira URL." >&2; exit 1
fi
[[ -n "$JIRA_URL" ]] && JIRA_ID="${JIRA_URL##*/}"

RKC_URL="${RHOAI_KONFLUX_CENTRAL_REPO_URL:-https://github.com/red-hat-data-services/konflux-central.git}"
echo "RKC_URL resolved to: $RKC_URL"
RKC_PATH=$(echo "$RKC_URL" | sed 's|https://github.com/||;s|\.git$||')

WORKFLOW_FILE=".github/workflows/sync-renovate-configs.yml"
WORKFLOW_REF="main"

# ── Check prerequisites ──────
bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "GITHUB_USER GITHUB_TOKEN" \
  --tools "uv"

if [[ -n "$JIRA_URL" ]]; then
  bash "$SCRIPTS_DIR/check_prerequisites.sh" \
    --env "JIRA_USER_EMAIL JIRA_API_TOKEN"
fi

# ── Trigger workflow ──────────
trigger_workflow() {
  local max_attempts=3
  local attempt
  for attempt in $(seq 1 $max_attempts); do
    RUN_ID=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" trigger \
      --repo-url "$RKC_URL" \
      --workflow "$WORKFLOW_FILE" \
      --ref "$WORKFLOW_REF" \
      --input "dry_run=false" \
      --input "renovate-config=all" 2>&1) && return 0

    echo "Trigger attempt $attempt failed: $RUN_ID"

    if echo "$RUN_ID" | grep -q "403"; then
      echo "ERROR: Permission denied (HTTP 403). GITHUB_TOKEN needs 'actions:write' scope." >&2
      exit 1
    fi
    if echo "$RUN_ID" | grep -q "404"; then
      echo "ERROR: Workflow or repo not found (HTTP 404). Verify RKC_URL: $RKC_URL" >&2
      exit 1
    fi

    if [[ $attempt -eq $max_attempts ]]; then
      echo "ERROR: Could not dispatch workflow after $max_attempts attempts." >&2
      exit 1
    fi
    sleep 10
  done
}

echo "Triggering workflow: $WORKFLOW_FILE"
echo "  Repo  : $RKC_URL"
echo "  Ref   : $WORKFLOW_REF"
trigger_workflow

echo "Workflow run triggered."
echo "  Run ID  : $RUN_ID"
echo "  Run URL : https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}"

if [[ -n "$JIRA_URL" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "renovate-sync-triggered" \
    --comment "sync-renovate-configs workflow triggered (Run #${RUN_ID}).

Workflow run: https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}

Monitoring in progress (max 30 minutes)..."
fi

# ── Monitor workflow ──────────
monitor_workflow() {
  MONITOR_OUTPUT=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" monitor \
    --repo-url "$RKC_URL" \
    --run-id "$RUN_ID" \
    --timeout 30 \
    --poll-interval 60 2>&1) || true
  WORKFLOW_STATUS="${MONITOR_OUTPUT#status=}"
}

monitor_workflow

case "$WORKFLOW_STATUS" in
  success)
    echo "Workflow run $RUN_ID completed successfully."
    ;;
  failure)
    echo "Workflow run $RUN_ID FAILED. Retrying once..."

    # Fetch failure logs
    FAILURE_LOGS=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" get-step-logs \
      --repo-url "$RKC_URL" \
      --run-id "$RUN_ID" \
      --step "Sync" 2>/dev/null) || FAILURE_LOGS="(could not fetch logs)"
    echo "Log excerpt:"
    echo "$FAILURE_LOGS" | head -50

    # Retry once
    trigger_workflow
    monitor_workflow

    if [[ "$WORKFLOW_STATUS" != "success" ]]; then
      if [[ -n "$JIRA_URL" ]]; then
        uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
          --add-label "renovate-sync-failed" \
          --remove-label "renovate-sync-triggered" \
          --comment "sync-renovate-configs workflow failed on second attempt.

Run URL: https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}"
      fi
      echo "ERROR: Workflow failed on second attempt." >&2
      exit 1
    fi
    ;;
  cancelled)
    if [[ -n "$JIRA_URL" ]]; then
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --remove-label "renovate-sync-triggered" \
        --comment "sync-renovate-configs workflow run #${RUN_ID} was cancelled."
    fi
    echo "ERROR: Workflow run $RUN_ID was cancelled." >&2
    exit 1
    ;;
  *)
    if [[ -n "$JIRA_URL" ]]; then
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --comment "sync-renovate-configs workflow run #${RUN_ID} monitoring timed out after 30 minutes.
The run may still be completing.
Run URL: https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}"
    fi
    echo "WARNING: Workflow run $RUN_ID has not completed after 30 minutes."
    echo "Run URL: https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}"
    exit 0
    ;;
esac

# ── Jira update on success ───
if [[ -n "$JIRA_URL" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "renovate-sync-done" \
    --remove-label "renovate-sync-triggered" \
    --comment "[step:renovate_sync] sync-renovate-configs workflow completed successfully.

Run URL: https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}

Renovate config has been synced to all registered component repositories."
fi

echo ""
echo "Done."
echo "  Workflow : $WORKFLOW_FILE"
echo "  Run ID   : $RUN_ID"
echo "  Status   : success"
echo "  Run URL  : https://github.com/${RKC_PATH}/actions/runs/${RUN_ID}"
echo "  Jira     : ${JIRA_ID:-(none)} — label: renovate-sync-done"
