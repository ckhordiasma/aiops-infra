---
name: setup-auto-merge
description: Configures auto-merge for a component's Konflux CI pull requests by adding the component to the auto-merge configuration in rhods-devops-infra and raising a GitHub pull request. Automates Step 8 of the RHOAI pipeline.
allowed-tools: Bash
user-invocable: true
---

# Setup Auto-Merge

Configures auto-merge for a component's Konflux CI pull requests by adding the component to the auto-merge configuration in rhods-devops-infra and raising a GitHub pull request. Automates Step 8 of the RHOAI pipeline.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/setup-auto-merge.md) for context.

## Usage

/setup-auto-merge [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/setup-auto-merge.sh" $ARGUMENTS
```

The Jira URL is optional. When provided, the script tracks progress via Jira labels.

Required env vars: `GITHUB_USER`, `GITHUB_TOKEN`.

Targets the `red-hat-data-services/rhods-devops-infra` repository.
