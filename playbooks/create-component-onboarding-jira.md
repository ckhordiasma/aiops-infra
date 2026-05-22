# Create Component Onboarding Jira

Interactively collects ODH/RHOAI component onboarding parameters, generates a validated component_onboarding_details.yaml, and creates or updates a Jira ticket with the YAML attached.

**Applies to:** ODH / RHOAI / Both
**Pipeline step:** Pre-requisite (Step 0)

## When to use

Before starting any component onboarding automation. Use this skill to:
- Create a new Jira onboarding ticket from a template (if no Jira URL provided)
- Attach a validated component_onboarding_details.yaml to an existing ticket
- Update an existing ticket's YAML attachment with new parameters

## Prerequisites

**Tools:**
- `uv` Python runner
- `jq` for JSON parsing

**Credentials:**
- `JIRA_USER_EMAIL` — Atlassian account email
- `JIRA_API_TOKEN` — Atlassian API token

**Optional:**
- `JIRA_SERVER` — Jira server URL (default: https://redhat.atlassian.net)

## What you'll be changing

**No repository changes.** This playbook only creates or updates Jira tickets.

**Jira operations:**
- If no Jira URL provided: creates a new Jira issue by cloning the product-specific onboarding template
- Attaches the generated `component_onboarding_details.yaml` file
- Posts an initial comment indicating the ticket is ready for automation

**Template issue keys:**
- ODH: `RHOAIENG-<template-id>` (consult team for current template)
- RHOAI: `RHOAIENG-<template-id>` (consult team for current template)

## Steps

### 1. Collect component details interactively

Gather the following information from the user (or from existing YAML if updating):

**Universal fields (both ODH and RHOAI):**
- `product_context` — "ODH" or "RHOAI"
- `component_name` — component identifier (e.g., "notebook-controller")
- `repo_url` — full GitHub HTTPS URL (e.g., "https://github.com/opendatahub-io/notebook-controller")
- `repo_branch` — branch to build from (e.g., "main" for ODH, "rhoai-3.5" for RHOAI)
- `context_path` — build context directory (default: ".")
- `dockerfile_path` — Dockerfile location relative to context (default: "Dockerfile")
- `quay_repo` — Quay registry path (e.g., "quay.io/opendatahub/notebook-controller")
- `is_operator` — boolean: is this an operator component?

**RHOAI-specific fields (when product_context=RHOAI):**
- `target_rhoai_version` — version string (e.g., "3.5", "3.5-ea-1")
- `delivery_repo_path` — Pyxis delivery repo path (derived from component_name)
- `delivery_repo_visibility` — "private" (default for RHOAI)

**ODH-specific considerations:**
- `quay_repo` visibility is typically "public" for ODH

### 2. Generate the YAML file

Create a `component_onboarding_details.yaml` file with the collected parameters:

```yaml
product_context: RHOAI
inputs:
  component_name: notebook-controller
  repo_url: https://github.com/opendatahub-io/notebook-controller
  repo_branch: rhoai-3.5
  context_path: .
  dockerfile_path: Dockerfile
  quay_repo: quay.io/rhoai/notebook-controller
  is_operator: true
  target_rhoai_version: "3.5"
  delivery_repo_path: rhoai/notebook-controller-container
  delivery_repo_visibility: private
```

For ODH, omit the RHOAI-specific fields and adjust defaults.

### 3. Validate YAML against the schema

Use the JSON Schema validator to check the YAML structure.

    uv run --script validate_yaml_schema.py \
      component_onboarding_details.yaml \
      /path/to/component_onboarding_details.schema.json

The schema file is located at `.claude/skills/validate-component-onboarding-jira/assets/component_onboarding_details.schema.json` in this repository.

If validation fails, review the error messages, correct the YAML, and re-validate.

### 4. Create or identify the Jira ticket

**Option A: Create a new ticket (no Jira URL provided)**

Clone the product-specific onboarding template:

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{
        "cloneIssueDetails": {
          "project": {"key": "RHOAIENG"},
          "summary": "Onboard <component-name> to Konflux"
        }
      }' \
      "https://redhat.atlassian.net/rest/api/2/issue/<TEMPLATE-ID>/clone"

Extract the new issue key from the response:

    JIRA_ID=$(echo "$RESPONSE" | jq -r '.key')
    JIRA_URL="https://redhat.atlassian.net/browse/$JIRA_ID"

**Option B: Use an existing ticket**

Extract the Jira ID from the provided URL:

    JIRA_URL="https://redhat.atlassian.net/browse/RHOAIENG-1234"
    JIRA_ID="${JIRA_URL##*/}"

### 5. Upload the YAML attachment

Attach the `component_onboarding_details.yaml` file to the Jira ticket.

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X POST \
      -H "X-Atlassian-Token: no-check" \
      -F "file=@component_onboarding_details.yaml" \
      "https://redhat.atlassian.net/rest/api/2/issue/$JIRA_ID/attachments"

If the file already exists as an attachment, delete the old version first:

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X DELETE \
      "https://redhat.atlassian.net/rest/api/2/attachment/<ATTACHMENT-ID>"

### 6. Post a comment to the Jira ticket

Add a comment indicating the ticket is ready for automation:

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"body":"Component onboarding YAML has been attached. Ready for automation."}' \
      "https://redhat.atlassian.net/rest/api/2/issue/$JIRA_ID/comment"

### 7. Display the Jira URL

Output the final Jira URL for the user:

    echo "Jira ticket: $JIRA_URL"

## Troubleshooting

| Problem | Solution |
|---------|----------|
| JIRA_USER_EMAIL or JIRA_API_TOKEN not set | Export both variables. Create an API token at https://id.atlassian.com/manage-profile/security/api-tokens. |
| Jira API returns 401 Unauthorized | Check that the API token is valid and the email matches your Atlassian account. |
| Template issue not found | Verify the template ID with the team. Update the script to use the correct template. |
| YAML validation fails | Review the error messages, correct the YAML fields, and re-run validation. |
| Attachment upload fails | Check that the YAML file exists and the Jira ticket ID is correct. |
| repo_branch / target_rhoai_version mismatch | For RHOAI, repo_branch must match the target version (e.g., "rhoai-3.5" for version "3.5"). |

## Automation

The script `scripts/create-component-onboarding-jira.sh` automates this playbook end-to-end.

    ./scripts/create-component-onboarding-jira.sh [--jira-url <url>]

Beyond the manual steps above, the script also:
- Provides an interactive questionnaire for collecting component details
- Automatically derives RHOAI-specific fields from inputs
- Validates the YAML before uploading
- Creates a new Jira ticket from the template if no URL is provided
- Handles re-uploading attachments (deletes old version first)
- Outputs the final Jira URL for use in subsequent automation

## Related playbooks

- [validate-component-onboarding-jira](validate-component-onboarding-jira.md) — run after creating the ticket
- [onboard-konflux-components-for-odh-and-rhoai](onboard-konflux-components-for-odh-and-rhoai.md) — orchestrator
