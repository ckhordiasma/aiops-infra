---
name: add-rhoai-dockerfile-labels
description: Checks a component Dockerfile for mandatory RHOAI labels (name, com.redhat.component, summary, description, maintainer, io.k8s.display-name, io.k8s.description). If any are missing or incorrect, clones the component repo, adds the labels, and raises a GitHub PR. Updates the Jira ticket throughout.
allowed-tools: Bash
user-invocable: true
---

# Add RHOAI Dockerfile Labels

Checks a component Dockerfile for mandatory RHOAI labels (name, com.redhat.component, summary, description, maintainer, io.k8s.display-name, io.k8s.description). If any are missing or incorrect, clones the component repo, adds the labels, and raises a GitHub PR. Updates the Jira ticket throughout.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/add-rhoai-dockerfile-labels.md) for context.

## Usage

/add-rhoai-dockerfile-labels [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/add-rhoai-dockerfile-labels.sh" $ARGUMENTS
```

The Jira URL is optional. When provided, the script tracks progress via Jira labels.

Required env vars: `GITHUB_USER`, `GITHUB_TOKEN`.

If all 7 mandatory labels are already correct, the script exits cleanly without creating a PR.
