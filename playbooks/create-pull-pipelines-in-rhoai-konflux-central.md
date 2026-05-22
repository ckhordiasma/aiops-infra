# Create Pull Pipelines in RHOAI-Konflux-Central

Creates Tekton pull-request PipelineRun YAMLs for a new RHOAI component in the rhoai-konflux-central GitHub repository and raises a pull request targeting the version-specific branch.

**Applies to:** RHOAI
**Pipeline step:** 6

## When to use

After the main push pipeline has been added to rhoai-konflux-central (Step 5). This step adds pull request pipeline configurations that run on PR events for the component.

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
- `pull-pipelines/<component-name>.yaml` — pull request pipeline definition

**Branch:** Creates a new feature branch from the version-specific branch (e.g., `rhoai-3.5`), **NOT** `main`.

## Steps

### 1. Fork and clone the repository (if not already done)

If you already cloned the repository in the previous step, navigate to it and fetch the latest changes.

    cd konflux-central
    git fetch upstream

Otherwise, fork and clone as described in [add-component-to-rhoai-konflux-central](add-component-to-rhoai-konflux-central.md).

### 2. Determine the target version branch

The target branch depends on the RHOAI version (e.g., `rhoai-3.5` for version 3.5). Extract this from the component onboarding YAML's `target_rhoai_version` field.

For version `3.5`, the branch is `rhoai-3.5`.
For version `3.5-ea-1`, the branch is `rhoai-3.5-ea.1`.

### 3. Create a feature branch

Create a new branch from the version-specific branch.

    git fetch upstream
    git checkout -b add-<component-name>-pull-pipeline upstream/rhoai-3.5

Replace `rhoai-3.5` with the appropriate version branch.

### 4. Add pull pipeline YAML

Create the pull-pipelines directory if it doesn't exist.

    mkdir -p pull-pipelines

Generate or copy the pull request pipeline YAML to `pull-pipelines/<component-name>.yaml`. The YAML should define a Tekton PipelineRun for pull request events, referencing the component's source repository, build context, and Dockerfile path.

Validate the YAML file.

    yamllint pull-pipelines/<component-name>.yaml

### 5. Commit and push changes

Stage the modified file.

    git add pull-pipelines/<component-name>.yaml

Commit the changes.

    git commit -m "Add pull request pipeline for <component-name>"

Push the branch to your fork.

    git push origin add-<component-name>-pull-pipeline

### 6. Raise a GitHub PR

Create a pull request targeting the upstream version-specific branch (e.g., `rhoai-3.5`).

    gh pr create \
      --repo red-hat-data-services/konflux-central \
      --base rhoai-3.5 \
      --head $GITHUB_USER:add-<component-name>-pull-pipeline \
      --title "Add pull request pipeline for <component-name>" \
      --body "Adds Tekton pull request PipelineRun configuration for <component-name> targeting RHOAI 3.5.

Related Jira: <jira-url>"

Capture the PR URL for tracking.

### 7. Update Jira (if applicable)

If a Jira URL was provided, update the issue:
- Add label `rkc-pull-pr-raised`
- Post a comment with the PR URL

Use the Jira web UI or API:

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"update":{"labels":[{"add":"rkc-pull-pr-raised"}]}}' \
      "https://redhat.atlassian.net/rest/api/2/issue/<JIRA-ID>"

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"body":"RHOAI Konflux Central pull pipeline PR raised: <pr-url>"}' \
      "https://redhat.atlassian.net/rest/api/2/issue/<JIRA-ID>/comment"

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Fork already exists | Reuse the existing fork. Fetch latest changes: `git fetch upstream`. |
| Target branch not found | Verify the branch name matches the RHOAI version. Contact maintainers if the branch doesn't exist. |
| PR targets wrong branch | Recreate the PR with the correct `--base` argument. Delete the incorrect PR first. |
| YAML validation fails | Check for syntax errors, indentation issues, or schema violations. Use `yamllint` to identify problems. |
| Directory pull-pipelines not found | Create it with `mkdir -p pull-pipelines`. |
| GITHUB_TOKEN lacks permissions | Ensure the token has `repo` scope. Regenerate the token at https://github.com/settings/tokens. |

## Automation

The script `scripts/create-pull-pipelines-in-rhoai-konflux-central.sh` automates this playbook end-to-end.

    ./scripts/create-pull-pipelines-in-rhoai-konflux-central.sh <jira-url>

Beyond the manual steps above, the script also:
- Automatically extracts component details from the Jira attachment
- Derives the correct target branch from the RHOAI version
- Generates the pull pipeline YAML from a template
- Validates YAML syntax before committing
- Handles idempotency: skips if PR already exists
- Updates Jira labels and comments throughout the process

## Related playbooks

- [add-component-to-rhoai-konflux-central](add-component-to-rhoai-konflux-central.md) — prerequisite step
- [onboard-konflux-components-for-odh-and-rhoai](onboard-konflux-components-for-odh-and-rhoai.md) — orchestrator
