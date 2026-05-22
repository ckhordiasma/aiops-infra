# Create Pull Pipelines in RHOAI-Konflux-Central

Creates a Tekton PipelineRun resource for pull-request builds of a new RHOAI component, generating a pull-request PipelineRun YAML under `pipelineruns/<repo_name>/.tekton/` and raising a PR to the `main` branch of `rhoai-konflux-central`.

**Applies to:** RHOAI
**Pipeline step:** 4 (RHOAI)

## When to use

Run this after (or in parallel with) the push PipelineRun in `add-component-to-rhoai-konflux-central`. The Jira ticket must have `component_onboarding_details.yaml` attached. Once merged, Konflux will build PRs against the component repo.

## Prerequisites

You need a GitHub account with push access to the `rhoai-konflux-central` repo (or a fork), a GitHub personal access token with `repo` scope, and `git`, `curl` installed. The onboarding YAML must include `architectures`.

## What you'll be changing

**Repo:** `red-hat-data-services/konflux-central` (or the repo set by `RHOAI_KONFLUX_CENTRAL_REPO_URL`)
**File added:** `pipelineruns/<repo-name>/.tekton/<component-name>-pull-request.yaml`
**Target branch:** `main` (not a version-specific branch)

Key differences from the push pipeline:
- Application label is `automation` (not version-specific)
- Service account is `build-pipeline-pull-request-pipelines` (shared)
- Output image goes to `quay.io/rhoai/pull-request-pipelines:<component-name>-{{revision}}`
- Images expire after 5 days
- Cancel-in-progress is `true`

## Steps

### 1. Download and parse the onboarding YAML

Download `component_onboarding_details.yaml` from the Jira ticket. Extract: `component_name`, `repo_url`, `context_path`, `dockerfile_path`, and `architectures`.

### 2. Check if the PipelineRun already exists

    curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/red-hat-data-services/konflux-central/contents/pipelineruns/<repo-name>/.tekton/<component-name>-pull-request.yaml?ref=main"

If HTTP 200, add the label `rkc-pull-changes-done` to Jira and stop.

### 3. Fork, clone main branch, and create a feature branch

    gh repo fork red-hat-data-services/konflux-central --clone
    cd konflux-central
    git checkout -b <jira-id>

### 4. Detect prefetch-input and write the PipelineRun YAML

Check the component repo for prefetch configuration. Write the pull-request PipelineRun YAML to `pipelineruns/<repo-name>/.tekton/<component-name>-pull-request.yaml`, with Tekton/PAC template variables written verbatim.

### 5. Commit, push, and create PR

    git add pipelineruns/<repo-name>/.tekton/<component-name>-pull-request.yaml
    git commit -m "Add <component-name> pull-request PipelineRun for <repo-name>"
    git push -u origin <jira-id>

    gh pr create \
      --title "Add <component-name> pull-request PipelineRun for <repo-name>" \
      --body "Adds Tekton pull-request PipelineRun for '<component-name>'.

    Jira: <jira-url>"

### 6. Update Jira

Add the label `rkc-pull-pr-raised` and comment with the PR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `architectures` missing from YAML | Add `architectures: [x86_64, arm64]` etc. |
| PipelineRun already exists | Expected -- exits cleanly, Jira labelled `rkc-pull-changes-done` |
| Push rejected (shallow update) | Run `git fetch --unshallow origin` then retry |

## Automation

The script `scripts/create-pull-pipelines-in-rhoai-konflux-central.sh` automates this playbook end-to-end.

    ./scripts/create-pull-pipelines-in-rhoai-konflux-central.sh [--jira-url <url>]

Beyond the manual steps above, the script also:
- Downloads `component_onboarding_details.yaml` from Jira automatically
- Detects prefetch-input by inspecting the component repo
- Performs a fast-path check via GitHub API before cloning
- Retries PR creation up to 3 times with error classification
- Adds Jira labels and comments at each milestone

## Related playbooks

- [add-component-to-rhoai-konflux-central](add-component-to-rhoai-konflux-central.md) -- the corresponding push pipeline
- [enable-renovate-on-rhoai-component-repo](enable-renovate-on-rhoai-component-repo.md) -- enable Renovate after both pipelines are merged
