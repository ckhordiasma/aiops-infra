# Add Component to RHOAI-Konflux-Central

Creates a Tekton PipelineRun resource for a new RHOAI component by generating a push PipelineRun YAML under `pipelineruns/<repo_name>/.tekton/` and raising a pull request to the version-specific branch of `rhoai-konflux-central`.

**Applies to:** RHOAI
**Pipeline step:** 4 (RHOAI)

## When to use

Run this after the Quay repository has been created and Konflux release data onboarding is complete. The Jira ticket must have `component_onboarding_details.yaml` attached with `target_rhoai_version` set. Once the PR is merged, Konflux CI will start building the component on the RHOAI release branch.

## Prerequisites

You need a GitHub account with push access to the `rhoai-konflux-central` repo (or a fork), a GitHub personal access token with `repo` scope, and `git`, `curl` installed. The onboarding YAML must include `target_rhoai_version` and `architectures`.

## What you'll be changing

**Repo:** `red-hat-data-services/konflux-central` (or the repo set by `RHOAI_KONFLUX_CENTRAL_REPO_URL`)
**File added:** `pipelineruns/<repo-name>/.tekton/<component-name>-<version-var>-push.yaml`
**Target branch:** A version-specific branch (e.g., `rhoai-3.5-ea.1`), NOT `main`

The PipelineRun YAML is written directly (not from a template), with Tekton/PAC variables (`{{revision}}`, `{{target_branch}}`, etc.) written verbatim.

Architecture mapping:

| YAML value | build-platforms entry |
|------------|----------------------|
| `x86_64` | `linux/x86_64` |
| `arm64` | `linux-m2xlarge/arm64` |
| `ppc64le` | `linux/ppc64le` |
| `s390x` | `linux/s390x` |

## Steps

### 1. Download and parse the onboarding YAML

Download `component_onboarding_details.yaml` from the Jira ticket. Extract: `component_name`, `repo_url`, `context_path`, `dockerfile_path`, `target_rhoai_version`, and `architectures`.

Derive the version variables from `target_rhoai_version` (e.g., `3.4-ea-2` produces `VERSION_VAR=v3-4-ea-2`, `BRANCH_NAME=rhoai-3.4-ea.2`, `RHOAI_MINOR_VERSION=3.4.0-ea.2`).

### 2. Check if the PipelineRun already exists

    curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/red-hat-data-services/konflux-central/contents/pipelineruns/<repo-name>/.tekton/<pipelinerun-file>?ref=<branch-name>"

If HTTP 200, add the label `rkc-changes-done` to Jira and stop.

### 3. Ensure the version branch exists

Check whether the branch (e.g., `rhoai-3.5-ea.1`) exists. If not, create it from `main`:

    gh api repos/red-hat-data-services/konflux-central/branches/<branch-name>

### 4. Fork, clone the version branch, and create a feature branch

    gh repo fork red-hat-data-services/konflux-central --clone
    cd konflux-central
    git checkout <branch-name>
    git checkout -b <jira-id>

### 5. Detect prefetch-input and write the PipelineRun YAML

Check the component repo for prefetch configuration (e.g., `go.mod`, `package-lock.json`). Write the PipelineRun YAML to `pipelineruns/<repo-name>/.tekton/<pipelinerun-file>`, including all Tekton/PAC template variables verbatim.

### 6. Commit, push, and create PR

    git add pipelineruns/<repo-name>/.tekton/<pipelinerun-file>
    git commit -m "Add <component-name>-<version-var> PipelineRun for <repo-name>"
    git push -u origin <jira-id>

    gh pr create \
      --base <branch-name> \
      --title "Add <component-name>-<version-var> PipelineRun for <repo-name>" \
      --body "Adds Tekton PipelineRun for '<component-name>' targeting branch '<branch-name>'.

    Jira: <jira-url>"

Note: the PR targets the version-specific branch, NOT `main`.

### 7. Update Jira

Add the label `rkc-pr-raised` and comment with the PR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `target_rhoai_version` missing | Add the field to the onboarding YAML and re-upload |
| `architectures` missing | Add `architectures: [x86_64, arm64]` etc. to YAML |
| Branch does not exist | The script auto-creates it from `main`; check `GITHUB_TOKEN` scope |
| Push rejected (shallow update) | Run `git fetch --unshallow origin` then retry |

## Automation

The script `scripts/add-component-to-rhoai-konflux-central.sh` automates this playbook end-to-end.

    ./scripts/add-component-to-rhoai-konflux-central.sh [--jira-url <url>]

Beyond the manual steps above, the script also:
- Downloads `component_onboarding_details.yaml` from Jira automatically
- Auto-creates the version branch from `main` if it does not exist
- Detects prefetch-input by inspecting the component repo
- Performs a fast-path check via GitHub API before cloning
- Retries PR creation up to 3 times with error classification
- Adds Jira labels and comments at each milestone

## Related playbooks

- [create-pull-pipelines-in-rhoai-konflux-central](create-pull-pipelines-in-rhoai-konflux-central.md) -- the corresponding pull-request pipeline
- [enable-renovate-on-rhoai-component-repo](enable-renovate-on-rhoai-component-repo.md) -- enable Renovate after this is merged
