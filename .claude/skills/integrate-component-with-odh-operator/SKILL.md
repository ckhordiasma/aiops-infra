---
name: integrate-component-with-odh-operator
description: Updates the operator repository (opendatahub-io/opendatahub-operator for ODH, red-hat-data-services/rhods-operator for RHOAI) to include a new operator component in build/manifests-config.yaml and raises a GitHub PR. Exits cleanly (no-op) when is_operator=false. Automates Step 9 of the ODH/RHOAI component onboarding pipeline.
allowed-tools: Bash
user-invocable: true
---

# Integrate Component with ODH Operator

Adds a new operator component to the operator repository (`opendatahub-operator` for ODH,
`rhods-operator` for RHOAI) by updating `build/manifests-config.yaml` and raising a PR.
Exits cleanly if `is_operator=false`.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/integrate-component-with-odh-operator.md) for context.

## Usage

/integrate-component-with-odh-operator <jira-url>

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/integrate-component-with-odh-operator.sh" --jira-url "$JIRA_URL"
```

The Jira URL is required. The target operator repo is determined by `product_context` (ODH or RHOAI) and can be overridden via `ODH_OPERATOR_REPO_URL`.

If invoked with `--existing-pr-url <url>`, the script exits immediately (idempotency fast-path used by the orchestrator).

If `is_operator=false` in the YAML, the script exits with code 0 and labels the Jira ticket `operator-changes-not-needed`.
