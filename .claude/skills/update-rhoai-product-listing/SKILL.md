---
name: update-rhoai-product-listing
description: Updates the RHOAI product listing in pyxis-repo-configs by appending the new component's registry path to product-listings/rhoai/rhoai.yaml and raising a GitLab MR. VPN required.
allowed-tools: Bash
user-invocable: true
---

# Update RHOAI Product Listing

Adds the new component's registry path to the RHOAI product listing in `pyxis-repo-configs`.
See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/update-rhoai-product-listing.md) for context.

## Usage

/update-rhoai-product-listing [<jira-url>]

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/update-rhoai-product-listing.sh" \
  --jira-url "$JIRA_URL"
```

The Jira ticket must have `component_onboarding_details.yaml` attached. The script
derives the registry path (`registry.access.redhat.com/rhoai/<component_name>-rhel9`)
from the component name automatically. VPN must be active for GitLab access.
