#!/usr/bin/env bash
# onboard-konflux-components-for-odh-and-rhoai.sh — Master orchestrator for component onboarding
#
# Usage:
#   ./scripts/onboard-konflux-components-for-odh-and-rhoai.sh <jira-url>
#
# Required env vars:
#   GITHUB_USER, GITHUB_TOKEN, GITLAB_USER, GITLAB_TOKEN
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# This orchestrator calls the individual step scripts in order,
# tracking state in pipeline_state.json for idempotent resume.

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Step 0: Parse Inputs
# ============================================================================

eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "${1:-}")"
[[ -z "$JIRA_URL" ]] && {
  echo "ERROR: Jira URL is required."
  echo "  Usage: $0 <jira-url>"
  exit 1
}
echo "Jira ID  : $JIRA_ID"
echo "Jira URL : $JIRA_URL"

# ============================================================================
# Step 1: Check Prerequisites
# ============================================================================

bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "JIRA_USER_EMAIL JIRA_API_TOKEN GITLAB_USER GITLAB_TOKEN GITHUB_USER GITHUB_TOKEN" \
  --tools "uv git oc skopeo yamllint jq kustomize"

[[ -x "${HOME}/.local/bin/kustomize" ]] && export PATH="${HOME}/.local/bin:${PATH}"

# ============================================================================
# Step 2: Set Up Working Directory and Initialize State
# ============================================================================

eval "$(bash "$SCRIPTS_DIR/init_pipeline.sh" --jira-url "$JIRA_URL")"
echo "Working directory: $WORKDIR"
echo "Pipeline state: $PIPELINE_STATE"

# ============================================================================
# Step 3: Sub-skill — validate-component-onboarding-jira
# ============================================================================

VALIDATE_STATUS=$(jq -r '.steps.validate.status // "pending"' "$PIPELINE_STATE")
if [[ "$VALIDATE_STATUS" == "done" ]]; then
  echo "[orchestrator] Step 3 (validate-component-onboarding-jira) already done — skipping"
else
  echo "[orchestrator] Running validate-component-onboarding-jira..."

  # Call the validate script
  bash "$SCRIPTS_DIR/validate-component-onboarding-jira.sh" "$JIRA_URL" || {
    echo "ERROR in Step 3 (validate-component-onboarding-jira): Validation failed. Aborting."
    exit 1
  }

  # Mark step as done
  bash "$SCRIPTS_DIR/pipeline_state.sh" set \
    --state "$PIPELINE_STATE" --step validate --field status --value "done"
fi

# ============================================================================
# Step 4: Parse Component Details and Derive Computed Variables
# ============================================================================

COMPONENT_NAME_IN_STATE=$(jq -r '.component_name // ""' "$PIPELINE_STATE")

eval "$(bash "$SCRIPTS_DIR/parse_component_details.sh" \
  --workdir        "$WORKDIR" \
  --jira-id        "$JIRA_ID" \
  --scripts-dir    "$SCRIPTS_DIR" \
  --pipeline-state "$PIPELINE_STATE")" || {
  echo "ERROR in Step 4 (Parse Component Details): Could not parse YAML or derive PRODUCT_CONTEXT. Aborting."
  exit 1
}

# Update the state schema for any steps not yet in the file
bash "$SCRIPTS_DIR/init_pipeline.sh" \
  --jira-url         "$JIRA_URL" \
  --workdir-override "$WORKDIR" \
  --product-context  "$PRODUCT_CONTEXT" \
  --component-name   "$COMPONENT_NAME" \
  --is-operator      "$IS_OPERATOR" \
  > /dev/null

# ============================================================================
# Step 5: Sync State from Jira Labels
# ============================================================================

echo "[orchestrator] Syncing state from Jira labels..."
uv run --script "$SCRIPTS_DIR/sync_state_from_jira.py" \
  --jira-details   "$WORKDIR/component_onboarding_details.json" \
  --pipeline-state "$PIPELINE_STATE" || {
  echo "WARNING: sync_state_from_jira.py failed — continuing anyway"
}

