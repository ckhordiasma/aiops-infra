#!/usr/bin/env bash
# create-quay-repo.sh — Create a Quay repository via a GitOps MR to app-interface
#
# Usage:
#   ./scripts/create-quay-repo.sh <org>/<repo> [--jira-url <url>] [--visibility public|private]
#   ./scripts/create-quay-repo.sh quay.io/<org>/<repo> [--jira-url <url>] [--visibility public|private]
#
# Required env vars:
#   GITLAB_USER   — GitLab username
#   GITLAB_TOKEN  — GitLab personal access token (api + write_repository)
#
# Required when --jira-url is provided:
#   JIRA_USER_EMAIL, JIRA_API_TOKEN
#
# Optional:
#   APP_INTERFACE_REPO_URL — override default app-interface URL
#                            (default: https://gitlab.cee.redhat.com/service/app-interface)

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse inputs ──────────────────────────────────────────────────────────────

QUAY_REPO=""
JIRA_URL=""
JIRA_ID=""
VISIBILITY=""
EXISTING_MR_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jira-url)      JIRA_URL="$2"; shift 2 ;;
    --visibility)    VISIBILITY="$2"; shift 2 ;;
    --existing-mr-url) EXISTING_MR_URL="$2"; shift 2 ;;
    -*)              echo "ERROR: Unknown flag: $1" >&2; exit 1 ;;
    *)
      if [[ -z "$QUAY_REPO" ]]; then
        QUAY_REPO="$1"; shift
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

# ── Parse quay repo ──────────────────────────────────────────────────────────

# Strip quay.io/ prefix if present
QUAY_REPO="${QUAY_REPO#quay.io/}"

IFS='/' read -r ORG REPO <<< "$QUAY_REPO"
if [[ -z "${ORG:-}" || -z "${REPO:-}" ]]; then
  echo "ERROR: Invalid quay repo format. Expected quay.io/<org>/<repo> or <org>/<repo>." >&2
  exit 1
fi

# Default visibility
if [[ -z "$VISIBILITY" ]]; then
  if [[ "$ORG" == "rhoai" ]]; then
    VISIBILITY="private"
  else
    VISIBILITY="public"
  fi
fi

# Parse Jira ID
if [[ -n "$JIRA_URL" ]]; then
  JIRA_ID="${JIRA_URL##*/}"
fi

# Resolve app-interface URL
APP_INTERFACE_URL="${APP_INTERFACE_REPO_URL:-https://gitlab.cee.redhat.com/service/app-interface}"
echo "APP_INTERFACE_REPO_URL=${APP_INTERFACE_REPO_URL:-(not set, using default)}"
echo "APP_INTERFACE_URL resolved to: $APP_INTERFACE_URL"

echo "ORG        : $ORG"
echo "REPO       : $REPO"
echo "VISIBILITY : $VISIBILITY"
echo "JIRA_URL   : ${JIRA_URL:-(not provided)}"
echo "JIRA_ID    : ${JIRA_ID:-(not provided)}"

# ── Check prerequisites ──────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/check_prerequisites.sh" \
  --env "GITLAB_USER GITLAB_TOKEN" \
  --tools "uv skopeo"

if [[ -n "$JIRA_URL" ]]; then
  bash "$SCRIPTS_DIR/check_prerequisites.sh" --env "JIRA_USER_EMAIL JIRA_API_TOKEN"
fi

# ── Create working directory ─────────────────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  eval "$(bash "$SCRIPTS_DIR/init_workdir.sh" --jira-url "$JIRA_URL")"
else
  WORKDIR="$(pwd)/quay-${ORG}-${REPO}"
  mkdir -p "$WORKDIR"
fi
echo "Working directory: $WORKDIR"

# ── Check if Quay repo already exists ────────────────────────────────────────

set +e
bash "$SCRIPTS_DIR/check_quay_repo.sh" "quay.io/${ORG}/${REPO}"
CHECK_RC=$?
set -e

if [[ $CHECK_RC -eq 0 ]]; then
  # Repo exists
  if [[ -n "$JIRA_URL" ]]; then
    uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
      --add-label "quay-repo-created" \
      --comment "Quay repo quay.io/${ORG}/${REPO} already exists. No action needed."
  fi
  echo "Quay repo quay.io/${ORG}/${REPO} already exists. Nothing to do."
  exit 0
elif [[ $CHECK_RC -eq 2 ]]; then
  echo "ERROR: Tool error while checking Quay repo. See details above." >&2
  exit 1
fi

# ── Fork app-interface ───────────────────────────────────────────────────────

FORK_URL=$(uv run --script "$SCRIPTS_DIR/setup_gitlab_fork.py" \
  --gitlab-repo-url "$APP_INTERFACE_URL") || {
  echo "ERROR in Step 5 (Fork app-interface): Could not fork the repository. See details above. Aborting." >&2
  exit 1
}
echo "Fork URL: $FORK_URL"

# ── Determine YAML file path ────────────────────────────────────────────────

