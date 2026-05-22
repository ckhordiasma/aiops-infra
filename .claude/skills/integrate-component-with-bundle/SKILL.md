---
name: integrate-component-with-bundle
description: Integrates a component with the ODH or RHOAI build config bundle by adding Dockerfile entries and raising a GitHub pull request.
allowed-tools: Bash
user-invocable: true
---

# Integrate Component with Bundle

Integrates a component with the ODH or RHOAI build config bundle by adding Dockerfile entries and raising a GitHub pull request.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/integrate-component-with-bundle.md) for context.

## Usage

/integrate-component-with-bundle [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/integrate-component-with-bundle.sh" $ARGUMENTS
```

The Jira URL is required.

Required env vars: `GITHUB_USER`, `GITHUB_TOKEN`, `JIRA_USER_EMAIL`, `JIRA_API_TOKEN`.

The target repo depends on product context: ODH → `ODH-Build-Config`, RHOAI → `RHOAI-Build-Config`.