# ============================================================================
# Step 6: Check Current PR/MR Status
# ============================================================================

echo "[orchestrator] Checking PR/MR status..."
NEWLY_MERGED=$(bash "$SCRIPTS_DIR/check_pr_mr_status.sh" \
  --state      "$PIPELINE_STATE" \
  --scripts-dir "$SCRIPTS_DIR")

# For each newly merged step, add its label_done and remove label_raised
if [[ -n "$NEWLY_MERGED" ]]; then
  echo "[orchestrator] Newly merged steps: $NEWLY_MERGED"
  for MERGED_KEY in $NEWLY_MERGED; do
    DONE_LABEL=$(jq -r --arg k "$MERGED_KEY" '.steps[$k].label_done // ""' "$PIPELINE_STATE")
    RAISED_LABEL=$(jq -r --arg k "$MERGED_KEY" '.steps[$k].label_raised // ""' "$PIPELINE_STATE")
    LABEL_ARGS=""
    [[ -n "$DONE_LABEL" ]]   && LABEL_ARGS="$LABEL_ARGS --add-label $DONE_LABEL"
    [[ -n "$RAISED_LABEL" ]] && LABEL_ARGS="$LABEL_ARGS --remove-label $RAISED_LABEL"
    if [[ -n "$LABEL_ARGS" ]]; then
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        $LABEL_ARGS || true
    fi
  done
fi

# ============================================================================
# Step 7: Compute Unblocked Steps
# ============================================================================

echo "[orchestrator] Computing unblocked steps..."
UNBLOCKED_STEPS=$(jq -r '
  .steps as $steps |
  $steps | to_entries[] |
  select(.value.status == "pending") |
  select(
    .value.depends_on | all(. as $dep |
      $steps[$dep].status == "merged" or $steps[$dep].status == "done"
    )
  ) | .key
' "$PIPELINE_STATE")

echo "[orchestrator] Unblocked steps: ${UNBLOCKED_STEPS:-none}"

# ============================================================================
# Step 8: Execute Pending Unblocked Steps
# ============================================================================

NEW_PRS_RAISED="false"

# Helper function to check if a step is in the unblocked list
is_unblocked() {
  local step_key="$1"
  echo "$UNBLOCKED_STEPS" | grep -qw "$step_key"
}

# Helper function to record PR/MR URL and update state
record_pr_mr() {
  local step_key="$1"
  local url="$2"
  local url_field="$3"  # "pr_url" or "mr_url"
  local status="$4"     # "pr_raised" or "mr_raised"
  local label="$5"      # label to add

  TMP=$(mktemp); NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg k "$step_key" --arg u "$url" --arg f "$url_field" --arg s "$status" --arg ts "$NOW" \
    '.steps[$k][$f] = $u | .steps[$k].status = $s | .last_status_change_at = $ts' \
    "$PIPELINE_STATE" > "$TMP" && mv "$TMP" "$PIPELINE_STATE"

  [[ -n "$label" ]] && uv run --script "$SCRIPTS_DIR/update_jira_issue.py" \
    "$JIRA_URL" --add-label "$label" || true

  NEW_PRS_RAISED="true"
}

# Step 8a: create-quay-repo
if is_unblocked "quay"; then
  URL_FIELD=$(jq -r '.steps.quay.mr_url // ""' "$PIPELINE_STATE")
  if [[ -n "$URL_FIELD" ]]; then
    echo "[orchestrator] quay already has URL $URL_FIELD — skipping"
  else
    echo "[orchestrator] Running create-quay-repo..."
    bash "$SCRIPTS_DIR/create-quay-repo.sh" "$JIRA_URL" || {
      echo "WARNING: create-quay-repo failed"
    }

    # Check if step is now done or has an MR
    QUAY_STATUS=$(jq -r '.steps.quay.status // "pending"' "$PIPELINE_STATE")
    if [[ "$QUAY_STATUS" == "done" ]]; then
      echo "[orchestrator] Quay repo already exists — marking as done"
    else
      # Extract MR URL from the script's output or state
      MR_URL=$(jq -r '.steps.quay.mr_url // ""' "$PIPELINE_STATE")
      if [[ -n "$MR_URL" ]]; then
        record_pr_mr "quay" "$MR_URL" "mr_url" "mr_raised" "quay-mr-raised"
      fi
    fi
  fi
fi

# Step 8b: create-rhoai-delivery-repo (RHOAI only)
if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]] && is_unblocked "delivery_repo"; then
  URL_FIELD=$(jq -r '.steps.delivery_repo.mr_url // ""' "$PIPELINE_STATE")
  if [[ -n "$URL_FIELD" ]]; then
    echo "[orchestrator] delivery_repo already has URL $URL_FIELD — skipping"
  else
    echo "[orchestrator] Running create-rhoai-delivery-repo..."
    bash "$SCRIPTS_DIR/create-rhoai-delivery-repo.sh" "$JIRA_URL" || {
      echo "WARNING: create-rhoai-delivery-repo failed"
    }

    DELIVERY_STATUS=$(jq -r '.steps.delivery_repo.status // "pending"' "$PIPELINE_STATE")
    if [[ "$DELIVERY_STATUS" == "done" ]]; then
      echo "[orchestrator] Delivery repo already exists — marking as done"
    else
      MR_URL=$(jq -r '.steps.delivery_repo.mr_url // ""' "$PIPELINE_STATE")
      if [[ -n "$MR_URL" ]]; then
        record_pr_mr "delivery_repo" "$MR_URL" "mr_url" "mr_raised" "delivery-repo-mr-raised"
      fi
    fi
  fi
