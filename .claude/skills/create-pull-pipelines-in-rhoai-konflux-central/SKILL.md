---
name: create-pull-pipelines-in-rhoai-konflux-central
description: Adds a pull-request Tekton PipelineRun YAML to the rhoai-konflux-central GitHub repository for a new RHOAI component, then raises a GitHub PR targeting the main branch.
allowed-tools: Bash
user-invocable: true
---

# Create Pull Pipelines in RHOAI-Konflux-Central

Creates a Tekton PipelineRun resource for pull-request builds of a new RHOAI component by
generating a pull-request PipelineRun YAML under `pipelineruns/<repo_name>/.tekton/` and
raising a pull request to the `main` branch of `rhoai-konflux-central`.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/create-pull-pipelines-in-rhoai-konflux-central.md) for context.

## Usage

/create-pull-pipelines-in-rhoai-konflux-central [<jira-url>]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/create-pull-pipelines-in-rhoai-konflux-central.sh" --jira-url "$JIRA_URL"
```

The Jira URL is optional. If omitted, the script expects `component_onboarding_details.yaml` to already be present in the working directory.

If invoked with `--existing-pr-url <url>`, the script exits immediately (idempotency fast-path used by the orchestrator).

Unlike the push PipelineRun (which targets a version-specific branch), this PR targets `main`.
