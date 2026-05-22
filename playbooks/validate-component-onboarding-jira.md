# Validate Component Onboarding Jira

Pre-flight validation for ODH/RHOAI component onboarding tickets.

**Applies to:** ODH / RHOAI / Both
**Pipeline step:** Pre-requisite (Step 0)

## When to use

Before starting the onboarding automation for any component. Run this after creating or receiving a Jira ticket with an attached component_onboarding_details.yaml file to confirm all inputs are valid and complete.

## Prerequisites

**Tools:**
- `uv` Python runner
- `jq` for JSON parsing
- `curl` for fetching Dockerfiles

**Credentials:**
- `JIRA_USER_EMAIL` — Atlassian account email
- `JIRA_API_TOKEN` — Atlassian API token

**Optional:**
- `JIRA_SERVER` — Jira server URL (default: https://redhat.atlassian.net)

## What you'll be changing

**No repository changes.** This playbook only validates the Jira ticket and attached YAML file.

**Jira updates:**
- On success: adds label `validation-successful`, removes `validation-failed`, sets status to `In Progress`
- On failure: adds label `validation-failed`, removes `validation-successful`, posts a comment with error details

## Steps

### 1. Fetch Jira issue details

Download the Jira issue metadata to a local JSON file.

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -H "Content-Type: application/json" \
      "https://redhat.atlassian.net/rest/api/2/issue/RHOAIENG-1234" \
      > component_onboarding_details.json

Verify the issue exists and your credentials are valid. If the fetch fails, check credentials and the issue key.

### 2. Download the component_onboarding_details.yaml attachment

List attachments on the issue.

    jq -r '.fields.attachment[] | "\(.filename): \(.content)"' component_onboarding_details.json

Find the entry for `component_onboarding_details.yaml` and download it.

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -o component_onboarding_details.yaml \
      "https://redhat.atlassian.net/secure/attachment/12345/component_onboarding_details.yaml"

If the file is not attached, the validation fails. Attach the YAML to the Jira ticket first.

### 3. Validate YAML against the schema

Use the JSON Schema validator to check the YAML structure.

    uv run --script validate_yaml_schema.py \
      component_onboarding_details.yaml \
      /path/to/component_onboarding_details.schema.json

The schema file is located at `playbooks/assets/component_onboarding_details.schema.json` in this repository.

If validation fails, the script outputs field-level errors. Correct the YAML, re-upload it to Jira, and re-run validation.

### 4. Cross-validate repo_branch for RHOAI (RHOAI only)

For RHOAI components, verify that `inputs.repo_branch` matches the expected branch derived from `inputs.target_rhoai_version`.

Parse the YAML:

    PRODUCT_CONTEXT=$(grep -m1 'product_context:' component_onboarding_details.yaml | awk '{print $2}')
    REPO_BRANCH=$(grep -m1 'repo_branch:' component_onboarding_details.yaml | awk '{print $2}')
    TARGET_VERSION=$(grep -m1 'target_rhoai_version:' component_onboarding_details.yaml | awk '{print $2}')

If `PRODUCT_CONTEXT` is `RHOAI`, derive the expected branch:
- For `3.5` (no EA suffix): expected branch is `rhoai-3.5`
- For `3.5-ea-1` (EA suffix present): expected branch is `rhoai-3.5-ea.1`

Compare `REPO_BRANCH` to the expected value. If they don't match, update the YAML.

### 5. Check Dockerfile digest pinning (RHOAI only)

For RHOAI components, verify that all `FROM` instructions in the Dockerfile use `@sha256:` digests.

Construct the raw GitHub URL for the Dockerfile:

    REPO_URL=$(grep -m1 'repo_url:' component_onboarding_details.yaml | awk '{print $2}')
    REPO_BRANCH=$(grep -m1 'repo_branch:' component_onboarding_details.yaml | awk '{print $2}')
    CONTEXT_PATH=$(grep -m1 'context_path:' component_onboarding_details.yaml | awk '{print $2}')
    DOCKERFILE_PATH=$(grep -m1 'dockerfile_path:' component_onboarding_details.yaml | awk '{print $2}')

    RAW_BASE="${REPO_URL/github.com/raw.githubusercontent.com}"
    DOCKERFILE_URL="$RAW_BASE/$REPO_BRANCH/$CONTEXT_PATH/$DOCKERFILE_PATH"

Fetch the Dockerfile:

    curl -sf "$DOCKERFILE_URL" -o Dockerfile

Check each `FROM` line:

    grep '^FROM ' Dockerfile

Every base image must include `@sha256:` followed by a hexadecimal digest. If any `FROM` line uses only a tag (e.g., `FROM ubi9:latest`), it must be updated to pin the digest.

Example valid line:

    FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:abc123...

If violations are found, update the Dockerfile in the component repository, then re-run validation.

### 6. Update Jira on success

Add the label `validation-successful`, remove `validation-failed`, and set the issue status to `In Progress`. Post a comment confirming validation passed.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| JIRA_USER_EMAIL or JIRA_API_TOKEN not set | Export both variables. Create an API token at https://id.atlassian.com/manage-profile/security/api-tokens. |
| Jira fetch returns 401 Unauthorized | Check that the API token is valid and the email matches your Atlassian account. |
| Jira fetch returns 404 Not Found | Verify the issue key is correct and you have permission to view the issue. |
| Attachment not found | Attach component_onboarding_details.yaml to the Jira issue before running validation. |
| YAML schema validation fails | Review the error messages, correct the YAML fields, re-upload the file, and re-run. |
| repo_branch / target_rhoai_version mismatch | For RHOAI, repo_branch must match the target version. Update the YAML to align them. |
| Dockerfile not reachable (404) | Check repo_url, repo_branch, context_path, and dockerfile_path in the YAML. The Dockerfile may not exist on the specified branch yet. |
| FROM instructions missing @sha256 digest | Update the Dockerfile to pin all base images with SHA digests. |

## Automation

The script `scripts/validate-component-onboarding-jira.sh` automates this playbook end-to-end.

    ./scripts/validate-component-onboarding-jira.sh <jira-url>

Beyond the manual steps above, the script also:
- Automatically resolves the Jira issue ID from the URL
- Creates a working directory for artifacts
- Skips posting duplicate success comments if validation has already passed
- Provides detailed error messages for each validation step
- Updates Jira labels and status based on validation results

## Related playbooks

- [create-component-onboarding-jira](create-component-onboarding-jira.md) — create the Jira ticket and YAML
- [run-odh-konflux-onboarder-workflow](run-odh-konflux-onboarder-workflow.md) — run after validation succeeds
