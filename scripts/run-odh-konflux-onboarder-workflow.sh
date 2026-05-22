#!/usr/bin/env bash
# run-odh-konflux-onboarder-workflow.sh — Trigger odh-konflux-onboarder GitHub Actions workflow
#
# Usage:
#   ./scripts/run-odh-konflux-onboarder-workflow.sh [<jira-url>]
#   ./scripts/run-odh-konflux-onboarder-workflow.sh --component <name> --pr-target-branch <branch> --build-type <CI|Release> [--version <ver>] [--jira-url <url>]
#
# Required env vars:
#   GITHUB_USER         GitHub username
#   GITHUB_TOKEN        GitHub PAT with repo + actions:write scope
#   JIRA_USER_EMAIL     Atlassian account email (if using Jira)
#   JIRA_API_TOKEN      Atlassian API token (if using Jira)
#
# Optional env vars:
#   ODH_KONFLUX_CENTRAL_REPO_URL    Override odh-konflux-central repo URL
#   JIRA_SERVER                      Jira server URL (default: https://redhat.atlassian.net)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────

JIRA_URL=""
COMPONENT=""
PR_TARGET_BRANCH=""
BUILD_TYPE=""
VERSION=""

# If first arg looks like a Jira URL, use it
if [[ $# -ge 1 && "$1" =~ ^https?:// ]]; then
  JIRA_URL="$1"
  shift
fi

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --component) COMPONENT="$2"; shift 2 ;;
    --pr-target-branch) PR_TARGET_BRANCH="$2"; shift 2 ;;
    --build-type) BUILD_TYPE="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --jira-url) JIRA_URL="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Parse Jira URL if provided
if [[ -n "$JIRA_URL" ]]; then
  eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "$JIRA_URL")"
  echo "JIRA_URL : $JIRA_URL"
  echo "JIRA_ID  : $JIRA_ID"
fi

# Resolve OKC repo URL
OKC_URL="${ODH_KONFLUX_CENTRAL_REPO_URL:-https://github.com/opendatahub-io/odh-konflux-central.git}"
echo "ODH_KONFLUX_CENTRAL_REPO_URL=${ODH_KONFLUX_CENTRAL_REPO_URL:-(not set, using default)}"
echo "OKC_URL resolved to: $OKC_URL"

OKC_PATH=$(echo "$OKC_URL" | sed 's|https://github.com/||;s|\.git$||')
OKC_REF="main"
WORKFLOW_FILE=".github/workflows/odh-konflux-onboarder.yml"

# ── Check prerequisites ───────

bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "GITHUB_USER GITHUB_TOKEN" --tools "uv"

if [[ -n "$JIRA_URL" ]]; then
  bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "JIRA_USER_EMAIL JIRA_API_TOKEN"
fi

# ── Set up working directory ──

eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "${JIRA_URL:-}")"
YAML_PATH="${WORKDIR}/component_onboarding_details.yaml"
echo "Working directory: $WORKDIR"

# ── Collect component inputs ──

# If Jira URL provided, fetch details and download YAML
if [[ -n "$JIRA_URL" ]]; then
  if [[ ! -f "$WORKDIR/component_onboarding_details.json" ]]; then
    cd "$WORKDIR"
    uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL" || {
      echo "ERROR in Step 3 (Fetch Jira): Could not fetch Jira issue. Aborting." >&2
      exit 1
    }
  fi

  if [[ ! -f "$YAML_PATH" ]]; then
    cd "$WORKDIR"
    uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" "$JIRA_URL" component_onboarding_details.yaml || {
      echo "ERROR in Step 3 (Download YAML): 'component_onboarding_details.yaml' not found as a Jira attachment. Aborting." >&2
      exit 1
    }
  fi
fi

