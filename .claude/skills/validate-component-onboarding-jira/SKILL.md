---
name: validate-component-onboarding-jira
description: Validates a component onboarding Jira ticket by checking the attached YAML against the schema and verifying that prerequisite pipeline steps have been completed. Run this before starting the onboarding pipeline.
allowed-tools: Bash
user-invocable: true
---

# Validate Component Onboarding Jira

Validates a component onboarding Jira ticket by checking the attached YAML against the schema and verifying that prerequisite pipeline steps have been completed. Run this before starting the onboarding pipeline.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/validate-component-onboarding-jira.md) for context.

## Usage

/validate-component-onboarding-jira [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/validate-component-onboarding-jira.sh" $ARGUMENTS
```

The Jira URL is required. The script downloads and validates the YAML attachment.

Required env vars: `JIRA_USER_EMAIL`, `JIRA_API_TOKEN`.

The schema file is at `playbooks/assets/component_onboarding_details.schema.json`.
