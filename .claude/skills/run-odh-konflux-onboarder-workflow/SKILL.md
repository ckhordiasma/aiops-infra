---
name: run-odh-konflux-onboarder-workflow
description: Triggers the ODH Konflux onboarder GitHub Actions workflow to generate Tekton resources for a component, monitors the run, and creates a PR from the results. Automates Step 4 of the ODH pipeline.
allowed-tools: Bash
user-invocable: true
---

# Run ODH Konflux Onboarder Workflow

Triggers the ODH Konflux onboarder GitHub Actions workflow to generate Tekton resources for a component, monitors the run, and creates a PR from the results. Automates Step 4 of the ODH pipeline.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/run-odh-konflux-onboarder-workflow.md) for context.

## Usage

/run-odh-konflux-onboarder-workflow [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/run-odh-konflux-onboarder-workflow.sh" $ARGUMENTS
```

The Jira URL is required.

Required env vars: `GITHUB_USER`, `GITHUB_TOKEN`, `JIRA_USER_EMAIL`, `JIRA_API_TOKEN`.

The `ODH_KONFLUX_CENTRAL_REPO_URL` env var can override the default repo URL.

`GITHUB_TOKEN` needs `repo` + `actions:write` scope.
