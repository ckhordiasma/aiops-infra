#!/usr/bin/env bash
# create-quay-repo.sh — Creates a Quay repository via GitOps MR to app-interface
#
# Usage:
#   ./scripts/create-quay-repo.sh <quay-repo> [--jira-url <url>] [--visibility public|private] [--existing-mr-url <url>]
#   ./scripts/create-quay-repo.sh quay.io/<org>/<repo>
#   ./scripts/create-quay-repo.sh <org>/<repo> --jira-url https://redhat.atlassian.net/browse/RHOAIENG-1234
#
# Required env vars:
#   GITLAB_USER, GITLAB_TOKEN
#
# Required when --jira-url is provided:
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional env vars:
#   APP_INTERFACE_REPO_URL (default: https://gitlab.cee.redhat.com/service/app-interface)
#   JIRA_SERVER (default: https://redhat.atlassian.net)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

QUAY_REPO=""
JIRA_URL=""
VISIBILITY=""
EXISTING_MR_URL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --jira-url)
      JIRA_URL="$2"
      shift 2
      ;;
    --visibility)
      VISIBILITY="$2"
      shift 2
      ;;
    --existing-mr-url)
      EXISTING_MR_URL="$2"
      shift 2
      ;;
    *)
      if [[ -z "$QUAY_REPO" ]]; then
        QUAY_REPO="$1"
      else
        echo "ERROR: Unexpected argument '$1'"
        exit 1
      fi
      shift
      ;;
  esac
done

# Idempotency fast-path
if [[ -n "$EXISTING_MR_URL" ]]; then
  echo "MR already raised: $EXISTING_MR_URL"
  exit 0
fi

# Parse quay repo
QUAY_REPO="${QUAY_REPO#quay.io/}"
IFS='/' read -r QUAY_ORG QUAY_REPO_NAME <<< "$QUAY_REPO"
if [[ -z "$QUAY_ORG" || -z "$QUAY_REPO_NAME" ]]; then
  echo "ERROR: Invalid quay repo format. Expected 'quay.io/<org>/<repo>' or '<org>/<repo>'."
  exit 1
fi

# Determine visibility
if [[ -z "$VISIBILITY" ]]; then
  if [[ "$QUAY_ORG" == "rhoai" ]]; then
    VISIBILITY="private"
  else
    VISIBILITY="public"
  fi
fi

# Parse Jira URL
JIRA_ID=""
if [[ -n "$JIRA_URL" ]]; then
  JIRA_ID="${JIRA_URL##*/}"
fi

# Resolve APP_INTERFACE_URL
APP_INTERFACE_URL="${APP_INTERFACE_REPO_URL:-https://gitlab.cee.redhat.com/service/app-interface}"
echo "APP_INTERFACE_REPO_URL=${APP_INTERFACE_REPO_URL:-(not set, using default)}"
echo "APP_INTERFACE_URL resolved to: $APP_INTERFACE_URL"

echo "QUAY_ORG  : $QUAY_ORG"
echo "QUAY_REPO : $QUAY_REPO_NAME"
echo "VISIBILITY: $VISIBILITY"
echo "JIRA_URL  : ${JIRA_URL:-(none)}"
echo "JIRA_ID   : ${JIRA_ID:-(none)}"

# ── Check prerequisites ───────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "GITLAB_USER GITLAB_TOKEN" --tools "uv skopeo"

if [[ -n "$JIRA_URL" ]]; then
  bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "JIRA_USER_EMAIL JIRA_API_TOKEN"
fi

# ── Create working directory ──────────────────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "$JIRA_URL")"
else
  WORKDIR="$(pwd)/quay-${QUAY_ORG}-${QUAY_REPO_NAME}"
  mkdir -p "$WORKDIR"
fi
echo "Working directory: $WORKDIR"

# ── Check if Quay repo already exists ─────────────────────────────────────────

if bash "$SCRIPTS_DIR/check_quay_repo.sh" "quay.io/${QUAY_ORG}/${QUAY_REPO_NAME}"; then
  echo "Quay repo quay.io/${QUAY_ORG}/${QUAY_REPO_NAME} already exists."
  if [[ -n "$JIRA_URL" ]]; then
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --add-label "quay-repo-created" \
      --comment "Quay repo quay.io/${QUAY_ORG}/${QUAY_REPO_NAME} already exists. No action needed."
  fi
  echo "Nothing to do."
  exit 0
fi

# ── Fork app-interface ────────────────────────────────────────────────────────

