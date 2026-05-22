---
name: add-rhoai-dockerfile-labels
description: Checks a component Dockerfile for mandatory RHOAI labels (name, com.redhat.component, summary, description, maintainer, io.k8s.display-name, io.k8s.description). If any are missing or incorrect, clones the component repo, adds the labels, and raises a GitHub PR. Updates the Jira ticket throughout.
allowed-tools: Bash
user-invocable: true
---

# Add RHOAI Dockerfile Labels

Ensures a component Dockerfile contains all mandatory RHOAI OCI labels. If labels are
missing or incorrect, clones the repo, adds them, and raises a PR. If all labels are
already correct, exits cleanly with a Jira update.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/add-rhoai-dockerfile-labels.md) for context.

## Usage

/add-rhoai-dockerfile-labels [<jira-url>]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/add-rhoai-dockerfile-labels.sh" --jira-url "$JIRA_URL"
```

The Jira URL is optional. If omitted, the script expects `component_onboarding_details.yaml` to already be present in the working directory.

The seven mandatory labels are: `name`, `com.redhat.component`, `summary`, `description`, `maintainer`, `io.k8s.display-name`, `io.k8s.description`.
