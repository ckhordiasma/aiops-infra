---
name: add-component-to-rhoai-konflux-central
description: Adds a Tekton PipelineRun YAML to the rhoai-konflux-central GitHub repository for a new RHOAI component, then raises a GitHub PR targeting the version-specific branch.
allowed-tools: Bash
user-invocable: true
---

# Add Component to RHOAI-Konflux-Central

Adds a Tekton PipelineRun YAML to the rhoai-konflux-central GitHub repository for a new RHOAI component, then raises a GitHub PR targeting the version-specific branch.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/add-component-to-rhoai-konflux-central.md) for context.

## Usage

/add-component-to-rhoai-konflux-central [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/add-component-to-rhoai-konflux-central.sh" $ARGUMENTS
```

The Jira URL is optional. When provided, the script tracks progress via Jira labels.

Required env vars: `GITHUB_USER`, `GITHUB_TOKEN`.

The `RHOAI_KONFLUX_CENTRAL_REPO_URL` env var can override the default repo URL. The PR targets a version-specific branch (e.g. `rhoai-3.5`), NOT `main`.
