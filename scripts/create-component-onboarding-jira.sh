#!/usr/bin/env bash
# create-component-onboarding-jira.sh — Collect component onboarding details,
# generate a validated YAML, and create/update a Jira ticket with the YAML attached.
#
# Usage:
#   ./scripts/create-component-onboarding-jira.sh \
#     --product-context <ODH|RHOAI> \
#     --component-name <name> \
#     --repo-url <url> \
#     --context-path <path> \
#     --dockerfile-path <path> \
#     --parent-feature <JIRA-ID> \
#     [--jira-url <url>] \
#     [--build-type <CI|Release>] \
#     [--target-rhoai-version <version>] \
#     [--architectures <arch1,arch2>] \
#     [--release-category <category>] \
#     [--long-description <text>] \
#     [--short-description <text>] \
#     [--repo-branch <branch>] \
#     [--is-operator] \
#     [--operator-manifest-src-path <path>] \
#     [--operator-manifest-dest-path <path>]
#
# Required env vars:
#   JIRA_USER_EMAIL  — your Atlassian account email
#   JIRA_API_TOKEN   — Atlassian Cloud API token
#
# Optional:
#   JIRA_SERVER — override default Jira server (default: https://redhat.atlassian.net)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_PATH="$(cd "$SCRIPTS_DIR/../playbooks/assets" && pwd)/component_onboarding_details.schema.json"

# ── Parse inputs ──────────────────────────────────────────────────────────────

JIRA_URL=""
JIRA_ID=""
product_context=""
component_name=""
repo_url=""
repo_branch=""
context_path=""
dockerfile_path=""
is_operator="false"
operator_manifest_src_path=""
operator_manifest_dest_path=""
build_type=""
target_rhoai_version=""
architectures=""
release_category=""
long_description=""
short_description=""
PARENT_FEATURE_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jira-url)                    JIRA_URL="$2"; shift 2 ;;
    --product-context)             product_context="${2^^}"; shift 2 ;;
    --component-name)              component_name="$2"; shift 2 ;;
    --repo-url)                    repo_url="$2"; shift 2 ;;
    --repo-branch)                 repo_branch="$2"; shift 2 ;;
    --context-path)                context_path="$2"; shift 2 ;;
    --dockerfile-path)             dockerfile_path="$2"; shift 2 ;;
    --is-operator)                 is_operator="true"; shift ;;
    --operator-manifest-src-path)  operator_manifest_src_path="$2"; shift 2 ;;
    --operator-manifest-dest-path) operator_manifest_dest_path="$2"; shift 2 ;;
    --build-type)                  build_type="$2"; shift 2 ;;
    --target-rhoai-version)        target_rhoai_version="$2"; shift 2 ;;
    --architectures)               architectures="$2"; shift 2 ;;
    --release-category)            release_category="$2"; shift 2 ;;
    --long-description)            long_description="$2"; shift 2 ;;
    --short-description)           short_description="$2"; shift 2 ;;
    --parent-feature)              PARENT_FEATURE_ID="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Parse Jira URL if provided
if [[ -n "$JIRA_URL" ]]; then
  if [[ "$JIRA_URL" != *"/browse/"* ]]; then
    echo "ERROR: Invalid Jira URL. Expected format: https://redhat.atlassian.net/browse/RHOAIENG-1234"
    exit 1
  fi
  JIRA_ID="${JIRA_URL##*/}"
fi

# ── Validate required inputs ─────────────────────────────────────────────────

missing=()
[[ -z "$product_context" ]] && missing+=("--product-context")
[[ -z "$component_name" ]] && missing+=("--component-name")
[[ -z "$repo_url" ]] && missing+=("--repo-url")
[[ -z "$context_path" ]] && missing+=("--context-path")
[[ -z "$dockerfile_path" ]] && missing+=("--dockerfile-path")
[[ -z "$PARENT_FEATURE_ID" ]] && missing+=("--parent-feature")

if [[ "$product_context" == "ODH" && -z "$build_type" ]]; then
  missing+=("--build-type (required for ODH)")
fi

if [[ "$product_context" == "RHOAI" ]]; then
  [[ -z "$target_rhoai_version" ]] && missing+=("--target-rhoai-version")
  [[ -z "$release_category" ]] && missing+=("--release-category")
  [[ -z "$long_description" ]] && missing+=("--long-description")
  [[ -z "$short_description" ]] && missing+=("--short-description")
