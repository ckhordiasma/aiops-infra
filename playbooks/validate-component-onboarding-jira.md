# Validate Component Onboarding Jira

Pre-flight validation for an ODH or RHOAI component onboarding Jira ticket. Fetches the issue details, downloads the `component_onboarding_details.yaml` attachment, and validates it against the JSON Schema.

**Applies to:** Both
**Pipeline step:** Pre-flight (run before any onboarding automation)

## When to use

Run this before invoking the full onboarding automation to confirm a ticket is correctly set up. The Jira ticket must already exist and have a `component_onboarding_details.yaml` file attached.

## Prerequisites

- Jira credentials: `JIRA_USER_EMAIL` and `JIRA_API_TOKEN` environment variables set
- `uv` Python runner installed
- The Jira ticket must have a `component_onboarding_details.yaml` attachment

## What you'll be changing

No repository files are modified. This is a read-only validation step that checks the Jira ticket and its YAML attachment, then updates labels on the Jira issue to reflect the validation result (`validation-successful` or `validation-failed`).

## Steps

### 1. Verify credentials and prerequisites

Ensure `JIRA_USER_EMAIL` and `JIRA_API_TOKEN` are set:

    echo $JIRA_USER_EMAIL
    echo $JIRA_API_TOKEN

If not set:

    export JIRA_USER_EMAIL='you@example.com'
    export JIRA_API_TOKEN='your-api-token'

Create an API token at https://id.atlassian.com/manage-profile/security/api-tokens if needed.

### 2. Fetch Jira issue details

Open the Jira ticket in your browser and verify the issue exists and you have access. The ticket key is the last segment of the URL (e.g., `RHOAIENG-1234` from `https://redhat.atlassian.net/browse/RHOAIENG-1234`).

### 3. Download the YAML attachment

Download the `component_onboarding_details.yaml` file from the Jira ticket's attachments section. Save it locally for inspection.

### 4. Validate the YAML against the schema

The YAML must conform to the schema at `playbooks/assets/component_onboarding_details.schema.json`. Check that all required fields are present:

**Common required fields (both ODH and RHOAI):**
- `product_context` (ODH or RHOAI)
- `component_name` (must start with `odh-`)
- `repo_url` (full HTTPS GitHub URL)
- `repo_branch`
- `context_path`
- `dockerfile_path`

**ODH-specific:**
- `build_type` (CI or Release)

**RHOAI-specific:**
- `target_rhoai_version` (canonical form, e.g. `3.4` or `3.4-ea-2`)
- `architectures` (list: x86_64, arm64, ppc64le, s390x)
- `release_category` (Generally Available, Tech Preview, or Beta)

### 5. Cross-validate repo_branch for RHOAI

For RHOAI components, verify that `repo_branch` matches `target_rhoai_version`:
- Version `3.5` requires branch `rhoai-3.5`
- Version `3.5-ea-1` requires branch `rhoai-3.5-ea.1`

### 6. Check Dockerfile digest pinning (RHOAI only)

For RHOAI components, verify that every `FROM` instruction in the Dockerfile pins its base image with an `@sha256:` digest. Fetch the Dockerfile from the raw GitHub URL:

    curl -sf "https://raw.githubusercontent.com/<org>/<repo>/<branch>/<context>/<dockerfile>"

Inspect each `FROM` line and confirm it contains `@sha256:`.

### 7. Update Jira with the validation result

On success, add the label `validation-successful`, remove `validation-failed`, and move the ticket to "In Progress" status. Post a comment confirming all checks passed.

On failure at any step, add the label `validation-failed`, remove `validation-successful`, and post a comment describing the specific failure and how to fix it.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `JIRA_USER_EMAIL` not set | `export JIRA_USER_EMAIL='you@example.com'` |
| `JIRA_API_TOKEN` not set | Create token at https://id.atlassian.com/manage-profile/security/api-tokens |
| Issue not found / no access | Check the ticket key and your Jira permissions |
| Attachment not found | Attach `component_onboarding_details.yaml` to the Jira issue |
| YAML fails schema validation | Fix the listed field errors in the YAML and re-upload |
| `repo_branch` / `target_rhoai_version` mismatch | Correct `repo_branch` in the YAML to match the version |
| Dockerfile not reachable | Check repo_url, repo_branch, context_path, and dockerfile_path in the YAML |
| FROM instructions missing `@sha256` digest | Pin all base images in the Dockerfile with SHA digests |

## Automation

The script `scripts/validate-component-onboarding-jira.sh` automates this playbook end-to-end.

    ./scripts/validate-component-onboarding-jira.sh <jira-url>

Beyond the manual steps above, the script also:
- Fetches and saves Jira issue details as JSON for downstream use
- Validates the YAML against the JSON Schema programmatically
- Automatically derives the expected RHOAI branch from the target version
- Checks the Dockerfile via raw GitHub URL for digest pinning violations
- Skips the success comment if `validation-successful` label is already present (idempotent)
- Updates Jira labels and status transitions automatically throughout

## Related playbooks

- [create-component-onboarding-jira](create-component-onboarding-jira.md) (prerequisite -- creates the ticket and YAML)
- [onboard-konflux-components-for-odh-and-rhoai](onboard-konflux-components-for-odh-and-rhoai.md) (downstream -- full pipeline)
