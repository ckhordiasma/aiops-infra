---
name: enable-renovate-on-rhoai-component-repo
description: Enables Renovate dependency updates for a new RHOAI component repo by adding it to the renovate config in rhoai-konflux-central and raising a GitHub PR targeting main.
allowed-tools: Bash
user-invocable: true
---

# Enable Renovate on RHOAI Component Repo

Registers a new RHOAI component repository in the Renovate configuration maintained in
`rhoai-konflux-central` (`config.yaml` on `main`) so that Renovate bot keeps its dependencies
up to date. Raises a PR and monitors it to completion.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/enable-renovate-on-rhoai-component-repo.md) for context.

## Usage

/enable-renovate-on-rhoai-component-repo [<jira-url>]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/enable-renovate-on-rhoai-component-repo.sh" --jira-url "$JIRA_URL"
```

The Jira URL is optional. If omitted, the script expects `component_onboarding_details.yaml` to already be present in the working directory.

If invoked with `--existing-pr-url <url>`, the script exits immediately (idempotency fast-path used by the orchestrator).
