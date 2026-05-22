---
name: run-odh-konflux-onboarder-workflow
description: Triggers the odh-konflux-onboarder GitHub Actions workflow in odh-konflux-central, extracts the resulting Tekton PR URL from workflow logs, and records it for tracking by the parent orchestrator. Automates Step 5 of the ODH component onboarding pipeline.
allowed-tools: Bash
user-invocable: true
---

# Run ODH Konflux Onboarder Workflow

Triggers the `odh-konflux-onboarder` GitHub Actions workflow, monitors its execution,
and extracts the resulting Tekton PR URL.
See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/run-odh-konflux-onboarder-workflow.md) for context.

## Usage

/run-odh-konflux-onboarder-workflow [<jira-url>]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/run-odh-konflux-onboarder-workflow.sh" "$JIRA_URL"
```

The Jira URL is optional. Without it, the script looks for a `component_onboarding_details.yaml`
in the working directory. If neither is available, prompt the user for the required inputs
(component name, branch, build type, version) and ask them to provide the YAML or Jira URL.

This workflow is for ODH components only. RHOAI components use a different onboarding process.
