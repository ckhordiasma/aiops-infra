---
name: add-component-to-rhoai-konflux-central
description: Adds a Tekton PipelineRun YAML to the rhoai-konflux-central GitHub repository for a new RHOAI component, then raises a GitHub PR targeting the version-specific branch.
allowed-tools: Bash
user-invocable: true
---

# Add Component to RHOAI-Konflux-Central

Creates a Tekton PipelineRun resource for a new RHOAI component by generating a push
PipelineRun YAML under `pipelineruns/<repo_name>/.tekton/` and raising a pull request
to the version-specific branch of `rhoai-konflux-central`.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/add-component-to-rhoai-konflux-central.md) for context.

## Usage

/add-component-to-rhoai-konflux-central [<jira-url>]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/add-component-to-rhoai-konflux-central.sh" --jira-url "$JIRA_URL"
```

The Jira URL is optional. If omitted, the script expects `component_onboarding_details.yaml` to already be present in the working directory.

If invoked with `--existing-pr-url <url>`, the script exits immediately (idempotency fast-path used by the orchestrator).

The PR targets a version-specific branch (e.g., `rhoai-3.5-ea.1`), NOT `main`. The branch is derived from `target_rhoai_version` in the onboarding YAML.