# Parse inputs from YAML or flags
if [[ -f "$YAML_PATH" ]]; then
  echo "Found component_onboarding_details.yaml. Reading inputs from file."
  PRODUCT_CONTEXT=$(grep -m1 'product_context:' "$YAML_PATH" | awk '{print $2}')
  REPO_URL=$(grep -m1 'repo_url:' "$YAML_PATH" | awk '{print $2}')
  PR_TARGET_BRANCH=$(grep -m1 'repo_branch:' "$YAML_PATH" | awk '{print $2}')
  BUILD_TYPE=$(grep -m1 'build_type:' "$YAML_PATH" | awk '{print $2}' 2>/dev/null || echo "")
  VERSION=$(grep -m1 'output_image_tag:' "$YAML_PATH" | awk '{print $2}' 2>/dev/null || echo "")

  # Derive component from repo URL
  REPO_NAME="${REPO_URL##*/}"
  COMPONENT="${REPO_NAME%.git}"

  # Normalize build type
  BUILD_TYPE_LOWER="${BUILD_TYPE,,}"
  if [[ "$BUILD_TYPE_LOWER" == "ci" ]]; then
    BUILD_TYPE="CI"
  elif [[ "$BUILD_TYPE_LOWER" == "release" ]]; then
    BUILD_TYPE="Release"
  else
    echo "ERROR in Step 3: Unknown build_type '${BUILD_TYPE}'. Expected CI or Release." >&2
    exit 1
  fi

  if [[ "$BUILD_TYPE" == "Release" && -z "$VERSION" ]]; then
    echo "ERROR in Step 3: build_type is Release but 'inputs.output_image_tag' is missing from YAML." >&2
    exit 1
  fi

  if [[ "${PRODUCT_CONTEXT^^}" == "RHOAI" ]]; then
    echo "ERROR: This workflow is for ODH component onboarding only. RHOAI uses a different process." >&2
    exit 1
  fi
elif [[ -z "$COMPONENT" || -z "$PR_TARGET_BRANCH" || -z "$BUILD_TYPE" ]]; then
  echo "ERROR: Required inputs missing. Provide --component, --pr-target-branch, and --build-type, or use --jira-url with attached YAML." >&2
  exit 1
fi

# ── Idempotency check — existing PR ──

if [[ -n "$JIRA_URL" && -f "$WORKDIR/component_onboarding_details.json" ]]; then
  EXISTING_PR_URLS=$(jq -r '.fields.comment.comments[].body' "$WORKDIR/component_onboarding_details.json" 2>/dev/null \
    | grep -oE 'https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+' \
    | sort -u || true)

  for pr_url in $EXISTING_PR_URLS; do
    pr_check=$(uv run --script "$SCRIPTS_DIR/monitor_github_pr.py" --pr-url "$pr_url" --check-only 2>/dev/null || true)
    if echo "$pr_check" | grep -qE 'state=(open|merged)' && echo "$pr_url" | grep -q "$OKC_PATH"; then
      TEKTON_PR_URL="$pr_url"
      echo "Found existing Tekton PR: $TEKTON_PR_URL"
      echo "Skipping workflow trigger. Jumping to PR monitoring."

      # Update Jira with PR URL if not already done
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --add-label "tekton-pr-raised" \
        --comment "Existing Tekton PR detected: $TEKTON_PR_URL" 2>/dev/null || true

      echo "=== run-odh-konflux-onboarder-workflow complete ==="
      echo ""
      echo "  Component             : $COMPONENT"
      echo "  PR target branch      : $PR_TARGET_BRANCH"
      echo "  Build type            : $BUILD_TYPE${VERSION:+
  Version               : $VERSION}"
      echo ""
      echo "  Tekton PR             : $TEKTON_PR_URL (${pr_check})"
      echo "  Jira updated          : ${JIRA_URL:-(no Jira URL provided)}"
      echo ""
      exit 0
    fi
  done
fi

# ── Trigger the workflow ──────

echo "Triggering odh-konflux-onboarder workflow..."

cd "$WORKDIR"

TRIGGER_INPUTS=(
  "--input" "component=${COMPONENT}"
  "--input" "pr_target_branch=${PR_TARGET_BRANCH}"
  "--input" "build_type=${BUILD_TYPE}"
)
if [[ "$BUILD_TYPE" == "Release" ]]; then
  TRIGGER_INPUTS+=("--input" "version=${VERSION}")
fi

RUN_ID=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" trigger \
  --repo-url "$OKC_URL" \
  --workflow "$WORKFLOW_FILE" \
  --ref "$OKC_REF" \
  "${TRIGGER_INPUTS[@]}") || {
  exit_code=$?
  if grep -qi "422" <<< "${error_msg:-}"; then
    echo "ERROR in Step 6 (Trigger): Workflow dispatch rejected (HTTP 422)." >&2
    echo "  Most likely cause: '$COMPONENT' is not yet in the workflow's component options list." >&2
    echo "  Ensure the Step 4 skill PR (add-component-to-odh-konflux-central) is merged first." >&2
  elif grep -qi "403" <<< "${error_msg:-}"; then
    echo "ERROR in Step 6 (Trigger): Permission denied (HTTP 403)." >&2
    echo "  GITHUB_TOKEN needs 'actions:write' scope." >&2
  else
    echo "ERROR in Step 6 (Trigger): Could not dispatch workflow." >&2
  fi
  exit $exit_code
}

echo "Workflow run triggered."
echo "  Run ID   : $RUN_ID"
echo "  Run URL  : https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}"

