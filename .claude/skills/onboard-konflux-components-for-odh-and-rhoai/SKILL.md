---
name: onboard-konflux-components-for-odh-and-rhoai
description: Master orchestrator skill for the full ODH/RHOAI component onboarding pipeline. Idempotent — run any number of times for the same Jira. Each run syncs PR/MR state, executes newly-unblocked steps, and posts a summary of what changed. Transitions Jira through In Progress → Review → Resolved automatically.
allowed-tools: Bash
user-invocable: true
---

# Onboard Konflux Components for ODH and RHOAI

Master orchestrator for the full ODH/RHOAI component onboarding pipeline. Coordinates all sub-steps (Quay, delivery repo, konflux-release-data, konflux-central, operator, bundle, product listing, auto-merge, Renovate), tracks PR/MR status, and advances the pipeline as dependencies are satisfied. Idempotent -- safe to re-run any number of times.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/onboard-konflux-components-for-odh-and-rhoai.md) for context.

## Usage

/onboard-konflux-components-for-odh-and-rhoai <jira-url>

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/onboard-konflux-components-for-odh-and-rhoai.sh" "$JIRA_URL"
```

The script requires a Jira URL as its sole argument. It will:
- Validate the Jira ticket and attached YAML
- Determine which pipeline steps apply (ODH vs RHOAI)
- Check current state from Jira labels and PR/MR API status
- Execute all newly-unblocked steps in dependency order
- Post progress summaries and transition Jira status automatically

VPN must be active before running (required for GitLab-based steps). The script is fully idempotent -- re-run after PRs/MRs merge to advance the pipeline.
