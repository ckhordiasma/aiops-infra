---
name: create-rhoai-delivery-repo
description: Creates an RHOAI delivery repository by raising a GitLab MR to pyxis-repo-configs. Reads component details from the Jira attachment, checks if the delivery repo already exists, and if not, adds the repository entry to products/rhoai/rhoai.yaml and raises and monitors a GitLab MR. VPN required.
allowed-tools: Bash
user-invocable: true
---

# Create RHOAI Delivery Repo

Creates a new RHOAI delivery repository in the Red Hat container registry by raising
a merge request to the `pyxis-repo-configs` GitLab repository.
See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/create-rhoai-delivery-repo.md) for context.

## Usage

/create-rhoai-delivery-repo [<jira-url>]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/create-rhoai-delivery-repo.sh" \
  --jira-url "$JIRA_URL"
```

The Jira ticket must have `component_onboarding_details.yaml` attached. The script
downloads it, parses component details, and derives the delivery repo name and content
stream tags automatically. VPN must be active for GitLab access.
