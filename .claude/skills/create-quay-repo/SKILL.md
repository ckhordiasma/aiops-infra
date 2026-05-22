---
name: create-quay-repo
description: Creates a Quay repository via a GitOps MR to app-interface. Handles fork setup, sparse YAML editing, MR creation, and optional Jira tracking. Automates Step 2 of the ODH component onboarding pipeline.
allowed-tools: Bash
user-invocable: true
---

# Create Quay Repo

Creates a new Quay repository for an ODH component by raising a merge request to the app-interface GitLab repository (GitOps-driven). The Quay repo is automatically created when the MR is merged.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/create-quay-repo.md) for context.

## Usage

/create-quay-repo <quay-repo> [--jira-url <url>] [--visibility public|private]

Examples:
- /create-quay-repo quay.io/opendatahub/my-new-component
- /create-quay-repo rhoai/rhoai-data-science-pipelines --jira-url https://redhat.atlassian.net/browse/RHOAIENG-1234

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/create-quay-repo.sh" $QUAY_REPO ${JIRA_URL:+--jira-url "$JIRA_URL"} ${VISIBILITY:+--visibility "$VISIBILITY"}
```

**Input notes:**
- QUAY_REPO: Accept formats `quay.io/<org>/<repo>` or `<org>/<repo>`
- Visibility defaults to `public` for ODH orgs (opendatahub, modh), `private` for RHOAI (rhoai)
- If --existing-mr-url is passed, the script exits immediately (idempotency fast-path)

**Edge cases:**
- If the Quay repo already exists, the script exits 0 and updates Jira if applicable
- Clone can take 30+ minutes for app-interface (large repo with full history)
- VPN must be active to access gitlab.cee.redhat.com