fi

# Step 8c: onboard-component-to-konflux-release-data
if is_unblocked "krd"; then
  URL_FIELD=$(jq -r '.steps.krd.mr_url // ""' "$PIPELINE_STATE")
  if [[ -n "$URL_FIELD" ]]; then
    echo "[orchestrator] krd already has URL $URL_FIELD — skipping"
  else
    echo "[orchestrator] Running onboard-component-to-konflux-release-data..."
    bash "$SCRIPTS_DIR/onboard-component-to-konflux-release-data.sh" "$JIRA_URL" || {
      echo "WARNING: onboard-component-to-konflux-release-data failed"
    }

    KRD_STATUS=$(jq -r '.steps.krd.status // "pending"' "$PIPELINE_STATE")
    if [[ "$KRD_STATUS" == "done" ]]; then
      echo "[orchestrator] Component already in KRD — marking as done"
    else
      MR_URL=$(jq -r '.steps.krd.mr_url // ""' "$PIPELINE_STATE")
      if [[ -n "$MR_URL" ]]; then
        record_pr_mr "krd" "$MR_URL" "mr_url" "mr_raised" "krd-mr-raised"
      fi
    fi
  fi
fi

# Step 8d: add-component-to-*-konflux-central
if is_unblocked "okc"; then
  URL_FIELD=$(jq -r '.steps.okc.pr_url // ""' "$PIPELINE_STATE")
  if [[ -n "$URL_FIELD" ]]; then
    echo "[orchestrator] okc already has URL $URL_FIELD — skipping"
  else
    if [[ "$PRODUCT_CONTEXT" == "ODH" ]]; then
      echo "[orchestrator] Running add-component-to-odh-konflux-central..."
      bash "$SCRIPTS_DIR/add-component-to-odh-konflux-central.sh" "$JIRA_URL" || {
        echo "WARNING: add-component-to-odh-konflux-central failed"
      }
      LABEL="okc-pr-raised"
    else
      echo "[orchestrator] Running add-component-to-rhoai-konflux-central..."
      bash "$SCRIPTS_DIR/add-component-to-rhoai-konflux-central.sh" "$JIRA_URL" || {
        echo "WARNING: add-component-to-rhoai-konflux-central failed"
      }
      LABEL="rkc-pr-raised"
    fi

    OKC_STATUS=$(jq -r '.steps.okc.status // "pending"' "$PIPELINE_STATE")
    if [[ "$OKC_STATUS" == "done" ]]; then
      echo "[orchestrator] PipelineRun already exists — marking as done"
    else
      PR_URL=$(jq -r '.steps.okc.pr_url // ""' "$PIPELINE_STATE")
      if [[ -n "$PR_URL" ]]; then
        record_pr_mr "okc" "$PR_URL" "pr_url" "pr_raised" "$LABEL"
      fi
    fi
  fi
