# Add Component to ODH-Konflux-Central

Adds Tekton PipelineRun YAMLs and updates the onboarder workflow in the odh-konflux-central GitHub repository for a new ODH component, then raises a GitHub PR.

**Applies to:** ODH
**Pipeline step:** 3 (ODH)

## When to use

After the component has been onboarded to konflux-release-data (Step 4). This step configures the Konflux CI pipelines for the component by adding PipelineRun definitions to the odh-konflux-central repository.

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
- `ODH_KONFLUX_CENTRAL_REPO_URL` — override default repo URL

## What you'll be changing

**Repository:** `opendatahub-io/odh-konflux-central` (or override via `ODH_KONFLUX_CENTRAL_REPO_URL`)

**Files modified:**
- `konflux/pipelines/<component-name>/push.yaml` — push pipeline definition
- `konflux/pipelines/<component-name>/main.yaml` — main pipeline definition
- `.github/workflows/update-component.yaml` — update onboarder workflow inputs

**Branch:** Creates a new feature branch from `main`

## Steps

### 1. Fork and clone the repository

Fork the odh-konflux-central repository to your GitHub account.

    gh repo fork opendatahub-io/odh-konflux-central --clone

If you already have a fork, clone it instead.

    git clone https://github.com/$GITHUB_USER/odh-konflux-central
    cd odh-konflux-central

Add the upstream remote if not already present.

    git remote add upstream https://github.com/opendatahub-io/odh-konflux-central

### 2. Create a feature branch

Fetch the latest changes and create a new branch.

    git fetch upstream
    git checkout -b add-<component-name>-pipelines upstream/main

### 3. Add PipelineRun YAMLs

Create the pipeline directory for the component.

    mkdir -p konflux/pipelines/<component-name>

Generate or copy the push pipeline YAML to `konflux/pipelines/<component-name>/push.yaml`. The YAML should define a Tekton PipelineRun for push events, referencing the component's source repository, build context, and Dockerfile path.

Generate or copy the main pipeline YAML to `konflux/pipelines/<component-name>/main.yaml`. This defines the main branch pipeline configuration.

Validate the YAML files.

    yamllint konflux/pipelines/<component-name>/

### 4. Update the onboarder workflow

Edit `.github/workflows/update-component.yaml` to add the new component to the workflow inputs. Locate the `component` input section and add the component name to the list.

Example:

```yaml
component:
  type: choice
  description: 'Component name'
  options:
    - existing-component
    - <component-name>  # Add this line
```

### 5. Commit and push changes

Stage the modified files.

    git add konflux/pipelines/<component-name>/ .github/workflows/update-component.yaml

Commit the changes.

    git commit -m "Add Konflux pipelines for <component-name>"

Push the branch to your fork.

    git push origin add-<component-name>-pipelines

### 6. Raise a GitHub PR

Create a pull request targeting the upstream `main` branch.

    gh pr create \
      --repo opendatahub-io/odh-konflux-central \
      --base main \
      --head $GITHUB_USER:add-<component-name>-pipelines \
      --title "Add Konflux pipelines for <component-name>" \
      --body "Adds Tekton PipelineRun configurations for <component-name>.

Related Jira: <jira-url>"

Capture the PR URL for tracking.

### 7. Update Jira (if applicable)

If a Jira URL was provided, update the issue:
- Add label `okc-pr-raised`
- Post a comment with the PR URL

Use the Jira web UI or API:

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"update":{"labels":[{"add":"okc-pr-raised"}]}}' \
      "https://redhat.atlassian.net/rest/api/2/issue/<JIRA-ID>"

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"body":"ODH Konflux Central PR raised: <pr-url>"}' \
      "https://redhat.atlassian.net/rest/api/2/issue/<JIRA-ID>/comment"

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Fork already exists | Clone the existing fork and update it: `git fetch upstream && git rebase upstream/main`. |
| YAML validation fails | Check for syntax errors, indentation issues, or schema violations. Use `yamllint` to identify problems. |
| PR already exists for this branch | Use the existing PR or delete the remote branch and recreate it: `git push origin --delete <branch>`. |
| GITHUB_TOKEN lacks permissions | Ensure the token has `repo` scope. Regenerate the token at https://github.com/settings/tokens. |

## Automation

The script `scripts/add-component-to-odh-konflux-central.sh` automates this playbook end-to-end.

    ./scripts/add-component-to-odh-konflux-central.sh <jira-url>

Beyond the manual steps above, the script also:
- Automatically extracts component details from the Jira attachment
- Generates the PipelineRun YAML files from templates
- Validates YAML syntax before committing
- Handles idempotency: skips if PR already exists
- Updates Jira labels and comments throughout the process

## Related playbooks

- [onboard-component-to-konflux-release-data](onboard-component-to-konflux-release-data.md) — prerequisite step
- [run-odh-konflux-onboarder-workflow](run-odh-konflux-onboarder-workflow.md) — follow-up step
- [onboard-konflux-components-for-odh-and-rhoai](onboard-konflux-components-for-odh-and-rhoai.md) — orchestrator
