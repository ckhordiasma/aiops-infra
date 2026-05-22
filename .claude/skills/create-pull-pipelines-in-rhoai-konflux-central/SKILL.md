---
name: create-pull-pipelines-in-rhoai-konflux-central
description: Creates Tekton pull-request PipelineRun YAMLs for a new RHOAI component in the rhoai-konflux-central GitHub repository and raises a pull request targeting the version-specific branch.
allowed-tools: Bash
user-invocable: true
---

# Create Pull Pipelines in RHOAI-Konflux-Central

Creates Tekton pull-request PipelineRun YAMLs for a new RHOAI component in the rhoai-konflux-central GitHub repository and raises a pull request targeting the version-specific branch.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/create-pull-pipelines-in-rhoai-konflux-central.md) for context.

## Usage

/create-pull-pipelines-in-rhoai-konflux-central [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/create-pull-pipelines-in-rhoai-konflux-central.sh" $ARGUMENTS
```

The Jira URL is optional. When provided, the script tracks progress via Jira labels.

Required env vars: `GITHUB_USER`, `GITHUB_TOKEN`.

The `RHOAI_KONFLUX_CENTRAL_REPO_URL` env var can override the default repo URL. The PR targets a version-specific branch, NOT `main`.