fi

# Step 8e: create-pull-pipelines-in-rhoai-konflux-central (RHOAI only)
if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]] && is_unblocked "pull_pipelines"; then
  URL_FIELD=$(jq -r '.steps.pull_pipelines.pr_url // ""' "$PIPELINE_STATE")
  if [[ -n "$URL_FIELD" ]]; then
    echo "[orchestrator] pull_pipelines already has URL $URL_FIELD — skipping"
  else
    echo "[orchestrator] Running create-pull-pipelines-in-rhoai-konflux-central..."
    bash "$SCRIPTS_DIR/create-pull-pipelines-in-rhoai-konflux-central.sh" "$JIRA_URL" || {
      echo "WARNING: create-pull-pipelines-in-rhoai-konflux-central failed"
    }

    PULL_STATUS=$(jq -r '.steps.pull_pipelines.status // "pending"' "$PIPELINE_STATE")
    if [[ "$PULL_STATUS" == "done" ]]; then
      echo "[orchestrator] Pull pipelines already exist — marking as done"
    else
      PR_URL=$(jq -r '.steps.pull_pipelines.pr_url // ""' "$PIPELINE_STATE")
      if [[ -n "$PR_URL" ]]; then
        record_pr_mr "pull_pipelines" "$PR_URL" "pr_url" "pr_raised" "rkc-pull-pr-raised"
      fi
    fi
  fi
fi

# Step 8f: integrate-component-with-odh-operator
if is_unblocked "operator"; then
  if [[ "$IS_OPERATOR" == "false" ]]; then
    echo "[orchestrator] IS_OPERATOR=false — marking operator step as skipped"
    bash "$SCRIPTS_DIR/pipeline_state.sh" set \
      --state "$PIPELINE_STATE" --step operator --field status --value "skipped"
  else
    URL_FIELD=$(jq -r '.steps.operator.pr_url // ""' "$PIPELINE_STATE")
    if [[ -n "$URL_FIELD" ]]; then
      echo "[orchestrator] operator already has URL $URL_FIELD — skipping"
    else
      echo "[orchestrator] Running integrate-component-with-odh-operator..."
      bash "$SCRIPTS_DIR/integrate-component-with-odh-operator.sh" "$JIRA_URL" || {
        echo "WARNING: integrate-component-with-odh-operator failed"
      }

      PR_URL=$(jq -r '.steps.operator.pr_url // ""' "$PIPELINE_STATE")
      if [[ -n "$PR_URL" ]]; then
        record_pr_mr "operator" "$PR_URL" "pr_url" "pr_raised" "operator-pr-raised"
      fi
    fi
  fi
fi

# Step 8g: integrate-component-with-bundle
if is_unblocked "bundle"; then
  URL_FIELD=$(jq -r '.steps.bundle.pr_url // ""' "$PIPELINE_STATE")
  if [[ -n "$URL_FIELD" ]]; then
    echo "[orchestrator] bundle already has URL $URL_FIELD — skipping"
  else
    echo "[orchestrator] Running integrate-component-with-bundle..."
    bash "$SCRIPTS_DIR/integrate-component-with-bundle.sh" "$JIRA_URL" || {
      echo "WARNING: integrate-component-with-bundle failed"
    }

    PR_URL=$(jq -r '.steps.bundle.pr_url // ""' "$PIPELINE_STATE")
    if [[ -n "$PR_URL" ]]; then
      record_pr_mr "bundle" "$PR_URL" "pr_url" "pr_raised" "bundle-pr-raised"
    fi
  fi
