---
name: create-component-onboarding-jira
description: Interactively collects ODH/RHOAI component onboarding parameters from the user, generates a validated component_onboarding_details.yaml, and creates or updates a Jira ticket with the YAML attached. When no Jira URL is provided, automatically creates a new ticket by cloning the product-specific onboarding template. Use this before running other onboarding skills.
allowed-tools: Bash
user-invocable: true
---

# Create Component Onboarding Jira

Interactively collects ODH/RHOAI component onboarding parameters from the user, generates a validated component_onboarding_details.yaml, and creates or updates a Jira ticket with the YAML attached. When no Jira URL is provided, automatically creates a new ticket by cloning the product-specific onboarding template. Use this before running other onboarding skills.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/create-component-onboarding-jira.md) for context.

## Usage

/create-component-onboarding-jira [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/create-component-onboarding-jira.sh" $ARGUMENTS
```

The Jira URL is optional. Without it, a new Jira ticket is created from a template.

Required env vars: `JIRA_USER_EMAIL`, `JIRA_API_TOKEN`.

This skill is interactive — it collects component details from the user through a series of questions, then generates the YAML and creates/updates the Jira ticket. When running the script directly, pass all fields as flags instead.
