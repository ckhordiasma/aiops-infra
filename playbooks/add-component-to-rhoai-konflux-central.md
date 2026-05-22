# Add Component to RHOAI-Konflux-Central

Adds a Tekton PipelineRun YAML to the rhoai-konflux-central GitHub repository for a new RHOAI component, then raises a GitHub PR targeting the version-specific branch.

**Applies to:** RHOAI
**Pipeline step:** 5

## When to use

After the component has been onboarded to konflux-release-data (Step 4). This step configures the Konflux CI pipelines for the RHOAI component by adding PipelineRun definitions to the rhoai-konflux-central repository.

## Prerequisites

**Tools:**
- `git` — version control
- `gh` CLI — GitHub operations (or use web UI for PR creation)
- `uv` Python runner — for helper scripts
- `yamllint` — YAML validation

**Credentials:**
- `GITHUB_USER` — GitHub username
- `GITHUB_TOKEN` — GitHub personal access token with `repo` scope

**Optional:**
- `JIRA_USER_EMAIL`, `JIRA_API_TOKEN` — for Jira tracking
- `RHOAI_KONFLUX_CENTRAL_REPO_URL` — override default repo URL

## What you'll be changing

**Repository:** `red-hat-data-services/konflux-central` (or override via `RHOAI_KONFLUX_CENTRAL_REPO_URL`)

**Files modified:**
- `pipelines/<component-name>.yaml` — push pipeline definition

**Branch:** Creates a new feature branch from the version-specific branch (e.g., `rhoai-3.5`), **NOT** `main`.

## Steps

### 1. Fork and clone the repository

Fork the rhoai-konflux-central repository to your GitHub account.

    gh repo fork red-hat-data-services/konflux-central --clone

If you already have a fork, clone it instead.

    git clone https://github.com/$GITHUB_USER/konflux-central
    cd konflux-central

Add the upstream remote if not already present.

    git remote add upstream https://github.com/red-hat-data-services/konflux-central

### 2. Determine the target version branch

The target branch depends on the RHOAI version (e.g., `rhoai-3.5` for version 3.5). Extract this from the component onboarding YAML's `target_rhoai_version` field.

For version `3.5`, the branch is `rhoai-3.5`.
For version `3.5-ea-1`, the branch is `rhoai-3.5-ea.1`.

Ensure the branch exists on the upstream repository.

    gh api repos/red-hat-data-services/konflux-central/branches/rhoai-3.5

If the branch does not exist, contact the repository maintainers to create it.

### 3. Create a feature branch

Fetch the latest changes and create a new branch from the version-specific branch.

    git fetch upstream
    git checkout -b add-<component-name>-pipeline upstream/rhoai-3.5

Replace `rhoai-3.5` with the appropriate version branch.

### 4. Add PipelineRun YAML

Generate or copy the push pipeline YAML to `pipelines/<component-name>.yaml`. The YAML should define a Tekton PipelineRun for push events, referencing the component's source repository, build context, and Dockerfile path.

Validate the YAML file.

    yamllint pipelines/<component-name>.yaml

### 5. Commit and push changes

Stage the modified file.

    git add pipelines/<component-name>.yaml

Commit the changes.

    git commit -m "Add Konflux pipeline for <component-name>"

Push the branch to your fork.

    git push origin add-<component-name>-pipeline

### 6. Raise a GitHub PR

Create a pull request targeting the upstream version-specific branch (e.g., `rhoai-3.5`).

    gh pr create \
      --repo red-hat-data-services/konflux-central \
      --base rhoai-3.5 \
      --head $GITHUB_USER:add-<component-name>-pipeline \
      --title "Add Konflux pipeline for <component-name>" \
      --body "Adds Tekton PipelineRun configuration for <component-name> targeting RHOAI 3.5.

Related Jira: <jira-url>"

Capture the PR URL for tracking.

### 7. Update Jira (if applicable)

If a Jira URL was provided, update the issue:
- Add label `rkc-pr-raised`
- Post a comment with the PR URL

Use the Jira web UI or API:

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"update":{"labels":[{"add":"rkc-pr-raised"}]}}' \
      "https://redhat.atlassian.net/rest/api/2/issue/<JIRA-ID>"

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"body":"RHOAI Konflux Central PR raised: <pr-url>"}' \
      "https://redhat.atlassian.net/rest/api/2/issue/<JIRA-ID>/comment"

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Fork already exists | Clone the existing fork and update it: `git fetch upstream && git rebase upstream/rhoai-3.5`. |
| Target branch not found | Verify the branch name matches the RHOAI version. Contact maintainers if the branch doesn't exist. |
| PR targets wrong branch | Recreate the PR with the correct `--base` argument. Delete the incorrect PR first. |
| YAML validation fails | Check for syntax errors, indentation issues, or schema violations. Use `yamllint` to identify problems. |
| GITHUB_TOKEN lacks permissions | Ensure the token has `repo` scope. Regenerate the token at https://github.com/settings/tokens. |

## Automation

The script `scripts/add-component-to-rhoai-konflux-central.sh` automates this playbook end-to-end.

    ./scripts/add-component-to-rhoai-konflux-central.sh <jira-url>

Beyond the manual steps above, the script also:
- Automatically extracts component details from the Jira attachment
- Derives the correct target branch from the RHOAI version
- Generates the PipelineRun YAML from a template
- Validates YAML syntax before committing
- Handles idempotency: skips if PR already exists
- Updates Jira labels and comments throughout the process

## Related playbooks

- [onboard-component-to-konflux-release-data](onboard-component-to-konflux-release-data.md) — prerequisite step
- [create-pull-pipelines-in-rhoai-konflux-central](create-pull-pipelines-in-rhoai-konflux-central.md) — follow-up step
- [onboard-konflux-components-for-odh-and-rhoai](onboard-konflux-components-for-odh-and-rhoai.md) — orchestrator