fi

# Step 8h: update-rhoai-product-listing (RHOAI only)
if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]] && is_unblocked "product_listing"; then
  URL_FIELD=$(jq -r '.steps.product_listing.mr_url // ""' "$PIPELINE_STATE")
  if [[ -n "$URL_FIELD" ]]; then
    echo "[orchestrator] product_listing already has URL $URL_FIELD — skipping"
  else
    echo "[orchestrator] Running update-rhoai-product-listing..."
    bash "$SCRIPTS_DIR/update-rhoai-product-listing.sh" "$JIRA_URL" || {
      echo "WARNING: update-rhoai-product-listing failed"
    }

    LISTING_STATUS=$(jq -r '.steps.product_listing.status // "pending"' "$PIPELINE_STATE")
    if [[ "$LISTING_STATUS" == "done" ]]; then
      echo "[orchestrator] Product listing already exists — marking as done"
    else
      MR_URL=$(jq -r '.steps.product_listing.mr_url // ""' "$PIPELINE_STATE")
      if [[ -n "$MR_URL" ]]; then
        record_pr_mr "product_listing" "$MR_URL" "mr_url" "mr_raised" "product-listing-mr-raised"
      fi
    fi
  fi
fi

# Step 8i: setup-auto-merge (RHOAI only)
if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]] && is_unblocked "auto_merge"; then
  URL_FIELD=$(jq -r '.steps.auto_merge.pr_url // ""' "$PIPELINE_STATE")
  if [[ -n "$URL_FIELD" ]]; then
    echo "[orchestrator] auto_merge already has URL $URL_FIELD — skipping"
  else
    echo "[orchestrator] Running setup-auto-merge..."
    bash "$SCRIPTS_DIR/setup-auto-merge.sh" "$JIRA_URL" || {
      echo "WARNING: setup-auto-merge failed"
    }

    AUTO_STATUS=$(jq -r '.steps.auto_merge.status // "pending"' "$PIPELINE_STATE")
    if [[ "$AUTO_STATUS" == "done" ]]; then
      echo "[orchestrator] Auto-merge entries already exist — marking as done"
    else
      PR_URL=$(jq -r '.steps.auto_merge.pr_url // ""' "$PIPELINE_STATE")
      if [[ -n "$PR_URL" ]]; then
        record_pr_mr "auto_merge" "$PR_URL" "pr_url" "pr_raised" "auto-merge-pr-raised"
      fi
    fi
  fi
fi

# Step 8j: enable-renovate-on-rhoai-component-repo (RHOAI only)
if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]] && is_unblocked "renovate"; then
  URL_FIELD=$(jq -r '.steps.renovate.pr_url // ""' "$PIPELINE_STATE")
  if [[ -n "$URL_FIELD" ]]; then
    echo "[orchestrator] renovate already has URL $URL_FIELD — skipping"
  else
    echo "[orchestrator] Running enable-renovate-on-rhoai-component-repo..."
    bash "$SCRIPTS_DIR/enable-renovate-on-rhoai-component-repo.sh" "$JIRA_URL" || {
      echo "WARNING: enable-renovate-on-rhoai-component-repo failed"
    }

    RENOVATE_STATUS=$(jq -r '.steps.renovate.status // "pending"' "$PIPELINE_STATE")
    if [[ "$RENOVATE_STATUS" == "done" ]]; then
      echo "[orchestrator] Renovate entry already exists — marking as done"
    else
      PR_URL=$(jq -r '.steps.renovate.pr_url // ""' "$PIPELINE_STATE")
      if [[ -n "$PR_URL" ]]; then
        record_pr_mr "renovate" "$PR_URL" "pr_url" "pr_raised" "renovate-pr-raised"
      fi
    fi
  fi
