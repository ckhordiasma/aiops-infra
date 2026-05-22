# Run ODH Konflux Onboarder Workflow

Trigger the odh-konflux-onboarder GitHub Actions workflow to generate Tekton configuration for a component.

**Applies to:** ODH
**Pipeline step:** 4 (ODH)

## When to use

After the component has been added to odh-konflux-central (Step 4) and the PR has been merged. The component must appear in the workflow's component options before this step can succeed.

## Prerequisites

**Tools:**
- `gh` CLI installed and authenticated
- `uv` Python runner
- `jq` for JSON parsing

**Credentials:**
- `GITHUB_USER` — your GitHub username
- `GITHUB_TOKEN` — GitHub PAT with `repo` and `actions:write` scope
- `JIRA_USER_EMAIL` — Atlassian account email (only if updating Jira)
- `JIRA_API_TOKEN` — Atlassian API token (only if updating Jira)

**Optional:**
- `ODH_KONFLUX_CENTRAL_REPO_URL` — override default odh-konflux-central repo

## What you'll be changing

**Repo:** `opendatahub-io/odh-konflux-central` (or fork specified in `ODH_KONFLUX_CENTRAL_REPO_URL`)

**Action:** Trigger the `.github/workflows/odh-konflux-onboarder.yml` workflow via GitHub Actions dispatch API. The workflow creates a pull request adding Tekton PipelineRun definitions for the component.

**Artifacts created:**
- A new PR in odh-konflux-central with Tekton YAML files
- Jira ticket updated with PR URL and label `tekton-pr-raised`

## Steps

### 1. Verify the component was added to odh-konflux-central

Check that the Step 4 PR adding the component to the workflow's options has been merged.

    gh pr list --repo opendatahub-io/odh-konflux-central --search "in:title <component-name>" --state merged

If no merged PR is found, stop and complete Step 4 first.

### 2. Trigger the odh-konflux-onboarder workflow

Dispatch the workflow with required inputs using the GitHub CLI.

    gh workflow run odh-konflux-onboarder.yml \
      --repo opendatahub-io/odh-konflux-central \
      --ref main \
      --field component=<component-name> \
      --field pr_target_branch=<branch> \
      --field build_type=<CI|Release>

For Release builds, add the version field:

    gh workflow run odh-konflux-onboarder.yml \
      --repo opendatahub-io/odh-konflux-central \
      --ref main \
      --field component=<component-name> \
      --field pr_target_branch=<branch> \
      --field build_type=Release \
      --field version=<version-string>

### 3. Monitor the workflow run

Find the run ID of the triggered workflow.

    gh run list --repo opendatahub-io/odh-konflux-central --workflow odh-konflux-onboarder.yml --limit 1

Watch the run until it completes (success or failure).

    gh run watch <run-id> --repo opendatahub-io/odh-konflux-central

If the run fails, view the logs to diagnose the issue.

    gh run view <run-id> --repo opendatahub-io/odh-konflux-central --log

### 4. Extract the Tekton PR URL from logs

Once the workflow succeeds, extract the pull request URL from the "Create pull request" step logs.

    gh run view <run-id> --repo opendatahub-io/odh-konflux-central --log | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+'

Copy the PR URL for the next step.

### 5. Update Jira with the PR URL

Add the label `tekton-pr-raised` to the Jira ticket and post a comment with the PR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Workflow dispatch fails with 422 (invalid inputs) | The component is not yet in the workflow's options list. Verify Step 4 PR is merged and the component appears in `.github/workflows/odh-konflux-onboarder.yml`. |
| GitHub API returns 403 Forbidden | `GITHUB_TOKEN` needs `actions:write` scope. Regenerate the token with the correct permissions. |
| Workflow run times out after 30 minutes | Check the run URL manually. The workflow may still be completing. Re-run monitoring or check for existing PRs. |
| Cannot find "Create pull request" step in logs | Search for alternative step names like "create-pull-request", "Create PR", or "pull request". Extract the PR URL manually from the workflow run page. |
| PR URL not found in logs | Open the GitHub Actions run URL in a browser and locate the PR link in the step output. |

## Automation

The script `scripts/run-odh-konflux-onboarder-workflow.sh` automates this playbook end-to-end.

    ./scripts/run-odh-konflux-onboarder-workflow.sh --component <name> --pr-target-branch <branch> --build-type <CI|Release> [--version <ver>] [--jira-url <url>]

Beyond the manual steps above, the script also:
- Parses component details from a Jira-attached YAML file
- Validates inputs and checks prerequisites automatically
- Polls the workflow run with timeout and retry logic
- Automatically extracts the Tekton PR URL from step logs
- Updates Jira with workflow status, PR URL, and appropriate labels
- Handles idempotency by detecting existing PRs from previous runs

## Related playbooks

- [add-component-to-odh-konflux-central](add-component-to-odh-konflux-central.md) — prerequisite (Step 4)
- [validate-component-onboarding-jira](validate-component-onboarding-jira.md) — pre-flight validation