case "$ORG" in
  opendatahub) YAML_FILE="data/services/rhoai/quay/opendatahub.yml" ;;
  rhoai)       YAML_FILE="data/services/rhoai/quay/rhoai.yml" ;;
  modh)        YAML_FILE="data/services/rhoai/quay/modh.yml" ;;
  *)
    echo "ERROR: Unknown Quay org '$ORG'. Cannot determine YAML file path." >&2
    echo "  Expected one of: opendatahub, rhoai, modh" >&2
    exit 1
    ;;
esac

DEST_BRANCH="${JIRA_ID:-}"

# ── Set up playpen (full clone) ─────────────────────────────────────────────

cd "$WORKDIR"

PLAYPEN_ARGS=(
  --src-url "$APP_INTERFACE_URL"
  --dest-url "$FORK_URL"
  --src-branch master
)
[[ -n "$DEST_BRANCH" ]] && PLAYPEN_ARGS+=(--dest-branch "$DEST_BRANCH")

PLAYPEN_OUTPUT=$(timeout 2700 bash "$SCRIPTS_DIR/setup_gitlab_playpen.sh" "${PLAYPEN_ARGS[@]}") || {
  RC=$?
  if [[ $RC -eq 124 ]]; then
    echo "ERROR in Step 7 (Playpen setup): Clone timed out after 45 minutes. Check VPN connectivity and retry. Aborting." >&2
  else
    echo "ERROR in Step 7 (Playpen setup): Clone or push failed. See details above. Aborting." >&2
  fi
  exit 1
}

CLONE_DIR=$(echo "$PLAYPEN_OUTPUT" | head -1)
DEST_BRANCH=$(echo "$PLAYPEN_OUTPUT" | tail -1)
echo "Clone dir  : $CLONE_DIR"
echo "Dest branch: $DEST_BRANCH"

# ── Modify YAML file ────────────────────────────────────────────────────────

# Resolve description
SHORT_DESCRIPTION="${ORG} ${REPO} container image"

if grep -q "^  name: ${REPO}$" "$CLONE_DIR/$YAML_FILE" 2>/dev/null || \
   grep -q "^- name: ${REPO}$" "$CLONE_DIR/$YAML_FILE" 2>/dev/null; then
  echo "Entry for '${REPO}' already exists in the YAML -- skipping append."
else
  if [[ "$VISIBILITY" == "public" ]]; then
    VIS_FLAG="--public"
  else
    VIS_FLAG="--no-public"
  fi
  uv run --script "$SCRIPTS_DIR/edit_yaml.py" append-items-array \
    "$CLONE_DIR/$YAML_FILE" \
    --name "$REPO" \
    --description "'${SHORT_DESCRIPTION}'" \
    $VIS_FLAG || {
    echo "ERROR in Step 8 (Modify YAML): Could not append entry to $YAML_FILE. See details above. Aborting." >&2
    exit 1
  }
fi

# ── Commit and push ─────────────────────────────────────────────────────────

DEST_REMOTE="dest"
[[ "$FORK_URL" == "$APP_INTERFACE_URL" ]] && DEST_REMOTE="origin"

bash "$SCRIPTS_DIR/git_commit_push.sh" \
  --clone-dir "$CLONE_DIR" \
  --files     "$YAML_FILE" \
  --message   "Add ${REPO} to quay ${ORG} config" \
  --branch    "$DEST_BRANCH" \
  --remote    "$DEST_REMOTE" || {
  echo "ERROR in Step 9 (Commit/Push): Could not commit or push changes. See details above. Aborting." >&2
  exit 1
}

# ── Raise MR (up to 3 attempts) ─────────────────────────────────────────────

MR_URL=""
for ATTEMPT in 1 2 3; do
  echo "Raising MR (attempt $ATTEMPT/3)..."
  set +e
  MR_URL=$(uv run --script "$SCRIPTS_DIR/raise_gitlab_mr.py" \
    --src-url "$FORK_URL" \
    --src-branch "$DEST_BRANCH" \
    --dest-url "$APP_INTERFACE_URL" \
    --dest-branch master \
    --title "Add ${REPO} quay repository for ${ORG}" \
    --description "Add quay.io/${ORG}/${REPO} to app-interface GitOps config.

Visibility: ${VISIBILITY}
Jira: ${JIRA_URL:-N/A}")
  MR_RC=$?
  set -e

  if [[ $MR_RC -eq 0 && -n "$MR_URL" ]]; then
    break
  fi

  echo "MR creation failed (attempt $ATTEMPT/3)." >&2
  if [[ $ATTEMPT -eq 3 ]]; then
    echo "ERROR in Step 9 (Raise MR): Could not create merge request after 3 attempts. See errors above. Aborting." >&2
    exit 1
  fi
  sleep 5
done

# ── Jira updates ─────────────────────────────────────────────────────────────

if [[ -n "$JIRA_URL" ]]; then
  uv run --script "$SCRIPTS_DIR/update_jira_issue.py" "$JIRA_URL" \
    --add-label "quay-mr-raised" \
    --comment "GitLab MR raised to create quay.io/${ORG}/${REPO}.

MR URL: $MR_URL

The Quay repo will be created automatically once this MR is merged."
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo "MR raised: $MR_URL"