fi

# ============================================================================
# Step 9: Handle Workflow Triggers
# ============================================================================

# Step 9a: run-odh-konflux-onboarder-workflow (ODH only)
if [[ "$PRODUCT_CONTEXT" == "ODH" ]] && is_unblocked "onboarder_workflow"; then
  URL_FIELD=$(jq -r '.steps.onboarder_workflow.pr_url // ""' "$PIPELINE_STATE")
  if [[ -n "$URL_FIELD" ]]; then
    echo "[orchestrator] onboarder_workflow already has URL $URL_FIELD — skipping"
  else
    echo "[orchestrator] Running run-odh-konflux-onboarder-workflow..."
    bash "$SCRIPTS_DIR/run-odh-konflux-onboarder-workflow.sh" "$JIRA_URL" || {
      echo "WARNING: run-odh-konflux-onboarder-workflow failed"
    }

    TEKTON_PR_URL=$(jq -r '.steps.onboarder_workflow.pr_url // ""' "$PIPELINE_STATE")
    if [[ -n "$TEKTON_PR_URL" ]]; then
      TMP=$(mktemp); NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      jq --arg u "$TEKTON_PR_URL" --arg s "pr_raised" --arg ts "$NOW" \
        '.steps.onboarder_workflow.pr_url = $u | .steps.onboarder_workflow.status = $s | .last_status_change_at = $ts' \
        "$PIPELINE_STATE" > "$TMP" && mv "$TMP" "$PIPELINE_STATE"
      NEW_PRS_RAISED="true"
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --add-label "tekton-pr-raised" || true
    fi
  fi
fi

# Step 9b: sync-rhoai-renovate-configs (RHOAI only)
if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]] && is_unblocked "renovate_sync"; then
  SYNC_STATUS=$(jq -r '.steps.renovate_sync.status // "pending"' "$PIPELINE_STATE")
  if [[ "$SYNC_STATUS" == "done" ]]; then
    echo "[orchestrator] renovate_sync already done — skipping"
  else
    echo "[orchestrator] Running sync-rhoai-renovate-configs..."
    bash "$SCRIPTS_DIR/sync-rhoai-renovate-configs.sh" "$JIRA_URL" || {
      echo "WARNING: sync-rhoai-renovate-configs failed"
    }

    RUN_URL=$(jq -r '.steps.renovate_sync.run_url // ""' "$PIPELINE_STATE")
    if [[ -n "$RUN_URL" ]]; then
      TMP=$(mktemp); NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      jq --arg ts "$NOW" --arg url "$RUN_URL" \
        '.steps.renovate_sync.status = "done" | .steps.renovate_sync.run_url = $url | .last_status_change_at = $ts' \
        "$PIPELINE_STATE" > "$TMP" && mv "$TMP" "$PIPELINE_STATE"
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --add-label "renovate-sync-triggered" || true
    fi
  fi
fi

# ============================================================================
# Step 10: Check Idle Reminder
# ============================================================================

LAST_CHANGE=$(jq -r '.last_status_change_at // ""' "$PIPELINE_STATE")
IDLE_DAYS=0
if [[ -n "$LAST_CHANGE" ]]; then
  EPOCH_NOW=$(date +%s)
  # macOS-compatible date parsing
  EPOCH_LAST=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$LAST_CHANGE" +%s 2>/dev/null \
    || date -d "$LAST_CHANGE" +%s 2>/dev/null || echo "$EPOCH_NOW")
  IDLE_DAYS=$(( (EPOCH_NOW - EPOCH_LAST) / 86400 ))
fi

HAS_OPEN=$(jq -r '[.steps | to_entries[] | select(.value.status == "pr_raised" or .value.status == "mr_raised")] | length' "$PIPELINE_STATE")
ASSIGNEE=$(jq -r '.fields.assignee.accountId // ""' "$WORKDIR/component_onboarding_details.json" 2>/dev/null || true)

