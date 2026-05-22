---
name: sync-rhoai-renovate-configs
description: Triggers the sync-renovate-configs GitHub Actions workflow in rhoai-konflux-central to push renovate config updates to all registered component repos. Monitors the run and updates Jira on completion.
allowed-tools: Bash
user-invocable: true
---

# Sync RHOAI Renovate Configs

Triggers the `sync-renovate-configs.yml` GitHub Actions workflow in `rhoai-konflux-central` to
propagate the central Renovate configuration to all registered component repositories. Monitors
the run to completion and optionally updates a Jira issue.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/sync-rhoai-renovate-configs.md) for context.

## Usage

/sync-rhoai-renovate-configs [<jira-url>]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/sync-rhoai-renovate-configs.sh" --jira-url "$JIRA_URL"
```

The Jira URL is optional. The `GITHUB_TOKEN` must have `repo` + `actions:write` scope (or `workflow` scope on classic PATs).

The script triggers the workflow, monitors it for up to 30 minutes (polling every 60 seconds), retries once on failure, and updates Jira with the outcome.
