---
name: validate-component-onboarding-jira
description: Pre-flight validation tool for ODH component onboarding. Given a Jira issue URL, fetches issue details, downloads the component_onboarding_details.yaml attachment, and validates it against the JSON Schema. Use before invoking the full onboarding automation to confirm a ticket is correctly set up.
allowed-tools: Bash
user-invocable: true
---

# Validate Component Onboarding Jira

Pre-flight validation for ODH/RHOAI component onboarding Jira tickets.
See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/validate-component-onboarding-jira.md) for context.

## Usage

/validate-component-onboarding-jira <jira-url-or-key>

The user may provide a full URL or just a ticket key (e.g. `RHOAIENG-1234`).

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the Jira URL and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/validate-component-onboarding-jira.sh" "$JIRA_URL"
```

The script accepts a full Jira URL or just a ticket key. It handles schema validation,
RHOAI branch cross-validation, Dockerfile digest checks, and Jira label/status updates
automatically. No repository changes are made.