POST_IDLE_REMINDER="false"
if [[ "$HAS_OPEN" -gt 0 && "$IDLE_DAYS" -ge 2 && -n "$ASSIGNEE" ]]; then
  POST_IDLE_REMINDER="true"
fi

# ============================================================================
# Step 11: Post Pending PRs/MRs Summary to Jira
# ============================================================================

SOMETHING_CHANGED="false"
[[ -n "$NEWLY_MERGED" ]] && SOMETHING_CHANGED="true"
[[ "${NEW_PRS_RAISED:-false}" == "true" ]] && SOMETHING_CHANGED="true"

if [[ "$SOMETHING_CHANGED" == "true" ]]; then
  PENDING_COMMENT=$(uv run --script "$SCRIPTS_DIR/build_progress_summary.py" \
    --state           "$PIPELINE_STATE" \
    --component-name  "$COMPONENT_NAME" \
    --product-context "$PRODUCT_CONTEXT" \
    --mode            "pending-only" \
    ${ASSIGNEE:+--assignee "$ASSIGNEE"})

  if [[ -n "$PENDING_COMMENT" ]]; then
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --comment "$PENDING_COMMENT" || true
  fi
fi

# ============================================================================
# Step 12: Resolve or Keep in Review
# ============================================================================

ALL_DONE=$(jq -r '
  [.steps | to_entries[] | select(.value.status != "skipped")] |
  all(.value.status == "done" or .value.status == "merged")
' "$PIPELINE_STATE")

if [[ "$ALL_DONE" == "true" ]]; then
  echo "[orchestrator] All steps complete — resolving Jira"

  FULL_COMMENT=$(uv run --script "$SCRIPTS_DIR/build_progress_summary.py" \
    --state           "$PIPELINE_STATE" \
    --component-name  "$COMPONENT_NAME" \
    --product-context "$PRODUCT_CONTEXT" \
    --mode            "full")

  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --comment   "$FULL_COMMENT" \
    --add-label "component-onboarding-completed" \
    --status    "Resolved"

  echo "[orchestrator] All steps complete — Jira resolved with component-onboarding-completed label."
elif [[ "$HAS_OPEN" -gt 0 ]]; then
  echo "[orchestrator] PRs/MRs pending — transitioning to Review"

  bash "$SCRIPTS_DIR/raise_jira_review.sh" \
    --workdir         "$WORKDIR" \
    --jira-url        "$JIRA_URL" \
    --scripts-dir     "$SCRIPTS_DIR" \
    --component-name  "$COMPONENT_NAME" \
    --product-context "$PRODUCT_CONTEXT" \
    ${ASSIGNEE:+--assignee "$ASSIGNEE"}
fi

# ============================================================================
# Print Final Summary
# ============================================================================

echo ""
echo "=== onboard-konflux-components-for-odh-and-rhoai — Run Complete ==="
echo ""
echo "  Component      : $COMPONENT_NAME"
echo "  Product        : $PRODUCT_CONTEXT"
echo "  Jira           : $JIRA_URL"
echo ""
echo "PRs / MRs:"

QUAY_STATUS=$(jq -r '.steps.quay.status // "pending"' "$PIPELINE_STATE")
QUAY_URL=$(jq -r '.steps.quay.mr_url // "not yet raised"' "$PIPELINE_STATE")
echo "  quay            : $QUAY_STATUS — $QUAY_URL"

KRD_STATUS=$(jq -r '.steps.krd.status // "pending"' "$PIPELINE_STATE")
KRD_URL=$(jq -r '.steps.krd.mr_url // "not yet raised"' "$PIPELINE_STATE")
echo "  krd             : $KRD_STATUS — $KRD_URL"

OKC_STATUS=$(jq -r '.steps.okc.status // "pending"' "$PIPELINE_STATE")
OKC_URL=$(jq -r '.steps.okc.pr_url // "not yet raised"' "$PIPELINE_STATE")
echo "  okc             : $OKC_STATUS — $OKC_URL"

if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  PULL_STATUS=$(jq -r '.steps.pull_pipelines.status // "pending"' "$PIPELINE_STATE")
  PULL_URL=$(jq -r '.steps.pull_pipelines.pr_url // "not yet raised"' "$PIPELINE_STATE")
  echo "  pull_pipelines  : $PULL_STATUS — $PULL_URL"
else
  echo "  pull_pipelines  : N/A (ODH)"
fi

OPERATOR_STATUS=$(jq -r '.steps.operator.status // "pending"' "$PIPELINE_STATE")
OPERATOR_URL=$(jq -r '.steps.operator.pr_url // "not yet raised"' "$PIPELINE_STATE")
echo "  operator        : $OPERATOR_STATUS — $OPERATOR_URL"

BUNDLE_STATUS=$(jq -r '.steps.bundle.status // "pending"' "$PIPELINE_STATE")
BUNDLE_URL=$(jq -r '.steps.bundle.pr_url // "not yet raised"' "$PIPELINE_STATE")
echo "  bundle          : $BUNDLE_STATUS — $BUNDLE_URL"

if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  DELIVERY_STATUS=$(jq -r '.steps.delivery_repo.status // "pending"' "$PIPELINE_STATE")
  DELIVERY_URL=$(jq -r '.steps.delivery_repo.mr_url // "not yet raised"' "$PIPELINE_STATE")
  echo "  delivery_repo   : $DELIVERY_STATUS — $DELIVERY_URL"

  LISTING_STATUS=$(jq -r '.steps.product_listing.status // "pending"' "$PIPELINE_STATE")
  LISTING_URL=$(jq -r '.steps.product_listing.mr_url // "not yet raised"' "$PIPELINE_STATE")
  echo "  product_listing : $LISTING_STATUS — $LISTING_URL"

  AUTO_STATUS=$(jq -r '.steps.auto_merge.status // "pending"' "$PIPELINE_STATE")
  AUTO_URL=$(jq -r '.steps.auto_merge.pr_url // "not yet raised"' "$PIPELINE_STATE")
  echo "  auto_merge      : $AUTO_STATUS — $AUTO_URL"

  RENOVATE_STATUS=$(jq -r '.steps.renovate.status // "pending"' "$PIPELINE_STATE")
  RENOVATE_URL=$(jq -r '.steps.renovate.pr_url // "not yet raised"' "$PIPELINE_STATE")
  echo "  renovate        : $RENOVATE_STATUS — $RENOVATE_URL"

  SYNC_STATUS=$(jq -r '.steps.renovate_sync.status // "pending"' "$PIPELINE_STATE")
  SYNC_URL=$(jq -r '.steps.renovate_sync.run_url // "not yet triggered"' "$PIPELINE_STATE")
  echo "  renovate_sync   : $SYNC_STATUS — $SYNC_URL"
else
  echo "  delivery_repo   : N/A (ODH)"
  echo "  product_listing : N/A (ODH)"
  echo "  auto_merge      : N/A (ODH)"
  echo "  renovate        : N/A (ODH)"
  echo "  renovate_sync   : N/A (ODH)"
fi

if [[ "$PRODUCT_CONTEXT" == "ODH" ]]; then
  ONBOARDER_STATUS=$(jq -r '.steps.onboarder_workflow.status // "pending"' "$PIPELINE_STATE")
  ONBOARDER_URL=$(jq -r '.steps.onboarder_workflow.pr_url // "not yet raised"' "$PIPELINE_STATE")
  echo "  onboarder_workflow: $ONBOARDER_STATUS — $ONBOARDER_URL"
else
  echo "  onboarder_workflow: N/A (RHOAI)"
fi

echo ""
echo "Newly merged this run : ${NEWLY_MERGED:-none}"
echo "State file            : $PIPELINE_STATE"
echo ""
echo "Re-run this skill after PRs/MRs are merged to advance the pipeline."
