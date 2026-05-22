---
name: integrate-component-with-bundle
description: Updates the build-config repository (ODH-Build-Config for ODH, RHOAI-Build-Config for RHOAI) with a new component's relatedImages entry (bundle/bundle-patch.yaml) and optionally config/build-config.yaml (RHOAI only), then raises a GitHub PR. Automates Step 8 of the ODH/RHOAI component onboarding pipeline.
allowed-tools: Bash
user-invocable: true
---

# Integrate Component with Bundle

Updates the build-config repository (`ODH-Build-Config` for ODH, `RHOAI-Build-Config` for RHOAI)
with a new component's `relatedImages` entry in `bundle/bundle-patch.yaml` and optionally
`config/build-config.yaml` (RHOAI only), then raises a GitHub PR.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/integrate-component-with-bundle.md) for context.

## Usage

/integrate-component-with-bundle <jira-url>

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/integrate-component-with-bundle.sh" --jira-url "$JIRA_URL"
```

The Jira URL is required. The target build-config repo is determined by `product_context` (ODH or RHOAI) and can be overridden via `BUILD_CONFIG_REPO_URL`.

If invoked with `--existing-pr-url <url>`, the script exits immediately (idempotency fast-path used by the orchestrator).

For RHOAI, the script also updates `config/build-config.yaml` (repo_mappings) and `bundle/Dockerfile` (ARG and LABEL entries).
