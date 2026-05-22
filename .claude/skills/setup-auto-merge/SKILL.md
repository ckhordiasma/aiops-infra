---
name: setup-auto-merge
description: Configures auto-merge for a new component repo by adding entries to rhods-devops-infra's upstream-source-map.yaml and main-release-source-map.yaml, registering the repo in both auto-merge GitHub Actions workflows, and raising a GitHub PR targeting main. Part of the ODH/RHOAI component onboarding pipeline.
allowed-tools: Bash
user-invocable: true
---

# Setup Auto-Merge

Configures auto-merge for a new component repository by updating four files in the
`rhods-devops-infra` repo and raising a GitHub PR targeting `main`.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/setup-auto-merge.md) for context.

## Usage

/setup-auto-merge [<jira-url>]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/setup-auto-merge.sh" --jira-url "$JIRA_URL"
```

The Jira URL is optional. If omitted, the script expects `component_onboarding_details.yaml` to already be present in the working directory.

If invoked with `--existing-pr-url <url>`, the script exits immediately (idempotency fast-path used by the orchestrator).

The script modifies four files: `src/config/upstream-source-map.yaml`, `src/config/main-release-source-map.yaml`, `.github/workflows/upstream-auto-merge.yaml`, and `.github/workflows/main-release-auto-merge.yaml`.
