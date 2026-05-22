#!/usr/bin/env bash
# run-odh-konflux-onboarder-workflow.sh — Trigger the odh-konflux-onboarder
# GitHub Actions workflow and extract the resulting Tekton PR URL.
#
# Usage:
#   ./scripts/run-odh-konflux-onboarder-workflow.sh [--jira-url <url>]
#
# Without --jira-url the script runs in interactive mode, prompting for inputs.
# With --jira-url it reads inputs from the Jira attachment.
#
# Required env vars:
#   GITHUB_USER  — your GitHub username
#   GITHUB_TOKEN — GitHub PAT with repo + actions:write scope
#
# Required when --jira-url is provided:
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional:
#   ODH_KONFLUX_CENTRAL_REPO_URL — override default odh-konflux-central repo URL
#   JIRA_SERVER                  — override default Jira server URL

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

JIRA_URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jira-url) JIRA_URL="$2"; shift 2 ;;
    *) JIRA_URL="$1"; shift ;;
  esac
done

JIRA_ID=""
if [[ -n "$JIRA_URL" ]]; then
  eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "$JIRA_URL")"
fi
echo "JIRA_URL : ${JIRA_URL:-(not provided)}"
echo "JIRA_ID  : ${JIRA_ID:-(not provided)}"

# Resolve OKC repo URL — single source of truth for all GitHub operations
OKC_URL="${ODH_KONFLUX_CENTRAL_REPO_URL:-https://github.com/opendatahub-io/odh-konflux-central.git}"
echo "OKC_URL resolved to: $OKC_URL"

# Derive owner/repo path for GitHub API calls
OKC_PATH=$(echo "$OKC_URL" | sed 's|https://github.com/||;s|\.git$||')

# Workflow dispatch target
OKC_REF="main"
WORKFLOW_FILE=".github/workflows/odh-konflux-onboarder.yml"

# ── Check prerequisites ──────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "GITHUB_USER GITHUB_TOKEN" \
  --tools "uv"

if [[ -n "$JIRA_URL" ]]; then
  bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "JIRA_USER_EMAIL JIRA_API_TOKEN"
fi

# ── Set up working directory ─────────────────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "${JIRA_URL:-}")"
YAML_PATH="${WORKDIR}/component_onboarding_details.yaml"
echo "Working directory: $WORKDIR"

# ── Collect component inputs ─────────────────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  # Branch A — Jira URL provided
  cd "$WORKDIR"

  if [[ ! -f "$WORKDIR/component_onboarding_details.json" ]]; then
    uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL" || {
      echo "ERROR in Step 3 (Fetch Jira): Could not fetch Jira issue. Aborting."
      exit 1
    }
  fi

  if [[ ! -f "$YAML_PATH" ]]; then
    uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
      "$JIRA_URL" component_onboarding_details.yaml || {
      echo "ERROR in Step 3 (Download YAML): 'component_onboarding_details.yaml' not found as a"
      echo "  Jira attachment. Please attach the file to the Jira issue and re-run."
      exit 1
    }
  fi

  # Parse YAML
  PRODUCT_CONTEXT=$(grep -m1 'product_context:' "$YAML_PATH" | awk '{print $2}')
  REPO_URL=$(grep -m1 'repo_url:' "$YAML_PATH" | awk '{print $2}')
  PR_TARGET_BRANCH=$(grep -m1 'repo_branch:' "$YAML_PATH" | awk '{print $2}')
  BUILD_TYPE=$(grep -m1 'build_type:' "$YAML_PATH" | awk '{print $2}' 2>/dev/null || echo "")
  VERSION=$(grep -m1 'output_image_tag:' "$YAML_PATH" | awk '{print $2}' 2>/dev/null || echo "")

elif [[ -f "$YAML_PATH" ]]; then
  echo "Found component_onboarding_details.yaml in current directory. Reading inputs from file."
  echo "(Delete or rename it to use interactive mode instead.)"

  PRODUCT_CONTEXT=$(grep -m1 'product_context:' "$YAML_PATH" | awk '{print $2}')
  REPO_URL=$(grep -m1 'repo_url:' "$YAML_PATH" | awk '{print $2}')
  PR_TARGET_BRANCH=$(grep -m1 'repo_branch:' "$YAML_PATH" | awk '{print $2}')
  BUILD_TYPE=$(grep -m1 'build_type:' "$YAML_PATH" | awk '{print $2}' 2>/dev/null || echo "")
  VERSION=$(grep -m1 'output_image_tag:' "$YAML_PATH" | awk '{print $2}' 2>/dev/null || echo "")

else
  echo "ERROR: No Jira URL provided and no component_onboarding_details.yaml found."
  echo "  Provide --jira-url or place the YAML file in the working directory."
  exit 1
fi

# Derive COMPONENT from REPO_URL
REPO_NAME="${REPO_URL##*/}"
COMPONENT="${REPO_NAME%.git}"

