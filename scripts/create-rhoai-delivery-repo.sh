#!/usr/bin/env bash
# create-rhoai-delivery-repo.sh — Create an RHOAI delivery repository via GitLab MR to pyxis-repo-configs
#
# Usage:
#   ./scripts/create-rhoai-delivery-repo.sh [--jira-url <url>] [--existing-mr-url <url>]
#
# Required env vars:
#   GITLAB_USER   — GitLab username
#   GITLAB_TOKEN  — GitLab personal access token (api + write_repository)
#
# Required when --jira-url is provided:
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional:
#   PYXIS_REPO_CONFIGS_REPO_URL — override default pyxis-repo-configs URL
#                                  (default: https://gitlab.cee.redhat.com/releng/pyxis-repo-configs.git)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

JIRA_URL=""
JIRA_ID=""
EXISTING_MR_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jira-url)        JIRA_URL="$2"; shift 2 ;;
    --existing-mr-url) EXISTING_MR_URL="$2"; shift 2 ;;
    --workdir)       WORKDIR="$2"; shift 2 ;;
    -*)                echo "ERROR: Unknown flag: $1" >&2; exit 1 ;;
    *)
      # First positional arg treated as jira-url for backward compat
      if [[ -z "$JIRA_URL" ]]; then
        JIRA_URL="$1"; shift
      else
        echo "ERROR: Unexpected positional argument: $1" >&2; exit 1
      fi
      ;;
  esac
done

# ── Idempotency fast-path ────────────────────────────────────────────────────

if [[ -n "$EXISTING_MR_URL" ]]; then
  echo "MR already raised: $EXISTING_MR_URL"
  exit 0
fi

# ── Validate Jira URL ────────────────────────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  if [[ "$JIRA_URL" != *"/browse/"* ]]; then
    echo "ERROR: Invalid Jira URL. Expected format: https://redhat.atlassian.net/browse/RHOAIENG-1234" >&2
    exit 1
  fi
  JIRA_ID="${JIRA_URL##*/}"
fi

# ── Resolve pyxis-repo-configs URL ───────────────────────────────────────────

PYXIS_URL="${PYXIS_REPO_CONFIGS_REPO_URL:-https://gitlab.cee.redhat.com/releng/pyxis-repo-configs.git}"
echo "PYXIS_REPO_CONFIGS_REPO_URL=${PYXIS_REPO_CONFIGS_REPO_URL:-(not set, using default)}"
echo "PYXIS_URL resolved to: $PYXIS_URL"

PYXIS_PATH=$(echo "$PYXIS_URL" | sed 's|https://gitlab.cee.redhat.com/||;s|\.git$||')
PYXIS_PATH_ENCODED=$(echo "$PYXIS_PATH" | sed 's|/|%2F|g')

echo "JIRA_URL  : ${JIRA_URL:-(not provided)}"
echo "JIRA_ID   : ${JIRA_ID:-(not provided)}"
echo "PYXIS_URL : $PYXIS_URL"
echo "PYXIS_PATH: $PYXIS_PATH"

# ── Check prerequisites ──────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "GITLAB_USER GITLAB_TOKEN" \
  --tools "uv git curl"

if [[ -n "$JIRA_URL" ]]; then
  bash "$SCRIPTS_DIR/check_prerequisites.sh" \
    --env "JIRA_USER_EMAIL JIRA_API_TOKEN"
fi

# ── Set up working directory ─────────────────────────────────────────────────

eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "${JIRA_URL:-}")"
echo "Working directory: $WORKDIR"

# ── Get component YAML ───────────────────────────────────────────────────────

if [[ -f "$WORKDIR/component_onboarding_details.yaml" ]]; then
  echo "Using existing component_onboarding_details.yaml from pipeline state."