fi

if [[ "$is_operator" == "true" ]]; then
  [[ -z "$operator_manifest_src_path" ]] && missing+=("--operator-manifest-src-path")
  [[ -z "$operator_manifest_dest_path" ]] && missing+=("--operator-manifest-dest-path")
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: Missing required arguments:"
  printf '  %s\n' "${missing[@]}"
  echo ""
  echo "Usage: $0 --product-context <ODH|RHOAI> --component-name <name> --repo-url <url> \\"
  echo "  --context-path <path> --dockerfile-path <path> --parent-feature <JIRA-ID> [options]"
  exit 1
fi

# Validate product_context
if [[ "$product_context" != "ODH" && "$product_context" != "RHOAI" ]]; then
  echo "ERROR: --product-context must be ODH or RHOAI (got: $product_context)"
  exit 1
fi

# Validate component_name format
if ! [[ "$component_name" =~ ^odh-[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "ERROR: --component-name must start with 'odh-' and contain only lowercase letters, numbers, and hyphens."
  echo "  Got: $component_name"
  exit 1
fi

# Validate repo_url format
if ! [[ "$repo_url" =~ ^https://github\.com/.+/.+$ ]]; then
  echo "ERROR: --repo-url must be a full HTTPS GitHub URL (e.g. https://github.com/opendatahub-io/my-component)"
  exit 1
fi

# Validate RHOAI Dockerfile naming
if [[ "$product_context" == "RHOAI" ]]; then
  dockerfile_basename=$(basename "$dockerfile_path")
  if [[ "$dockerfile_basename" != *"Dockerfile.konflux"* ]]; then
    echo "ERROR: For RHOAI components, the Dockerfile name must contain 'Dockerfile.konflux'."
    echo "  Got: $dockerfile_path"
    exit 1
  fi
fi

# Validate parent feature format
if ! [[ "$PARENT_FEATURE_ID" =~ ^[A-Z]+-[0-9]+$ ]]; then
  echo "ERROR: --parent-feature must be a valid Jira ID (e.g. RHAISTRAT-1234)"
  exit 1
fi

# ── Derive repo_branch for RHOAI if not provided ─────────────────────────────

if [[ "$product_context" == "RHOAI" && -z "$repo_branch" ]]; then
  VERSION_X=$(echo "$target_rhoai_version" | cut -d. -f1)
  VERSION_Y=$(echo "$target_rhoai_version" | cut -d. -f2 | cut -d- -f1)
  VERSION_N=""
  if echo "$target_rhoai_version" | grep -qE 'ea[-.]?[0-9]+'; then
    VERSION_N=$(echo "$target_rhoai_version" | grep -oE '[0-9]+$')
  fi

  if [[ -n "$VERSION_N" ]]; then
    repo_branch="rhoai-${VERSION_X}.${VERSION_Y}-ea.${VERSION_N}"
  else
    repo_branch="rhoai-${VERSION_X}.${VERSION_Y}"
  fi
  echo "repo_branch auto-set to: $repo_branch"
fi

# Default repo_branch for ODH if not provided
if [[ "$product_context" == "ODH" && -z "$repo_branch" ]]; then
  echo "ERROR: --repo-branch is required for ODH components."
  exit 1
fi

# Default architectures for RHOAI
if [[ "$product_context" == "RHOAI" && -z "$architectures" ]]; then
  architectures="x86_64,arm64"
  echo "architectures defaulted to: $architectures"
fi

# ── Check prerequisites ──────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" --tools "uv jq"
bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "JIRA_USER_EMAIL JIRA_API_TOKEN"

# ── Set up working directory ─────────────────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "${JIRA_URL:-}")"
YAML_PATH="${WORKDIR}/component_onboarding_details.yaml"
echo "Working directory: $WORKDIR"

# ── Fetch Jira details (if URL provided) ─────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  echo "Fetching Jira issue details..."
  (cd "$WORKDIR" && uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL") || {
    echo "ERROR in Step 2 (Fetch Jira): Could not fetch issue details. Aborting."
    exit 1
  }
fi

# ── Show collected inputs ────────────────────────────────────────────────────

echo ""
echo "Component onboarding details collected:"
echo ""
echo "  product_context              : $product_context"
if [[ "$product_context" == "ODH" ]]; then
  echo "  build_type                   : $build_type"
else
  echo "  target_rhoai_version         : $target_rhoai_version"
  echo "  architectures                : $architectures"
  echo "  release_category             : $release_category"
fi
echo "  component_name               : $component_name"
echo "  repo_url                     : $repo_url"
echo "  repo_branch                  : $repo_branch"
echo "  context_path                 : $context_path"
echo "  dockerfile_path              : $dockerfile_path"
if [[ "$product_context" == "RHOAI" ]]; then
  echo "  long_description             : $long_description"
  echo "  short_description            : $short_description"
fi
echo "  is_operator                  : $is_operator"
if [[ "$is_operator" == "true" ]]; then
  echo "  operator_manifest_src_path   : $operator_manifest_src_path"
  echo "  operator_manifest_dest_path  : $operator_manifest_dest_path"
fi
echo "  parent_feature               : $PARENT_FEATURE_ID"
echo "  jira_url                     : ${JIRA_URL:-(will create new)}"
echo ""

# ── Generate YAML file ───────────────────────────────────────────────────────

echo "Generating component_onboarding_details.yaml..."

YAML_ARGS=(
  --output "$YAML_PATH"
  --product-context "$product_context"
  --component-name "$component_name"
  --repo-url "$repo_url"
  --repo-branch "$repo_branch"
  --context-path "$context_path"
  --dockerfile-path "$dockerfile_path"
)

# ODH-only
if [[ "$product_context" == "ODH" ]]; then
  YAML_ARGS+=(--build-type "$build_type")
fi

# RHOAI-only
if [[ "$product_context" == "RHOAI" ]]; then
  YAML_ARGS+=(
    --target-rhoai-version "$target_rhoai_version"
    --architectures "$architectures"
    --release-category "$release_category"
    --long-description "$long_description"
    --short-description "$short_description"
  )
fi

# Operator fields
if [[ "$is_operator" == "true" ]]; then
  YAML_ARGS+=(
    --is-operator
    --operator-manifest-src-path "$operator_manifest_src_path"
    --operator-manifest-dest-path "$operator_manifest_dest_path"
  )
fi

uv run --script "$SCRIPTS_DIR/generate_onboarding_yaml.py" "${YAML_ARGS[@]}" || {
  echo "ERROR in Step 5 (Generate YAML): Could not write YAML file. Aborting."
  exit 1
}

echo "YAML generated: $YAML_PATH"

# ── Validate YAML against schema ─────────────────────────────────────────────

echo "Validating YAML against schema..."
VALIDATION_ERRORS=""
if ! VALIDATION_ERRORS=$(uv run --script "$SCRIPTS_DIR/validate_yaml_schema.py" \
  "$YAML_PATH" "$SCHEMA_PATH" 2>&1); then
  echo "ERROR in Step 6 (Validation): YAML failed schema validation:"
  echo "$VALIDATION_ERRORS"
  exit 1
fi
echo "Schema validation passed."

# ── Dockerfile digest check (RHOAI only) ─────────────────────────────────────

if [[ "$product_context" == "ODH" ]]; then
  echo "Dockerfile digest check skipped (not required for ODH components)."
else
  REPO_RAW_BASE="${repo_url/github.com/raw.githubusercontent.com}"
  CLEAN_CTX="${context_path%/}"; CLEAN_CTX="${CLEAN_CTX#./}"

  if [[ -z "$CLEAN_CTX" || "$CLEAN_CTX" == "." ]]; then
    DOCKERFILE_RAW_URL="${REPO_RAW_BASE}/${repo_branch}/${dockerfile_path}"
  else
    DOCKERFILE_RAW_URL="${REPO_RAW_BASE}/${repo_branch}/${CLEAN_CTX}/${dockerfile_path}"
  fi

  echo "Checking Dockerfile digest pinning..."
  DIGEST_ERRORS=""
  DIGEST_EXIT=0
  DIGEST_ERRORS=$(uv run --script "$SCRIPTS_DIR/check_dockerfile_digests.py" \
    --dockerfile-url "$DOCKERFILE_RAW_URL" 2>&1) || DIGEST_EXIT=$?

  if [[ $DIGEST_EXIT -eq 2 ]]; then
    echo "NOTICE: Could not fetch Dockerfile at $DOCKERFILE_RAW_URL -- skipping digest check."
    echo "         Ensure all FROM images use @sha256 digests before running /validate-component-onboarding-jira."
  elif [[ $DIGEST_EXIT -eq 1 ]]; then
    echo "ERROR in Step 6b (Dockerfile digest check): The Dockerfile contains FROM instructions"
    echo "that do not use @sha256 digests:"
    echo "$DIGEST_ERRORS"
    echo ""
    echo "All base and builder images must be pinned with @sha256 digests before onboarding can proceed."
    exit 1
  else
    echo "Dockerfile digest check passed."
  fi
fi

# ── Jira integration ─────────────────────────────────────────────────────────

TEMPLATE_ID=""

if [[ -n "$JIRA_URL" ]]; then
  # Path A — existing Jira ticket
  echo "Attaching YAML to existing Jira: $JIRA_URL"

  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --attach "$YAML_PATH" \
    --add-label "yaml-attached" \
    --link-related "$PARENT_FEATURE_ID" \
    --comment "component_onboarding_details.yaml has been generated and attached to this ticket.

Component: $component_name
Product: $product_context
Repo: $repo_url @ $repo_branch
Operator: $is_operator

This ticket is ready for onboarding automation. Run /validate-component-onboarding-jira to verify." || {
    echo "ERROR in Step 7 (Upload attachment): Could not attach YAML to Jira. Aborting."
    exit 1
  }

else
  # Path B — create new Jira from template
  if [[ "$product_context" == "ODH" ]]; then
    TEMPLATE_ID="RHOAIENG-35683"
  else
    TEMPLATE_ID="RHOAIENG-17225"
  fi

  echo "Cloning Jira template $TEMPLATE_ID..."

  NEW_JIRA_URL=$(uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "new" \
    --clone-from "$TEMPLATE_ID" \
    --remove-label "template" \
    --link-related "$PARENT_FEATURE_ID" \
    --set-reporter-to-current) || {
    echo "ERROR in Step 7b-1: Could not clone Jira template ($TEMPLATE_ID). Aborting."
    exit 1
  }

  JIRA_URL="$NEW_JIRA_URL"
  JIRA_ID="${NEW_JIRA_URL##*/}"
  echo "New Jira created: $JIRA_URL"

  # Attach YAML to the new Jira
  echo "Attaching YAML to new Jira..."
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --attach "$YAML_PATH" \
    --add-label "yaml-attached" \
    --comment "component_onboarding_details.yaml has been generated and attached to this ticket.

Component: $component_name
Product: $product_context
Repo: $repo_url @ $repo_branch
Operator: $is_operator

This ticket is ready for onboarding automation. Run /validate-component-onboarding-jira to verify." || {
    echo "ERROR in Step 7b-2 (Upload attachment): Could not attach YAML to new Jira. Aborting."
    exit 1
  }
fi

# ── Update Jira metadata ─────────────────────────────────────────────────────

echo "Updating Jira metadata..."

UPDATE_JIRA_ARGS=(
  --component-name "$component_name"
  --product-context "$product_context"
  --repo-url "$repo_url"
  --repo-branch "$repo_branch"
  --context-path "$context_path"
  --dockerfile-path "$dockerfile_path"
)

if [[ "$product_context" == "RHOAI" ]]; then
  UPDATE_JIRA_ARGS+=(
    --short-description "$short_description"
    --architectures "$architectures"
  )
fi

uv run --script "$SCRIPTS_DIR/update_onboarding_jira.py" "$JIRA_URL" "${UPDATE_JIRA_ARGS[@]}" || {
  echo "WARN in Step 7c: Could not update Jira metadata. Update manually."
}

# ── Report completion ────────────────────────────────────────────────────────

echo ""
echo "Done."
echo ""
echo "  component_onboarding_details.yaml  — generated and validated"
echo "  Jira                               — ${JIRA_ID} (${JIRA_URL})"
if [[ -n "$TEMPLATE_ID" ]]; then
  echo "                                       (created from template $TEMPLATE_ID)"
fi
echo "  Parent feature link                — $PARENT_FEATURE_ID (relates to)"
echo "  Jira attachment                    — uploaded (label: yaml-attached)"
echo "  Jira comment                       — posted"
echo ""
echo "  Output file: $YAML_PATH"
echo ""
echo "Next step: /validate-component-onboarding-jira $JIRA_URL"