# Normalize BUILD_TYPE
BUILD_TYPE_LOWER="${BUILD_TYPE,,}"
if [[ "$BUILD_TYPE_LOWER" == "ci" ]]; then
  BUILD_TYPE="CI"
elif [[ "$BUILD_TYPE_LOWER" == "release" ]]; then
  BUILD_TYPE="Release"
else
  echo "ERROR in Step 3: Unknown build_type '${BUILD_TYPE}'. Expected CI or Release."
  exit 1
fi

# Validate required fields
for field_name in PRODUCT_CONTEXT REPO_URL PR_TARGET_BRANCH BUILD_TYPE; do
  if [[ -z "${!field_name}" ]]; then
    echo "ERROR in Step 3: Required field '${field_name}' is missing from component_onboarding_details.yaml."
    exit 1
  fi
done

if [[ "$BUILD_TYPE" == "Release" && -z "$VERSION" ]]; then
  echo "ERROR in Step 3: build_type is Release but 'inputs.output_image_tag' is missing from"
  echo "  component_onboarding_details.yaml. Add 'output_image_tag: <version>' under inputs: and re-run."
  exit 1
fi

# Product context gate — ODH only
if [[ "${PRODUCT_CONTEXT^^}" == "RHOAI" ]]; then
  echo "ERROR: This workflow is for ODH component onboarding only."
  echo "  RHOAI onboarding uses a different process. Aborting."
  exit 1
fi

# ── Show collected inputs ────────────────────────────────────────────────────

echo ""
echo "Workflow inputs collected:"
echo ""
echo "  OKC repo              : $OKC_URL"
echo "  Workflow file         : $WORKFLOW_FILE"
echo "  Dispatch ref          : $OKC_REF"
echo ""
echo "  component             : $COMPONENT"
echo "  pr_target_branch      : $PR_TARGET_BRANCH"
echo "  build_type            : $BUILD_TYPE"
echo "  version               : ${VERSION:-N/A}"
echo "  product_context       : $PRODUCT_CONTEXT"
echo ""

# ── Idempotency check — existing Tekton PR ───────────────────────────────────

TEKTON_PR_URL=""
SKIP_TO_MONITOR=false

if [[ -n "$JIRA_URL" && -f "$WORKDIR/component_onboarding_details.json" ]]; then
  EXISTING_PR_URLS=$(jq -r '.fields.comment.comments[].body' \
    "$WORKDIR/component_onboarding_details.json" 2>/dev/null \
    | grep -oE 'https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+' \
    | sort -u || true)

  for url in $EXISTING_PR_URLS; do
    if echo "$url" | grep -q "$OKC_PATH"; then
      PR_STATE=$(uv run --script "$SCRIPTS_DIR/monitor_github_pr.py" \
        --pr-url "$url" --check-only 2>/dev/null || true)
      if echo "$PR_STATE" | grep -qE 'state=(open|merged)'; then
        echo "Found existing Tekton PR: $url ($PR_STATE)"
        echo "Skipping workflow trigger — jumping to monitoring."
        TEKTON_PR_URL="$url"
        SKIP_TO_MONITOR=true
        break
      fi
    fi
  done
fi

# ── Trigger workflow ─────────────────────────────────────────────────────────

RUN_ID=""
ATTEMPT=0
MAX_ATTEMPTS=2

trigger_workflow() {
  ATTEMPT=$((ATTEMPT + 1))
  echo "Triggering workflow (attempt $ATTEMPT of $MAX_ATTEMPTS)..."

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
    "${TRIGGER_INPUTS[@]}" 2>&1) || {
    local err="$RUN_ID"
    if echo "$err" | grep -qE '422|inputs'; then
      echo "ERROR in Step 6 (Trigger): Workflow dispatch rejected (HTTP 422)."
      echo "  Most likely cause: '$COMPONENT' is not yet in the workflow's component options list."
      echo "  Ensure the Step 4 skill PR (add-component-to-odh-konflux-central) is merged first."
      exit 1
    elif echo "$err" | grep -q '403'; then
      echo "ERROR in Step 6 (Trigger): Permission denied (HTTP 403)."
      echo "  GITHUB_TOKEN needs 'actions:write' scope (or 'workflow' scope on classic PATs)."
      exit 1
    else
      echo "ERROR in Step 6 (Trigger): Could not dispatch workflow. Aborting."
      echo "$err"
      exit 1
    fi
  }

  echo "Workflow run triggered."
  echo "  Run ID   : $RUN_ID"
  echo "  Run URL  : https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}"

  # Post interim Jira comment
  if [[ -n "$JIRA_URL" ]]; then
    local version_line=""
    [[ -n "$VERSION" ]] && version_line="
Version         : $VERSION"
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --comment "odh-konflux-onboarder workflow triggered (Run #${RUN_ID}).

Component       : $COMPONENT
PR target branch: $PR_TARGET_BRANCH
Build type      : $BUILD_TYPE${version_line}

Workflow run: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}" 2>/dev/null || true
  fi
}

