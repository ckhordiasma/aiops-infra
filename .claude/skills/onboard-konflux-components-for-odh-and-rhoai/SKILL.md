---
name: onboard-konflux-components-for-odh-and-rhoai
description: Master orchestrator that coordinates all steps of the ODH/RHOAI component onboarding pipeline. Runs each step in sequence, tracks state for idempotent resume, and manages Jira labels throughout.
allowed-tools: Bash
user-invocable: true
---

# Onboard Konflux Components for ODH and RHOAI

Master orchestrator that coordinates all steps of the ODH/RHOAI component onboarding pipeline. Runs each step in sequence, tracks state for idempotent resume, and manages Jira labels throughout.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/onboard-konflux-components-for-odh-and-rhoai.md) for context.

## Usage

/onboard-konflux-components-for-odh-and-rhoai [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/onboard-konflux-components-for-odh-and-rhoai.sh" $ARGUMENTS
```

The Jira URL is required.

Required env vars: `GITHUB_USER`, `GITHUB_TOKEN`, `GITLAB_USER`, `GITLAB_TOKEN`, `JIRA_USER_EMAIL`, `JIRA_API_TOKEN`.

The orchestrator tracks pipeline state in `pipeline_state.json` for idempotent resume. Re-running picks up where it left off. Each step calls the corresponding individual script.
