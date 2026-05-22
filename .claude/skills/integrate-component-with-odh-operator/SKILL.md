---
name: integrate-component-with-odh-operator
description: Integrates an operator component with the ODH or RHOAI operator repository by adding manifest copy entries to the Makefile and raising a GitHub pull request. Only applies to components marked as operators.
allowed-tools: Bash
user-invocable: true
---

# Integrate Component with ODH Operator

Integrates an operator component with the ODH or RHOAI operator repository by adding manifest copy entries to the Makefile and raising a GitHub pull request. Only applies to components marked as operators.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/integrate-component-with-odh-operator.md) for context.

## Usage

/integrate-component-with-odh-operator [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/integrate-component-with-odh-operator.sh" $ARGUMENTS
```

The Jira URL is required. Only runs for components where `is_operator: true` in the onboarding YAML.

Required env vars: `GITHUB_USER`, `GITHUB_TOKEN`, `JIRA_USER_EMAIL`, `JIRA_API_TOKEN`.

The target repo depends on product context: ODH → `opendatahub-operator`, RHOAI → `rhods-operator`.