if [[ "$SKIP_TO_MONITOR" != "true" ]]; then
  trigger_workflow
fi

# ── Monitor workflow (30 minutes max) ────────────────────────────────────────

monitor_workflow() {
  echo "Monitoring workflow run $RUN_ID (timeout: 30 minutes)..."

  MONITOR_OUTPUT=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" monitor \
    --repo-url "$OKC_URL" \
    --run-id "$RUN_ID" \
    --timeout 30 \
    --poll-interval 60 2>&1) || true
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
        --step "Run onboarder" 2>/dev/null) || FAILURE_LOGS=""

      if [[ -n "$FAILURE_LOGS" ]]; then
        echo ""
        echo "Log excerpt:"
        echo "$FAILURE_LOGS" | head -60
      fi

      if [[ -n "$JIRA_URL" ]]; then
        uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
          --comment "odh-konflux-onboarder workflow run #${RUN_ID} FAILED.

Run URL: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}

Please inspect the run logs and re-run /run-odh-konflux-onboarder-workflow to retry." 2>/dev/null || true
      fi

      if [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; then
        echo ""
        echo "Re-triggering workflow (attempt $((ATTEMPT + 1)) of $MAX_ATTEMPTS)..."
        trigger_workflow
        monitor_workflow
        return
      else
        echo "ERROR in Step 7: Workflow failed on attempt $ATTEMPT. Manual investigation required."
        echo "Run URL: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}"
        exit 1
      fi
      ;;
    cancelled)
      echo "ERROR in Step 7: Workflow run $RUN_ID was cancelled."
      echo "Run URL: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}"
      exit 1
      ;;
    *)
      echo "WARNING: Workflow run $RUN_ID has not completed after 30 minutes."
      echo "Run URL: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}"

      if [[ -n "$JIRA_URL" ]]; then
        uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
          --comment "odh-konflux-onboarder workflow run #${RUN_ID} monitoring timed out after 30 minutes.

The run may still be completing. Run URL: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}

Re-run /run-odh-konflux-onboarder-workflow -- it will detect the existing PR and resume." 2>/dev/null || true
      fi
      exit 1
      ;;
  esac
}

if [[ "$SKIP_TO_MONITOR" != "true" ]]; then
  monitor_workflow
fi

# ── Extract Tekton PR URL from workflow logs ─────────────────────────────────

if [[ -z "$TEKTON_PR_URL" ]]; then
  STEP_NAMES=("Create pull request" "create-pull-request" "Create PR" "pull request")

  for step_name in "${STEP_NAMES[@]}"; do
    STEP_LOGS=$(uv run --script "$SCRIPTS_DIR/run_github_workflow.py" get-step-logs \
      --repo-url "$OKC_URL" \
      --run-id "$RUN_ID" \
      --step "$step_name" 2>/dev/null) && break || true
  done

  if [[ -n "${STEP_LOGS:-}" ]]; then
    TEKTON_PR_URL=$(echo "$STEP_LOGS" \
      | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' \
      | head -1 || true)
  fi

  if [[ -z "$TEKTON_PR_URL" ]]; then
    echo "WARNING: Could not locate the Tekton PR URL from workflow logs."
    echo "Run URL: https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}"
    echo ""
    echo "Please open the run in GitHub and locate the PR URL from the step logs."
    echo "Then update the Jira ticket manually with the PR URL."
    exit 1
  fi
fi

echo "Tekton PR URL: $TEKTON_PR_URL"

# ── Update Jira with PR URL ──────────────────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  local_version_line=""
  [[ -n "${VERSION:-}" ]] && local_version_line="
Version          : $VERSION"

  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "tekton-pr-raised" \
    --comment "odh-konflux-onboarder workflow completed successfully.

Tekton PR raised: $TEKTON_PR_URL

Component        : $COMPONENT
PR target branch : $PR_TARGET_BRANCH
Build type       : $BUILD_TYPE${local_version_line}
Workflow run     : https://github.com/${OKC_PATH}/actions/runs/${RUN_ID}" 2>/dev/null || {
    echo "WARN: Could not update Jira. Update manually."
  }
fi

# ── Final status report ──────────────────────────────────────────────────────

echo ""
echo "=== run-odh-konflux-onboarder-workflow complete ==="
echo ""
echo "  Component             : $COMPONENT"
echo "  PR target branch      : $PR_TARGET_BRANCH"
echo "  Build type            : $BUILD_TYPE"
[[ -n "${VERSION:-}" ]] && echo "  Version               : $VERSION"
echo ""
echo "  Workflow run          : https://github.com/${OKC_PATH}/actions/runs/${RUN_ID:-N/A}"
echo "  Tekton PR             : $TEKTON_PR_URL (raised -- awaiting merge)"
echo ""
echo "  Jira updated          : ${JIRA_URL:-(no Jira URL provided)}"
echo ""
echo "Tekton PR raised. Re-run the parent orchestrator after the PR merges to advance the pipeline."
