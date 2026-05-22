#!/usr/bin/env bash
# onboard-konflux-components-for-odh-and-rhoai.sh — Master orchestrator for the full ODH/RHOAI
# component onboarding pipeline. Idempotent — run any number of times for the same Jira.
#
# Usage:
#   ./scripts/onboard-konflux-components-for-odh-and-rhoai.sh <jira-url>
#
# Required env vars:
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#   GITHUB_USER, GITHUB_TOKEN
#   GITLAB_USER, GITLAB_TOKEN
#
# Optional env vars:
#   EXT_OC_TOKEN, INT_OC_TOKEN
#   APP_INTERFACE_REPO_URL, KONFLUX_RELEASE_DATA_REPO_URL,
#   ODH_KONFLUX_CENTRAL_REPO_URL, ODH_OPERATOR_REPO_URL, OBC_REPO_URL,
#   RHOAI_KONFLUX_CENTRAL_REPO_URL, PYXIS_REPO_CONFIGS_REPO_URL,
#   RHODS_DEVOPS_INFRA_REPO_URL, JIRA_SERVER

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Track whether any new PRs/MRs were raised this run
NEW_PRS_RAISED="false"

# ─── Step 0: Parse Inputs ───────────────────────────────────────────────────
eval "$(bash "$SCRIPTS_DIR/parse_jira_url.sh" "${1:-}")"
[[ -z "$JIRA_URL" ]] && {
  echo "ERROR: Jira URL is required."
  echo "  Usage: ./scripts/onboard-konflux-components-for-odh-and-rhoai.sh <jira-url>"
  exit 1
}
echo "Jira ID  : $JIRA_ID"
echo "Jira URL : $JIRA_URL"

# ─── Step 1: Check Prerequisites ────────────────────────────────────────────
bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "JIRA_USER_EMAIL JIRA_API_TOKEN GITLAB_USER GITLAB_TOKEN GITHUB_USER GITHUB_TOKEN" \
  --tools "uv git oc skopeo yamllint jq kustomize"

[[ -x "${HOME}/.local/bin/kustomize" ]] && export PATH="${HOME}/.local/bin:${PATH}"

# ─── Step 2: Set Up Working Directory and Initialize State ──────────────────
eval "$(bash "$SCRIPTS_DIR/init_pipeline.sh" --jira-url "$JIRA_URL")"
echo "Working directory: $WORKDIR"
echo "Pipeline state: $PIPELINE_STATE"

# ─── Step 3: Validate Jira (sub-skill) ──────────────────────────────────────
VALIDATE_STATUS=$(jq -r '.steps.validate.status // "pending"' "$PIPELINE_STATE")
if [[ "$VALIDATE_STATUS" != "done" ]]; then
  echo "[orchestrator] Running validate-component-onboarding-jira..."
  if bash "$SCRIPTS_DIR/validate-component-onboarding-jira.sh" "$JIRA_URL" --workdir "$WORKDIR"; then
    bash "$SCRIPTS_DIR/pipeline_state.sh" set \
      --state "$PIPELINE_STATE" --step validate --field status --value "done"
    echo "[orchestrator] Validation complete."
  else
    echo "ERROR: Validation failed. Fix the Jira YAML and re-run."
    exit 1
  fi
else
  echo "[orchestrator] Validation already done — skipping."
fi

# ─── Step 4: Parse Component Details ────────────────────────────────────────
eval "$(bash "$SCRIPTS_DIR/parse_component_details.sh" \
  --workdir        "$WORKDIR" \
  --jira-id        "$JIRA_ID" \
  --scripts-dir    "$SCRIPTS_DIR" \
  --pipeline-state "$PIPELINE_STATE")" || {
  echo "ERROR in Step 4 (Parse Component Details): Could not parse YAML or derive PRODUCT_CONTEXT. Aborting."
  exit 1
}
# Sets: COMPONENT_NAME IS_OPERATOR REPO_URL REPO_BRANCH
#       PRODUCT_CONTEXT QUAY_ORG QUAY_VISIBILITY QUAY_REPO_URI

# Re-init state with full context (handles old state files missing new steps)
bash "$SCRIPTS_DIR/init_pipeline.sh" \
  --jira-url         "$JIRA_URL" \
  --workdir-override "$WORKDIR" \
  --product-context  "$PRODUCT_CONTEXT" \
  --component-name   "$COMPONENT_NAME" \
  --is-operator      "$IS_OPERATOR" \
  > /dev/null

echo "Component : $COMPONENT_NAME"
echo "Product   : $PRODUCT_CONTEXT"

