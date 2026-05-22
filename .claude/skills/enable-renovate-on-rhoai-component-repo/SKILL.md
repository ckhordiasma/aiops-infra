---
name: enable-renovate-on-rhoai-component-repo
description: Enables Renovate dependency management on an RHOAI component repository by adding it to the konflux-central config.yaml and raising a GitHub pull request. Automates Step 9 of the RHOAI component onboarding pipeline.
allowed-tools: Bash
user-invocable: true
---

# Enable Renovate on RHOAI Component Repo

Enables Renovate dependency management on an RHOAI component repository by adding it to the konflux-central config.yaml and raising a GitHub pull request. Automates Step 9 of the RHOAI component onboarding pipeline.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/enable-renovate-on-rhoai-component-repo.md) for context.

## Usage

/enable-renovate-on-rhoai-component-repo [args]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/enable-renovate-on-rhoai-component-repo.sh" $ARGUMENTS
```

The Jira URL is optional. The script fetches the component YAML from the Jira ticket attachment if provided.

Required env vars: `GITHUB_USER`, `GITHUB_TOKEN`.

The `RHOAI_KONFLUX_CENTRAL_REPO_URL` env var can override the default repo URL.
