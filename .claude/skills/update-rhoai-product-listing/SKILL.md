---
name: update-rhoai-product-listing
description: Updates the RHOAI product listing in pyxis-repo-configs by appending the new component's registry path to product-listings/rhoai/rhoai.yaml and raising a GitLab MR. VPN required.
allowed-tools: Bash
user-invocable: true
---

# Update RHOAI Product Listing

Adds the new component's registry path to the RHOAI product listing in pyxis-repo-configs. The entry is a single line in the repositories array of product-listings/rhoai/rhoai.yaml. This skill handles the full lifecycle.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/update-rhoai-product-listing.md) for context.

## Usage

/update-rhoai-product-listing [<jira-url>]

Examples:
- /update-rhoai-product-listing https://redhat.atlassian.net/browse/RHOAIENG-1234
- /update-rhoai-product-listing

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/update-rhoai-product-listing.sh" ${JIRA_URL:+"$JIRA_URL"}
```

**Input notes:**
- JIRA_URL is optional but recommended; if omitted, component_onboarding_details.yaml must exist in the working directory
- If --existing-mr-url is passed, the script exits immediately (idempotency fast-path)

**Edge cases:**
- Requires component_onboarding_details.yaml attachment on Jira (created by /create-component-onboarding-jira)
- If product listing entry already exists in product-listings/rhoai/rhoai.yaml, script exits 0 and updates Jira
- VPN must be active to access gitlab.cee.redhat.com
- Registry path follows pattern: registry.access.redhat.com/rhoai/<component-name>-rhel9