# ─── Step 5: Sync State from Jira Labels ────────────────────────────────────
echo "[orchestrator] Syncing state from Jira labels..."
uv run --script "$SCRIPTS_DIR/sync_state_from_jira.py" \
  --jira-details   "$WORKDIR/component_onboarding_details.json" \
  --pipeline-state "$PIPELINE_STATE" || {
  echo "WARNING: Jira label sync failed — continuing with local state."
}

# ─── Step 6: Check Current PR/MR Status ─────────────────────────────────────
echo "[orchestrator] Checking PR/MR merge status..."
NEWLY_MERGED=$(bash "$SCRIPTS_DIR/check_pr_mr_status.sh" \
  --state       "$PIPELINE_STATE" \
  --scripts-dir "$SCRIPTS_DIR") || true

# Add done labels for newly merged steps
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

if [[ -n "$NEWLY_MERGED" ]]; then
  echo "[orchestrator] Newly merged this run: $(echo "$NEWLY_MERGED" | tr '\n' ' ')"
else
  echo "[orchestrator] No new merges detected."
fi

# ─── Step 7: Compute Unblocked Steps ────────────────────────────────────────
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

if [[ -n "$UNBLOCKED_STEPS" ]]; then
  echo "[orchestrator] Unblocked steps: $(echo "$UNBLOCKED_STEPS" | tr '\n' ' ')"
else
  echo "[orchestrator] No new steps unblocked."
fi

# ─── Step 8: Execute Pending Unblocked Steps ────────────────────────────────

# Helper: record PR/MR result in pipeline state and add Jira label
record_result() {
  local step_key="$1" url="$2" url_field="$3" status="$4"
  local TMP NOW
  TMP=$(mktemp)
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg k "$step_key" --arg u "$url" --arg f "$url_field" --arg s "$status" --arg ts "$NOW" \
    '.steps[$k][$f] = $u | .steps[$k].status = $s | .last_status_change_at = $ts' \
    "$PIPELINE_STATE" > "$TMP" && mv "$TMP" "$PIPELINE_STATE"

  local LABEL
  LABEL=$(jq -r --arg k "$step_key" '.steps[$k].label_raised // ""' "$PIPELINE_STATE")
  if [[ "$status" == "done" || "$status" == "skipped" ]]; then
    LABEL=$(jq -r --arg k "$step_key" '.steps[$k].label_done // ""' "$PIPELINE_STATE")
  fi
  [[ -n "$LABEL" ]] && uv run --script "$SCRIPTS_DIR/update_jira_issue.py" \
    "$JIRA_URL" --add-label "$LABEL" || true

  NEW_PRS_RAISED="true"
}

# Check if a step is in the unblocked list
is_unblocked() {
  echo "$UNBLOCKED_STEPS" | grep -qx "$1"
}

# Step 8a: create-quay-repo (quay)
if is_unblocked "quay"; then
  echo "[orchestrator] Running create-quay-repo..."
  EXISTING_URL=$(jq -r '.steps.quay.mr_url // ""' "$PIPELINE_STATE")
  EXTRA_ARGS=""
  [[ -n "$EXISTING_URL" ]] && EXTRA_ARGS="--existing-mr-url $EXISTING_URL"
  if MR_URL=$(bash "$SCRIPTS_DIR/create-quay-repo.sh" "$QUAY_REPO_URI" --jira-url "$JIRA_URL" --workdir "$WORKDIR" $EXTRA_ARGS 2>&1 | tee /dev/stderr | grep -oE 'https://[^ ]+merge_requests/[0-9]+' | tail -1); then
    record_result "quay" "$MR_URL" "mr_url" "mr_raised"
  else
    # Check if repo already exists (exit 0 from child)
    if [[ $? -eq 0 ]]; then
      record_result "quay" "" "mr_url" "done"
    fi
  fi
fi