if [[ -n "$JIRA_URL" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --comment "odh-konflux-onboarder workflow triggered (Run #${RUN_ID}).

Component       : $COMPONENT
PR target branch: $PR_TARGET_BRANCH
Build type      : $BUILD_TYPE${VERSION:+
Version         : $VERSION}

Workflow run: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}" 2>/dev/null || true
fi

# ── Monitor workflow ──────────

echo "Monitoring workflow run (timeout: 30 minutes)..."

MONITOR_OUTPUT=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" monitor \
  --repo-url "$OKC_URL" \
  --run-id "$RUN_ID" \
  --timeout 30 \
  --poll-interval 60)
WORKFLOW_STATUS="${MONITOR_OUTPUT#status=}"

case "$WORKFLOW_STATUS" in
  success)
    echo "Workflow run $RUN_ID completed successfully."
    ;;
  failure)
    echo "Workflow run $RUN_ID FAILED."
    echo "Run URL: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}"

    FAILURE_LOGS=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" get-step-logs \
      --repo-url "$OKC_URL" \
      --run-id "$RUN_ID" \
      --step "Run onboarder" 2>/dev/null | head -60 || echo "(could not fetch logs)")

    echo ""
    echo "Log excerpt:"
    echo "$FAILURE_LOGS"

    if [[ -n "$JIRA_URL" ]]; then
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --comment "odh-konflux-onboarder workflow run #${RUN_ID} FAILED.

Run URL: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}

Please inspect the run logs and re-run to retry." 2>/dev/null || true
    fi

    echo "ERROR in Step 7: Workflow run $RUN_ID failed." >&2
    exit 1
    ;;
  cancelled)
    echo "ERROR in Step 7: Workflow run $RUN_ID was cancelled." >&2
    echo "Run URL: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}" >&2
    exit 1
    ;;
  timeout)
    echo "WARNING: Workflow run $RUN_ID has not completed after 30 minutes." >&2
    echo "Run URL: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}" >&2

    if [[ -n "$JIRA_URL" ]]; then
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --comment "odh-konflux-onboarder workflow run #${RUN_ID} monitoring timed out after 30 minutes.

The run may still be completing. Run URL: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}

Re-run the script — it will detect the existing PR and resume." 2>/dev/null || true
    fi
    exit 1
    ;;
esac

# ── Extract Tekton PR URL ─────

echo "Extracting Tekton PR URL from workflow logs..."

STEP_LOGS=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" get-step-logs \
  --repo-url "$OKC_URL" \
  --run-id "$RUN_ID" \
  --step "Create pull request" 2>/dev/null) || {
  # Try fallback step names
  STEP_LOGS=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" get-step-logs \
    --repo-url "$OKC_URL" \
    --run-id "$RUN_ID" \
    --step "create-pull-request" 2>/dev/null) || \
  STEP_LOGS=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" get-step-logs \
    --repo-url "$OKC_URL" \
    --run-id "$RUN_ID" \
    --step "Create PR" 2>/dev/null) || \
  STEP_LOGS=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" get-step-logs \
    --repo-url "$OKC_URL" \
    --run-id "$RUN_ID" \
    --step "pull request" 2>/dev/null) || STEP_LOGS=""
}

TEKTON_PR_URL=$(echo "$STEP_LOGS" \
  | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' \
  | head -1)

if [[ -z "$TEKTON_PR_URL" ]]; then
  echo "WARNING: Could not auto-extract PR URL from step logs." >&2
  echo "Run URL: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}" >&2
  echo "Please locate the PR URL from the workflow logs manually." >&2
  exit 1
fi

echo "Tekton PR URL: $TEKTON_PR_URL"

# ── Update Jira with PR URL ───

if [[ -n "$JIRA_URL" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "tekton-pr-raised" \
    --comment "odh-konflux-onboarder workflow completed successfully.

Tekton PR raised: $TEKTON_PR_URL

Component        : $COMPONENT
PR target branch : $PR_TARGET_BRANCH
Build type       : $BUILD_TYPE${VERSION:+
Version          : $VERSION}
Workflow run     : https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}" 2>/dev/null || \
  echo "WARN: Could not update Jira. Update manually." >&2
fi

# ── Done ──────────────────────

echo ""
echo "=== run-odh-konflux-onboarder-workflow complete ==="
echo ""
echo "  Component             : $COMPONENT"
echo "  PR target branch      : $PR_TARGET_BRANCH"
echo "  Build type            : $BUILD_TYPE${VERSION:+
  Version               : $VERSION}"
echo ""
echo "  Workflow run          : https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}"
echo "  Tekton PR             : $TEKTON_PR_URL (raised — awaiting merge)"
echo ""
echo "  Jira updated          : ${JIRA_URL:-(no Jira URL provided)}"
echo ""