elif [[ -n "$JIRA_URL" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/download_jira_attachment.py" \
    "$JIRA_URL" component_onboarding_details.yaml || {
    echo "ERROR in Step 3b: Could not download 'component_onboarding_details.yaml'." >&2
    echo "  Ensure the attachment exists on the Jira issue." >&2
    echo "  Run /create-component-onboarding-jira <jira-url> first." >&2
    exit 1
  }
else
  echo "ERROR in Step 3: No component_onboarding_details.yaml found and no Jira URL provided." >&2
  echo "  Either provide a Jira URL or run from within the master onboarding pipeline." >&2
  exit 1
fi

# Fetch Jira details
if [[ -n "$JIRA_URL" && ! -f "$WORKDIR/component_onboarding_details.json" ]]; then
  cd "$WORKDIR"
  uv run --script "$SCRIPTS_DIR/fetch_jira_details.py" "$JIRA_URL" || {
    echo "ERROR in Step 3d (Fetch Jira): Could not fetch issue details. Aborting." >&2
    exit 1
  }
fi

# ── Parse YAML and derive variables ──────────────────────────────────────────

YAML_FILE="$WORKDIR/component_onboarding_details.yaml"
COMPONENT_NAME=$(grep -m1 'component_name:' "$YAML_FILE" | awk '{print $2}')
TARGET_RHOAI_VERSION=$(grep -m1 'target_rhoai_version:' "$YAML_FILE" | awk '{print $2}')

for _field in COMPONENT_NAME TARGET_RHOAI_VERSION; do
  [[ -z "${!_field}" ]] && {
    echo "ERROR in Step 4: Missing required field '${_field}' in component_onboarding_details.yaml." >&2
    echo "  Re-generate the YAML with /create-component-onboarding-jira <jira-url>." >&2
    exit 1
  }
done

eval "$(bash "$SCRIPTS_DIR/parse_rhoai_version.sh" \
  --version "$TARGET_RHOAI_VERSION" \
  --component "$COMPONENT_NAME")"
# Sets: CONTENT_STREAM_TAG, REPOSITORY_NAME, and other version vars

# Parse display fields (may contain spaces)
SHORT_DESCRIPTION=$(grep -m1 'short_description:' "$YAML_FILE" | sed 's/^[[:space:]]*short_description:[[:space:]]*//')
LONG_DESCRIPTION=$(grep -m1 'long_description:' "$YAML_FILE" | sed 's/^[[:space:]]*long_description:[[:space:]]*//')
RELEASE_CATEGORY=$(grep -m1 'release_category:' "$YAML_FILE" | sed 's/^[[:space:]]*release_category:[[:space:]]*//' | tr -d '"')

# Defaults
[[ -z "$SHORT_DESCRIPTION" ]] && SHORT_DESCRIPTION="$COMPONENT_NAME"
[[ -z "$LONG_DESCRIPTION" ]]  && LONG_DESCRIPTION="$COMPONENT_NAME"
[[ -z "$RELEASE_CATEGORY" ]]  && RELEASE_CATEGORY="Generally Available"

# Compute display name
DISPLAY_NAME=$(echo "$COMPONENT_NAME" | tr '-' ' ' \
  | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1' \
  | sed -E 's/\bOdh\b/ODH/g; s/\bRhoai\b/RHOAI/g; s/\bAi\b/AI/g; s/\bCli\b/CLI/g; s/\bApi\b/API/g')

echo "COMPONENT_NAME       : $COMPONENT_NAME"
echo "TARGET_RHOAI_VERSION : $TARGET_RHOAI_VERSION"
echo "REPOSITORY_NAME      : $REPOSITORY_NAME"
echo "CONTENT_STREAM_TAG   : $CONTENT_STREAM_TAG"
echo "RELEASE_CATEGORY     : $RELEASE_CATEGORY"
echo "DISPLAY_NAME         : $DISPLAY_NAME"
echo "SHORT_DESCRIPTION    : $SHORT_DESCRIPTION"
echo "LONG_DESCRIPTION     : $LONG_DESCRIPTION"
echo "PYXIS_URL            : $PYXIS_URL"

# ── Fast-path check: does delivery repo already exist? ───────────────────────

RHOAI_YAML_TMPFILE=$(mktemp)
HTTP_STATUS=$(curl -sk -w "%{http_code}" \
  -H "Authorization: Bearer $GITLAB_TOKEN" \
  "https://gitlab.cee.redhat.com/api/v4/projects/${PYXIS_PATH_ENCODED}/repository/files/products%2Frhoai%2Frhoai.yaml/raw?ref=main" \
  -o "$RHOAI_YAML_TMPFILE")

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "WARN in Step 5: Could not fetch rhoai.yaml via GitLab API (HTTP $HTTP_STATUS)."
  echo "  Ensure VPN is active. Continuing with clone."
  rm -f "$RHOAI_YAML_TMPFILE"
else
  if grep -qF "repository: ${REPOSITORY_NAME}" "$RHOAI_YAML_TMPFILE"; then
    rm -f "$RHOAI_YAML_TMPFILE"
    if [[ -n "$JIRA_URL" ]]; then
      uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
        --add-label "delivery-repo-exists" \
        --comment "Delivery repository '${REPOSITORY_NAME}' already exists in pyxis-repo-configs.

No changes needed. The repository is already present in products/rhoai/rhoai.yaml on the main branch."
    fi
    echo "Delivery repository '$REPOSITORY_NAME' already exists in products/rhoai/rhoai.yaml."
    echo "Jira updated (label: delivery-repo-exists). No MR needed."
    exit 0
  fi
  rm -f "$RHOAI_YAML_TMPFILE"
fi

# ── Set up GitLab playpen (clone) ────────────────────────────────────────────

cd "$WORKDIR"

PLAYPEN_ARGS=(
  --src-url "$PYXIS_URL"
  --dest-url "$PYXIS_URL"
  --src-branch main
  --sparse-files "products/rhoai/rhoai.yaml"
)
[[ -n "${JIRA_ID:-}" ]] && PLAYPEN_ARGS+=(--dest-branch "$JIRA_ID")

PLAYPEN_OUTPUT=$(GITLAB_SSL_VERIFY=false bash "$SCRIPTS_DIR/setup_gitlab_playpen.sh" \
  "${PLAYPEN_ARGS[@]}") || {
  echo "ERROR in Step 6 (Playpen setup): Clone or push failed. See details above." >&2
  echo "  Check GITLAB_TOKEN has 'write_repository' scope and push access to $PYXIS_PATH." >&2
  echo "  Ensure VPN is active and you can reach gitlab.cee.redhat.com." >&2
  exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)
echo "Clone dir  : $CLONE_DIR"
echo "Dest branch: $DEST_BRANCH"

# ── Add entry to products/rhoai/rhoai.yaml ──────────────────────────────────

RHOAI_YAML="$CLONE_DIR/products/rhoai/rhoai.yaml"
[[ -f "$RHOAI_YAML" ]] || {
  echo "ERROR in Step 7: products/rhoai/rhoai.yaml not found in $CLONE_DIR." >&2
  echo "  Verify PYXIS_URL points to the correct pyxis-repo-configs repository." >&2
  exit 1
}

RESULT=$(uv run --script "$SCRIPTS_DIR/append_delivery_repo_entry.py" \
  --yaml-file           "$RHOAI_YAML" \
  --repository-name     "$REPOSITORY_NAME" \
  --content-stream-tag  "$CONTENT_STREAM_TAG" \
  --release-category    "$RELEASE_CATEGORY" \
  --display-name        "$DISPLAY_NAME" \
  --short-description   "$SHORT_DESCRIPTION" \
  --long-description    "$LONG_DESCRIPTION")
if [[ "$RESULT" == "already-present" ]]; then
  echo "Entry for ${REPOSITORY_NAME} already present in rhoai.yaml -- skipping edit."
else
  echo "Entry for ${REPOSITORY_NAME} added to products/rhoai/rhoai.yaml."
fi

# ── Commit and push ─────────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files     "products/rhoai/rhoai.yaml" \
  --message   "Add ${REPOSITORY_NAME} delivery repository for ${COMPONENT_NAME}

Adds a new repository entry to products/rhoai/rhoai.yaml:
  repository: ${REPOSITORY_NAME}
  content_stream_tags: ['${CONTENT_STREAM_TAG}']

Related: ${JIRA_ID:-no-jira}" \
  --branch    "$DEST_BRANCH" || {
  echo "ERROR in Step 8 (Push): Could not push branch '$DEST_BRANCH'. See details above." >&2
  exit 1
}

# ── Raise MR (up to 3 attempts) ─────────────────────────────────────────────

MR_URL=""
for ATTEMPT in 1 2 3; do
  echo "Raising MR (attempt $ATTEMPT/3)..."
  set +e
  MR_URL=$(GITLAB_SSL_VERIFY=false uv run --script "$SCRIPTS_DIR/raise_gitlab_mr.py" \
    --src-url "$PYXIS_URL" \
    --src-branch "$DEST_BRANCH" \
    --dest-url "$PYXIS_URL" \
    --dest-branch main \
    --title "Add ${REPOSITORY_NAME} delivery repository for ${COMPONENT_NAME}" \
    --description "Adds a new delivery repository entry to \`products/rhoai/rhoai.yaml\`.

## Repository details

| Field | Value |
|-------|-------|
| \`repository\` | \`${REPOSITORY_NAME}\` |
| \`content_stream_tags\` | \`['${CONTENT_STREAM_TAG}']\` |
| \`component_name\` | \`${COMPONENT_NAME}\` |
| \`target_rhoai_version\` | \`${TARGET_RHOAI_VERSION}\` |

**File changed:** \`products/rhoai/rhoai.yaml\`
**Jira:** ${JIRA_URL:-(none)}")
  MR_RC=$?
  set -e

  if [[ $MR_RC -eq 0 && -n "$MR_URL" ]]; then
    break
  fi

  echo "MR creation failed (attempt $ATTEMPT/3)." >&2
  if [[ $ATTEMPT -eq 3 ]]; then
    echo "ERROR in Step 9 (Raise MR): Could not create MR after 3 attempts. See errors above. Aborting." >&2
    exit 1
  fi
  sleep 5
done

# ── Jira updates ─────────────────────────────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "delivery-repo-mr-raised" \
    --comment "[step:delivery_repo] GitLab MR raised to create RHOAI delivery repository '${REPOSITORY_NAME}'.

MR URL: $MR_URL

File changed: products/rhoai/rhoai.yaml
Repository: ${REPOSITORY_NAME}
Content stream tag: ${CONTENT_STREAM_TAG}

The delivery repository will be provisioned automatically once the MR is merged."
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo "Done."
echo ""
echo "  products/rhoai/rhoai.yaml  -- ${REPOSITORY_NAME} entry added"
echo "  content_stream_tags        : ['${CONTENT_STREAM_TAG}']"
echo "  GitLab MR                  : $MR_URL"
echo "  Jira                       : ${JIRA_ID:-(none)} -- label: delivery-repo-mr-raised"
echo ""
echo "The delivery repository will be provisioned once the MR is merged:"
echo "  https://quay.io/${REPOSITORY_NAME}"