# Step 8b: create-rhoai-delivery-repo (delivery_repo, RHOAI only)
if is_unblocked "delivery_repo" && [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  echo "[orchestrator] Running create-rhoai-delivery-repo..."
  if MR_URL=$(bash "$SCRIPTS_DIR/create-rhoai-delivery-repo.sh" "$JIRA_URL" --workdir "$WORKDIR" 2>&1 | tee /dev/stderr | grep -oE 'https://[^ ]+merge_requests/[0-9]+' | tail -1); then
    record_result "delivery_repo" "$MR_URL" "mr_url" "mr_raised"
  else
    if [[ $? -eq 0 ]]; then
      record_result "delivery_repo" "" "mr_url" "done"
    fi
  fi
fi

# Step 8c: onboard-component-to-konflux-release-data (krd)
if is_unblocked "krd"; then
  echo "[orchestrator] Running onboard-component-to-konflux-release-data..."
  if MR_URL=$(bash "$SCRIPTS_DIR/onboard-component-to-konflux-release-data.sh" "$JIRA_URL" --workdir "$WORKDIR" 2>&1 | tee /dev/stderr | grep -oE 'https://[^ ]+merge_requests/[0-9]+' | tail -1); then
    record_result "krd" "$MR_URL" "mr_url" "mr_raised"
  else
    if [[ $? -eq 0 ]]; then
      record_result "krd" "" "mr_url" "done"
    fi
  fi
fi

# Step 8d: add-component-to-*-konflux-central (okc)
if is_unblocked "okc"; then
  if [[ "$PRODUCT_CONTEXT" == "ODH" ]]; then
    echo "[orchestrator] Running add-component-to-odh-konflux-central..."
    if PR_URL=$(bash "$SCRIPTS_DIR/add-component-to-odh-konflux-central.sh" "$JIRA_URL" --workdir "$WORKDIR" 2>&1 | tee /dev/stderr | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | tail -1); then
      record_result "okc" "$PR_URL" "pr_url" "pr_raised"
    else
      if [[ $? -eq 0 ]]; then
        record_result "okc" "" "pr_url" "done"
      fi
    fi
  elif [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
    echo "[orchestrator] Running add-component-to-rhoai-konflux-central..."
    if PR_URL=$(bash "$SCRIPTS_DIR/add-component-to-rhoai-konflux-central.sh" "$JIRA_URL" --workdir "$WORKDIR" 2>&1 | tee /dev/stderr | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | tail -1); then
      record_result "okc" "$PR_URL" "pr_url" "pr_raised"
    else
      if [[ $? -eq 0 ]]; then
        record_result "okc" "" "pr_url" "done"
      fi
    fi
  fi
fi

# Step 8e: create-pull-pipelines-in-rhoai-konflux-central (pull_pipelines, RHOAI only)
if is_unblocked "pull_pipelines" && [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  echo "[orchestrator] Running create-pull-pipelines-in-rhoai-konflux-central..."
  if PR_URL=$(bash "$SCRIPTS_DIR/create-pull-pipelines-in-rhoai-konflux-central.sh" "$JIRA_URL" --workdir "$WORKDIR" 2>&1 | tee /dev/stderr | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | tail -1); then
    record_result "pull_pipelines" "$PR_URL" "pr_url" "pr_raised"
  else
    if [[ $? -eq 0 ]]; then
      record_result "pull_pipelines" "" "pr_url" "done"
    fi
  fi
fi

# Step 8f: integrate-component-with-odh-operator (operator)
if is_unblocked "operator"; then
  if [[ "$IS_OPERATOR" == "false" ]]; then
    echo "[orchestrator] is_operator=false — skipping operator step."
    TMP=$(mktemp); NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg ts "$NOW" \
      '.steps.operator.status = "skipped" | .last_status_change_at = $ts' \
      "$PIPELINE_STATE" > "$TMP" && mv "$TMP" "$PIPELINE_STATE"
  else
    echo "[orchestrator] Running integrate-component-with-odh-operator..."
    EXISTING_URL=$(jq -r '.steps.operator.pr_url // ""' "$PIPELINE_STATE")
    EXTRA_ARGS=""
    [[ -n "$EXISTING_URL" ]] && EXTRA_ARGS="--existing-pr-url $EXISTING_URL"
    if PR_URL=$(bash "$SCRIPTS_DIR/integrate-component-with-odh-operator.sh" "$JIRA_URL" --workdir "$WORKDIR" $EXTRA_ARGS 2>&1 | tee /dev/stderr | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | tail -1); then
      record_result "operator" "$PR_URL" "pr_url" "pr_raised"
    fi
  fi
fi

# Step 8g: integrate-component-with-bundle (bundle)
if is_unblocked "bundle"; then
  echo "[orchestrator] Running integrate-component-with-bundle..."
  if PR_URL=$(bash "$SCRIPTS_DIR/integrate-component-with-bundle.sh" "$JIRA_URL" --workdir "$WORKDIR" 2>&1 | tee /dev/stderr | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | tail -1); then
    record_result "bundle" "$PR_URL" "pr_url" "pr_raised"
  fi
fi

# Step 8h: update-rhoai-product-listing (product_listing, RHOAI only)
if is_unblocked "product_listing" && [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  echo "[orchestrator] Running update-rhoai-product-listing..."
  if MR_URL=$(bash "$SCRIPTS_DIR/update-rhoai-product-listing.sh" "$JIRA_URL" --workdir "$WORKDIR" 2>&1 | tee /dev/stderr | grep -oE 'https://[^ ]+merge_requests/[0-9]+' | tail -1); then
    record_result "product_listing" "$MR_URL" "mr_url" "mr_raised"
  else
    if [[ $? -eq 0 ]]; then
      record_result "product_listing" "" "mr_url" "done"
    fi
  fi
fi

# Step 8i: setup-auto-merge (auto_merge, RHOAI only)
if is_unblocked "auto_merge" && [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  echo "[orchestrator] Running setup-auto-merge..."
  if PR_URL=$(bash "$SCRIPTS_DIR/setup-auto-merge.sh" "$JIRA_URL" --workdir "$WORKDIR" 2>&1 | tee /dev/stderr | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | tail -1); then
    record_result "auto_merge" "$PR_URL" "pr_url" "pr_raised"
  else
    if [[ $? -eq 0 ]]; then
      record_result "auto_merge" "" "pr_url" "done"
    fi
  fi
fi

# Step 8j: enable-renovate-on-rhoai-component-repo (renovate, RHOAI only)
if is_unblocked "renovate" && [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  echo "[orchestrator] Running enable-renovate-on-rhoai-component-repo..."
  if PR_URL=$(bash "$SCRIPTS_DIR/enable-renovate-on-rhoai-component-repo.sh" "$JIRA_URL" --workdir "$WORKDIR" 2>&1 | tee /dev/stderr | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | tail -1); then
    record_result "renovate" "$PR_URL" "pr_url" "pr_raised"
  else
    if [[ $? -eq 0 ]]; then
      record_result "renovate" "" "pr_url" "done"
    fi
  fi
fi

# ─── Step 9: Handle Workflow Triggers ────────────────────────────────────────

# Step 9a: run-odh-konflux-onboarder-workflow (onboarder_workflow, ODH only)
if is_unblocked "onboarder_workflow" && [[ "$PRODUCT_CONTEXT" == "ODH" ]]; then
  echo "[orchestrator] Running run-odh-konflux-onboarder-workflow..."
  if TEKTON_PR_URL=$(bash "$SCRIPTS_DIR/run-odh-konflux-onboarder-workflow.sh" "$JIRA_URL" --workdir "$WORKDIR" 2>&1 | tee /dev/stderr | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | tail -1); then
    TMP=$(mktemp); NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg u "$TEKTON_PR_URL" --arg s "pr_raised" --arg ts "$NOW" \
      '.steps.onboarder_workflow.pr_url = $u | .steps.onboarder_workflow.status = $s | .last_status_change_at = $ts' \
      "$PIPELINE_STATE" > "$TMP" && mv "$TMP" "$PIPELINE_STATE"
    NEW_PRS_RAISED="true"
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --add-label "tekton-pr-raised" || true
  fi
fi

# Step 9b: sync-rhoai-renovate-configs (renovate_sync, RHOAI only)
if is_unblocked "renovate_sync" && [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  echo "[orchestrator] Running sync-rhoai-renovate-configs..."
  RKC_URL="${RHOAI_KONFLUX_CENTRAL_REPO_URL:-https://github.com/red-hat-data-services/konflux-central.git}"
  if bash "$SCRIPTS_DIR/sync-rhoai-renovate-configs.sh" "$JIRA_URL" --workdir "$WORKDIR"; then
    # The sync skill sets RUN_ID and RKC_PATH — build the URL
    RKC_PATH=$(echo "$RKC_URL" | sed 's|https://github.com/||; s|\.git$||')
    RUN_URL="https://github.com/${RKC_PATH}/actions"
    TMP=$(mktemp); NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg ts "$NOW" --arg url "$RUN_URL" \
      '.steps.renovate_sync.status = "done" | .steps.renovate_sync.run_url = $url | .last_status_change_at = $ts' \
      "$PIPELINE_STATE" > "$TMP" && mv "$TMP" "$PIPELINE_STATE"
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --add-label "renovate-sync-triggered" || true
    NEW_PRS_RAISED="true"
  fi
fi

# ─── Step 10: Check Idle Reminder ───────────────────────────────────────────
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

# ─── Step 11: Post Pending PRs/MRs Summary to Jira ──────────────────────────
SOMETHING_CHANGED="false"
[[ -n "$NEWLY_MERGED" ]] && SOMETHING_CHANGED="true"
[[ "${NEW_PRS_RAISED:-false}" == "true" ]] && SOMETHING_CHANGED="true"

if [[ "$SOMETHING_CHANGED" == "true" ]]; then
  PENDING_COMMENT=$(uv run --script "$SCRIPTS_DIR/build_progress_summary.py" \
    --state           "$PIPELINE_STATE" \
    --component-name  "$COMPONENT_NAME" \
    --product-context "$PRODUCT_CONTEXT" \
    --mode            "pending-only" \
    ${ASSIGNEE:+--assignee "$ASSIGNEE"}) || true

  if [[ -n "$PENDING_COMMENT" ]]; then
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --comment "$PENDING_COMMENT" || true
  fi
fi

# ─── Step 12: Resolve or Keep in Review ──────────────────────────────────────
ALL_DONE=$(jq -r '
  [.steps | to_entries[] | select(.value.status != "skipped")] |
  all(.value.status == "done" or .value.status == "merged")
' "$PIPELINE_STATE")

if [[ "$ALL_DONE" == "true" ]]; then
  # All steps complete — resolve the Jira ticket
  FULL_COMMENT=$(uv run --script "$SCRIPTS_DIR/build_progress_summary.py" \
    --state           "$PIPELINE_STATE" \
    --component-name  "$COMPONENT_NAME" \
    --product-context "$PRODUCT_CONTEXT" \
    --mode            "full") || true

  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --comment   "$FULL_COMMENT" \
    --add-label "component-onboarding-completed" \
    --status    "Resolved" || true

  echo "[orchestrator] All steps complete — Jira resolved with component-onboarding-completed label."
else
  # Some steps still pending — transition to Review if PRs/MRs are open
  if [[ "$HAS_OPEN" -gt 0 ]]; then
    bash "$SCRIPTS_DIR/raise_jira_review.sh" \
      --workdir         "$WORKDIR" \
      --jira-url        "$JIRA_URL" \
      --scripts-dir     "$SCRIPTS_DIR" \
      --component-name  "$COMPONENT_NAME" \
      --product-context "$PRODUCT_CONTEXT" \
      ${ASSIGNEE:+--assignee "$ASSIGNEE"} || true
  fi
fi

# ─── Print Final Summary ────────────────────────────────────────────────────
echo ""
echo "=== onboard-konflux-components-for-odh-and-rhoai — Run Complete ==="
echo ""
echo "  Component      : $COMPONENT_NAME"
echo "  Product        : $PRODUCT_CONTEXT"
echo "  Jira           : $JIRA_URL"
echo ""
echo "PRs / MRs:"

print_step_status() {
  local key="$1" label="$2"
  local status url
  status=$(jq -r --arg k "$key" '.steps[$k].status // "N/A"' "$PIPELINE_STATE")
  url=$(jq -r --arg k "$key" '.steps[$k].pr_url // .steps[$k].mr_url // "not yet raised"' "$PIPELINE_STATE")
  [[ "$url" == "null" || -z "$url" ]] && url="not yet raised"
  printf "  %-20s: %s — %s\n" "$label" "$status" "$url"
}

print_step_status "quay"               "quay"
print_step_status "krd"                "krd"
print_step_status "okc"                "okc"

if [[ "$PRODUCT_CONTEXT" == "RHOAI" ]]; then
  print_step_status "pull_pipelines"   "pull_pipelines"
  print_step_status "delivery_repo"    "delivery_repo"
  print_step_status "product_listing"  "product_listing"
  print_step_status "auto_merge"       "auto_merge"
  print_step_status "renovate"         "renovate"
  print_step_status "renovate_sync"    "renovate_sync"
else
  echo "  pull_pipelines    : N/A (ODH)"
  echo "  delivery_repo     : N/A (ODH)"
  echo "  product_listing   : N/A (ODH)"
  echo "  auto_merge        : N/A (ODH)"
  echo "  renovate          : N/A (ODH)"
  echo "  renovate_sync     : N/A (ODH)"
fi

print_step_status "operator"           "operator"
print_step_status "bundle"             "bundle"

if [[ "$PRODUCT_CONTEXT" == "ODH" ]]; then
  print_step_status "onboarder_workflow" "onboarder_workflow"
else
  echo "  onboarder_workflow: N/A (RHOAI)"
fi

echo ""
echo "Newly merged this run : ${NEWLY_MERGED:-none}"
echo "State file            : $PIPELINE_STATE"
echo ""
echo "Re-run this script after PRs/MRs are merged to advance the pipeline."
