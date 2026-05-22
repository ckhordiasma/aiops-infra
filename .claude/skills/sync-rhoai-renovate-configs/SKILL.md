---
name: sync-rhoai-renovate-configs
description: Triggers the sync-renovate-configs GitHub Actions workflow in rhoai-konflux-central to push renovate config updates to all registered component repos. Monitors the run and updates Jira on completion.
allowed-tools: Bash
user-invocable: true
---

# Sync RHOAI Renovate Configs

Triggers the `sync-renovate-configs` workflow in `konflux-central` to propagate the central Renovate configuration to all registered component repositories. Monitors the run to completion and optionally updates a Jira issue with progress labels and comments.

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

The Jira URL is optional. If provided, the script tracks progress via Jira labels (`renovate-sync-triggered`, `renovate-sync-done`, `renovate-sync-failed`).

The `RHOAI_KONFLUX_CENTRAL_REPO_URL` env var can override the default repo URL (`https://github.com/red-hat-data-services/konflux-central.git`).

`GITHUB_TOKEN` needs `repo` + `actions:write` scope (or `workflow` scope on classic PATs).