FORK_URL=$(uv run --script "$SCRIPTS_DIR/setup_gitlab_fork.py" --gitlab-repo-url "$APP_INTERFACE_URL")
echo "Fork URL: $FORK_URL"

# ── Determine YAML file path and branch name ──────────────────────────────────

case "$QUAY_ORG" in
  opendatahub)
    YAML_FILE="data/services/rhoai/quay/opendatahub.yml"
    ;;
  rhoai)
    YAML_FILE="data/services/rhoai/quay/rhoai.yml"
    ;;
  modh)
    YAML_FILE="data/services/rhoai/quay/modh.yml"
    ;;
  *)
    echo "ERROR: Unknown org '$QUAY_ORG'. Expected opendatahub, rhoai, or modh."
    exit 1
    ;;
esac

DEST_BRANCH="${JIRA_ID:-quay-${QUAY_ORG}-${QUAY_REPO_NAME}}"

# ── Set up playpen (full clone) ───────────────────────────────────────────────

cd "$WORKDIR"

PLAYPEN_OUTPUT=$(timeout 2700 bash "$SCRIPTS_DIR/setup_gitlab_playpen.sh" \
  --src-url "$APP_INTERFACE_URL" \
  --dest-url "$FORK_URL" \
  --src-branch master \
  --dest-branch "$DEST_BRANCH") || {
  EXIT_CODE=$?
  if [[ $EXIT_CODE -eq 124 ]]; then
    echo "ERROR: Clone timed out after 45 minutes. Check VPN connectivity and retry."
  else
    echo "ERROR: Playpen setup failed. See details above."
  fi
  exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)

echo "Clone directory: $CLONE_DIR"
echo "Branch: $DEST_BRANCH"

# ── Modify YAML file ──────────────────────────────────────────────────────────

if grep -q "^  name: ${QUAY_REPO_NAME}$" "$CLONE_DIR/$YAML_FILE" 2>/dev/null || \
   grep -q "^- name: ${QUAY_REPO_NAME}$" "$CLONE_DIR/$YAML_FILE" 2>/dev/null; then
  echo "Entry for '${QUAY_REPO_NAME}' already exists in $YAML_FILE — skipping append."
else
  if [[ "$VISIBILITY" == "public" ]]; then
    VIS_FLAG="--public"
  else
    VIS_FLAG="--no-public"
  fi
  uv run --script "$SCRIPTS_DIR/edit_yaml.py" append-items-array \
    "$CLONE_DIR/$YAML_FILE" \
    --name "$QUAY_REPO_NAME" \
    --description "${QUAY_ORG} ${QUAY_REPO_NAME} container image" \
    $VIS_FLAG
fi

# ── Commit and push ───────────────────────────────────────────────────────────

DEST_REMOTE="dest"
[[ "$FORK_URL" == "$APP_INTERFACE_URL" ]] && DEST_REMOTE="origin"

bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files "$YAML_FILE" \
  --message "Add ${QUAY_REPO_NAME} to quay ${QUAY_ORG} config" \
  --branch "$DEST_BRANCH" \
  --remote "$DEST_REMOTE"

# ── Raise MR (up to 3 attempts) ───────────────────────────────────────────────

MR_URL=""
for attempt in 1 2 3; do
  MR_URL=$(uv run --script "$SCRIPTS_DIR/raise_gitlab_mr.py" \
    --src-url "$FORK_URL" \
    --src-branch "$DEST_BRANCH" \
    --dest-url "$APP_INTERFACE_URL" \
    --dest-branch master \
    --title "Add ${QUAY_REPO_NAME} quay repository for ${QUAY_ORG}" \
    --description "Add quay.io/${QUAY_ORG}/${QUAY_REPO_NAME} to app-interface GitOps config.

Visibility: ${VISIBILITY}
Jira: ${JIRA_URL:-N/A}") && break || {
    echo "WARN: MR creation attempt $attempt failed."
    [[ $attempt -eq 3 ]] && {
      echo "ERROR: Could not create MR after 3 attempts."
      exit 1
    }
  }
done

echo "MR raised: $MR_URL"

# ── Jira updates ──────────────────────────────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "quay-mr-raised" \
    --comment "GitLab MR raised to create quay.io/${QUAY_ORG}/${QUAY_REPO_NAME}.

MR URL: $MR_URL

The Quay repo will be created automatically once this MR is merged."
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo "Done."
echo "MR: $MR_URL"
