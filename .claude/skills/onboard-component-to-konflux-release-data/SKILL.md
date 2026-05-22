---
name: onboard-component-to-konflux-release-data
description: Onboards a component to the Konflux release pipeline by adding entries to the konflux-release-data GitLab repository and raising a merge request. Automates Step 2 (ODH) or Step 3 (RHOAI) of the component onboarding pipeline.
allowed-tools: Bash
user-invocable: true
---

# Onboard Component to Konflux Release Data

Onboards a component to the Konflux release pipeline by adding entries to the konflux-release-data GitLab repository and raising a merge request. Automates Step 2 (ODH) or Step 3 (RHOAI) of the component onboarding pipeline.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/onboard-component-to-konflux-release-data.md) for context.

## Usage

/onboard-component-to-konflux-release-data [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/onboard-component-to-konflux-release-data.sh" $ARGUMENTS
```

The Jira URL is required. The script fetches the component YAML from the Jira ticket attachment.

Required env vars: `GITLAB_USER`, `GITLAB_TOKEN`, `JIRA_USER_EMAIL`, `JIRA_API_TOKEN`.

The `KONFLUX_RELEASE_DATA_REPO_URL` env var can override the default GitLab repo URL.
