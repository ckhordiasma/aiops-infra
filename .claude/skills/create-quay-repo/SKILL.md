---
name: create-quay-repo
description: Creates a Quay repository via a GitOps MR to app-interface. Handles fork setup, sparse YAML editing, MR creation, and optional Jira tracking. Automates Step 2 of the ODH component onboarding pipeline.
allowed-tools: Bash
user-invocable: true
---

# Create Quay Repo

Creates a new Quay repository for an ODH component by raising a merge request to the
`app-interface` GitLab repository (GitOps-driven).
See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/create-quay-repo.md) for context.

## Usage

/create-quay-repo quay.io/<org>/<repo> [--jira-url <url>] [--visibility public|private]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/create-quay-repo.sh" <org>/<repo> \
  --jira-url "$JIRA_URL" --visibility "$VISIBILITY"
```

The script accepts `quay.io/<org>/<repo>` or `<org>/<repo>` format. Visibility defaults to
`private` for the `rhoai` org and `public` otherwise. VPN must be active for GitLab access.
