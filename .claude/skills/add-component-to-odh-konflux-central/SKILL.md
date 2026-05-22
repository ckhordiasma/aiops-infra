---
name: update-component-using-odh-konflux-central
description: Onboards a new ODH/RHOAI component onto the Konflux CI platform by adding PipelineRun YAMLs and updating the onboarder workflow in the odh-konflux-central GitHub repository and raising a pull request. Automates Step 4 of the ODH component onboarding pipeline.
allowed-tools: Bash
user-invocable: true
---

# Add Component to ODH-Konflux-Central

Onboards a new ODH/RHOAI component onto the Konflux CI platform by adding PipelineRun YAMLs and updating the onboarder workflow in the odh-konflux-central GitHub repository and raising a pull request. Automates Step 4 of the ODH component onboarding pipeline.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/add-component-to-odh-konflux-central.md) for context.

## Usage

/update-component-using-odh-konflux-central [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/add-component-to-odh-konflux-central.sh" $ARGUMENTS
```

The Jira URL is required.

Required env vars: `GITHUB_USER`, `GITHUB_TOKEN`, `JIRA_USER_EMAIL`, `JIRA_API_TOKEN`.

The `ODH_KONFLUX_CENTRAL_REPO_URL` env var can override the default repo URL. This is resolved once and used for all Git operations — never hardcode the upstream URL.
