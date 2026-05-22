---
name: create-rhoai-delivery-repo
description: Creates an RHOAI delivery repository by raising a GitLab MR to pyxis-repo-configs. Reads component details from the Jira attachment, checks if the delivery repo already exists, and if not, adds the repository entry to products/rhoai/rhoai.yaml and raises and monitors a GitLab MR. VPN required.
allowed-tools: Bash
user-invocable: true
---

# Create RHOAI Delivery Repo

Creates a new RHOAI delivery repository in the Red Hat container registry. The repository is provisioned automatically when a GitLab MR is merged into pyxis-repo-configs — a GitOps repo maintained by the Release Engineering team. This skill handles the full lifecycle.

See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/create-rhoai-delivery-repo.md) for context.

## Usage

/create-rhoai-delivery-repo [<jira-url>]

Examples:
- /create-rhoai-delivery-repo https://redhat.atlassian.net/browse/RHOAIENG-1234
- /create-rhoai-delivery-repo

## Implementation

Help the user accomplish this task by either:

1. Walking them through the playbook steps interactively, or
2. Collecting the required inputs and running the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/create-rhoai-delivery-repo.sh" ${JIRA_URL:+"$JIRA_URL"}
```

**Input notes:**
- JIRA_URL is optional but recommended; if omitted, component_onboarding_details.yaml must exist in the working directory
- If --existing-mr-url is passed, the script exits immediately (idempotency fast-path)

**Edge cases:**
- Requires component_onboarding_details.yaml attachment on Jira (created by /create-component-onboarding-jira)
- If delivery repo entry already exists in products/rhoai/rhoai.yaml, script exits 0 and updates Jira
- VPN must be active to access gitlab.cee.redhat.com
- Derives repository name, content stream tag, and display name from target_rhoai_version field
