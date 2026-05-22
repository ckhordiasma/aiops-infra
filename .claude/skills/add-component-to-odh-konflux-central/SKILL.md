---
name: update-component-using-odh-konflux-central
description: Onboards a new ODH/RHOAI component onto the Konflux CI platform by adding PipelineRun YAMLs and updating the onboarder workflow in the odh-konflux-central GitHub repository and raising a pull request. Automates Step 4 of the ODH component onboarding pipeline.
allowed-tools: Bash
user-invocable: true
---

# Add Component to ODH-Konflux-Central

Creates Tekton PipelineRun resources for a new ODH/RHOAI component by generating push and
pull-request PipelineRun YAMLs from templates, adding the component to the onboarder workflow,
and raising a pull request to `odh-konflux-central`.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/add-component-to-odh-konflux-central.md) for context.

## Usage

/add-component-to-odh-konflux-central <jira-url>

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/add-component-to-odh-konflux-central.sh" --jira-url "$JIRA_URL"
```

The Jira URL is required -- the script downloads `component_onboarding_details.yaml` from the ticket.

If invoked with `--existing-pr-url <url>`, the script exits immediately (idempotency fast-path used by the orchestrator).

Key inputs from the YAML: `component_name`, `repo_url`, `repo_branch`, `context_path`, `dockerfile_path`, `build_type`, and `product_context` (ODH or RHOAI, which determines namespace and application names).
