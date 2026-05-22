# Run ODH Konflux Onboarder Workflow

Triggers the `odh-konflux-onboarder` GitHub Actions workflow in the `odh-konflux-central` repository, waits for it to complete, and extracts the resulting Tekton PR URL from the workflow logs.

**Applies to:** ODH
**Pipeline step:** 4 (ODH)

## When to use

Run this after the `add-component-to-odh-konflux-central` step (Step 4) has completed and its PR has been merged. The component must already appear in the onboarder workflow's `components:` options list before dispatch will succeed.

## Prerequisites

- GitHub CLI (`gh`) installed and authenticated
- `GITHUB_TOKEN` with `repo` and `actions:write` scopes
- Jira credentials (`JIRA_USER_EMAIL`, `JIRA_API_TOKEN`) if tracking via Jira
- The component must be listed in `.github/workflows/odh-konflux-onboarder.yml` in odh-konflux-central

## What you'll be changing

No repository files are modified directly. This step triggers a GitHub Actions workflow in `opendatahub-io/odh-konflux-central` (or a fork), which creates a pull request containing Tekton PipelineRun YAML for the component.

## Steps

### 1. Gather the workflow inputs

You need four values from the onboarding YAML or from your knowledge of the component:

| Input | Description | Example |
|-------|-------------|---------|
| `component` | GitHub repo name of the component | `opendatahub-operator` |
| `pr_target_branch` | Branch to build against | `main` |
| `build_type` | `CI` or `Release` | `CI` |
| `version` | Version string (Release builds only) | `2.21.0` |

### 2. Check for existing Tekton PRs (idempotency)

Before triggering a new run, check whether a previous run already created a PR. Search the Jira comments or GitHub for an open or merged PR in odh-konflux-central that matches your component.

    gh pr list --repo opendatahub-io/odh-konflux-central --search "<component-name>" --state all

If a matching PR exists and is open or merged, you can skip triggering a new workflow and go directly to monitoring that PR.

### 3. Trigger the workflow

Dispatch the onboarder workflow via the GitHub CLI:

    gh workflow run odh-konflux-onboarder.yml \
      --repo opendatahub-io/odh-konflux-central \
      --ref main \
      -f component=<component-name> \
      -f pr_target_branch=<branch> \
      -f build_type=<CI|Release> \
      -f version=<version>          # only for Release builds

Note the `version` field should be omitted for CI builds.

### 4. Find the triggered run

After dispatching, locate the workflow run:

    gh run list --repo opendatahub-io/odh-konflux-central \
      --workflow odh-konflux-onboarder.yml --limit 5

Note the run ID from the output.

### 5. Monitor the workflow run

Watch the workflow run until it completes (allow up to 30 minutes):

    gh run watch <run-id> --repo opendatahub-io/odh-konflux-central

If the run fails, view the logs for diagnosis:

    gh run view <run-id> --repo opendatahub-io/odh-konflux-central --log

Common failure causes:
- The component is not yet in the workflow's options list (Step 4 PR not merged)
- Branch or build configuration issues in the component repo

If the first run fails, you may re-trigger once with the same inputs.

### 6. Extract the Tekton PR URL from the workflow logs

Once the workflow succeeds, find the PR it created:

    gh run view <run-id> --repo opendatahub-io/odh-konflux-central --log \
      | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+'

Alternatively, check recent PRs:

    gh pr list --repo opendatahub-io/odh-konflux-central --state open --limit 10

### 7. Update Jira

Add the label `tekton-pr-raised` and post a comment with the Tekton PR URL, component name, branch, and build type.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Dispatch rejected (HTTP 422) | Step 4 PR not merged yet -- component not in workflow options list |
| Permission denied (HTTP 403) | `GITHUB_TOKEN` needs `actions:write` scope |
| Workflow run fails | Inspect logs at the run URL; fix component config and re-trigger |
| Workflow run cancelled | Re-trigger manually |
| Monitoring times out after 30 min | Re-run -- check for an existing PR first |
| "Create pull request" step not found in logs | Open the run in GitHub and locate the PR URL manually |

## Automation

The script `scripts/run-odh-konflux-onboarder-workflow.sh` automates this playbook end-to-end.

    ./scripts/run-odh-konflux-onboarder-workflow.sh --jira-url <url>

Beyond the manual steps above, the script also:
- Parses the component onboarding YAML from the Jira attachment automatically
- Checks for existing Tekton PRs in Jira comments before triggering
- Retries the workflow once on failure with automated log diagnosis
- Monitors the workflow run with configurable timeout and polling interval
- Extracts the PR URL from multiple possible step names (fallback logic)
- Posts interim and final Jira comments and labels throughout
- Supports `ODH_KONFLUX_CENTRAL_REPO_URL` override for fork-based workflows

## Related playbooks

- [add-component-to-odh-konflux-central](add-component-to-odh-konflux-central.md) (prerequisite -- Step 4)
- [validate-component-onboarding-jira](validate-component-onboarding-jira.md) (pre-flight validation)
