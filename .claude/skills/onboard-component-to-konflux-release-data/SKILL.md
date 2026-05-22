---
name: onboard-component-to-konflux-release-data
description: Onboards a new ODH/RHOAI component onto the Konflux CI platform by raising a merge request to the konflux-release-data GitLab repo. Automates Step 3 of the ODH component onboarding pipeline.
allowed-tools: Bash
user-invocable: true
---

# Onboard Component to Konflux Release Data

Creates Konflux Component resources for a new ODH/RHOAI component by appending YAML
documents to the appropriate tenant config file in `konflux-release-data` and raising an MR.
See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/onboard-component-to-konflux-release-data.md) for context.

## Usage

/onboard-component-to-konflux-release-data <jira-url>

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/onboard-component-to-konflux-release-data.sh" \
  --jira-url "$JIRA_URL"
```

A Jira URL is always required. The script downloads the component YAML from Jira,
determines product context (ODH vs RHOAI) automatically, handles the different file
modifications for each product, and runs manifest build/verify steps. VPN must be active
for both GitLab and the Konflux OpenShift cluster.

For RHOAI components, `target_rhoai_version` in the onboarding YAML is mandatory and
must be in `x.y` or `x.y-ea-n` format. The script modifies up to four files (ProjectDevelopmentStream,
stage RPA, prod RPA, and automation resources).
