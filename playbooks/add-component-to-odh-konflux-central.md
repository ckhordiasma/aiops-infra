# Add Component to ODH-Konflux-Central

Creates Tekton PipelineRun resources for a new ODH/RHOAI component by generating push and pull-request PipelineRun YAMLs from the OKC templates, adding the component to the onboarder workflow, and raising a pull request to `odh-konflux-central`.

**Applies to:** Both (ODH and RHOAI)
**Pipeline step:** 4

## When to use

Run this after the Quay repository has been created (Step 2) and the Konflux release data onboarding (Step 3) is complete. The Jira ticket must have `component_onboarding_details.yaml` attached. Once the resulting PR is merged, Konflux CI will start building the component.

## Prerequisites

You need a GitHub account with push access to the `odh-konflux-central` repo (or a fork), a GitHub personal access token with `repo` scope, the Jira CLI credentials (`JIRA_USER_EMAIL`, `JIRA_API_TOKEN`), and `git` installed. The `component_onboarding_details.yaml` must be attached to the Jira ticket.

## What you'll be changing

**Repo:** `opendatahub-io/odh-konflux-central` (or the repo set by `ODH_KONFLUX_CENTRAL_REPO_URL`)
**Files added:**
- `pipelineruns/<repo-name>/<component-name>-push.yaml` -- push PipelineRun
- `pipelineruns/<repo-name>/<component-name>-pull-request.yaml` -- PR PipelineRun

**File modified:**
- `.github/workflows/odh-konflux-onboarder.yml` -- component added to the `options` list

The PipelineRun YAMLs are generated from the templates in `pipelineruns/template/`. Key substitutions include the repo URL, branch, Dockerfile path, context path, Quay image, namespace, and application name.

## Steps

### 1. Download and parse the onboarding YAML

Download `component_onboarding_details.yaml` from the Jira ticket. Extract: `component_name`, `repo_url`, `repo_branch`, `context_path`, `dockerfile_path`, `build_type`, and `product_context`.

Derive the Konflux component name (append `-ci` if not already present), the push and PR run names, output image tags (CI: `odh-stable`/`odh-pr`; RELEASE: from `output_image_tag` field), and service account name.

### 2. Determine product context

Based on `product_context` (ODH or RHOAI), set the namespace and application:

| Product | Namespace | Application |
|---------|-----------|-------------|
| ODH | `open-data-hub-tenant` | `opendatahub-builds` |
| RHOAI | `rhoai-tenant` | `rhoai-builds` |

### 3. Check if PipelineRuns already exist

    curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/opendatahub-io/odh-konflux-central/contents/pipelineruns/<repo-name>/<component-name>-push.yaml"

If both push and PR files return HTTP 200, the PipelineRuns already exist. Add the label `okc-changes-done` to Jira and stop.

### 4. Fork, clone, and create a branch

    gh repo fork opendatahub-io/odh-konflux-central --clone
    cd odh-konflux-central
    git checkout -b <jira-id>

Use sparse checkout for `pipelineruns/template`, `pipelineruns/<repo-name>`, and `.github/workflows`.

### 5. Generate PipelineRun files

Copy the push template and apply `sed` substitutions for all placeholders (repo URL, branch, component name, Quay image, Dockerfile path, context path, namespace, application, service account). Do the same for the pull-request template. Key differences in the PR template: placeholder comments (`#`) must also be removed during substitution.

Verify no unreplaced placeholders remain (no `$$TARGET_BRANCH$$`, `quayurl`, or `#component-git-url`).

### 6. Update the onboarder workflow

Open `.github/workflows/odh-konflux-onboarder.yml` and add the repo name to the `options` list under `on.workflow_dispatch.inputs.components`.

### 7. Commit, push, and create PR

    git add pipelineruns/<repo-name>/ .github/workflows/odh-konflux-onboarder.yml
    git commit -m "Add <konflux-component-name> PipelineRuns for <repo-name>"
    git push -u origin <jira-id>

    gh pr create \
      --title "Add <konflux-component-name> PipelineRuns for <component-name>" \
      --body "Add Konflux CI PipelineRuns for '<component-name>'.

    Product: <product-context>
    Source repo: <repo-url>
    Jira: <jira-url>"

### 8. Update Jira

Add the label `okc-pr-raised` and comment with the PR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Unknown BUILD_TYPE | Set `build_type: CI` or `build_type: RELEASE` in the YAML |
| `output_image_tag` missing for RELEASE | Add `output_image_tag: <tag>` under `inputs:` in the YAML |
| Unreplaced placeholders in generated YAML | Re-check sed commands; template may have changed |
| Push rejected (shallow update) | Run `git fetch --unshallow origin` then retry |

## Automation

The script `scripts/add-component-to-odh-konflux-central.sh` automates this playbook end-to-end.

    ./scripts/add-component-to-odh-konflux-central.sh --jira-url <url>

Beyond the manual steps above, the script also:
- Downloads `component_onboarding_details.yaml` from Jira automatically
- Performs a fast-path check via GitHub API before cloning
- Applies all template substitutions programmatically via `sed`
- Verifies no unreplaced placeholders remain
- Retries PR creation up to 3 times with error classification
- Adds Jira labels and comments at each milestone

## Related playbooks

- [create-pull-pipelines-in-rhoai-konflux-central](create-pull-pipelines-in-rhoai-konflux-central.md) -- RHOAI pull-request pipelines
- [add-component-to-rhoai-konflux-central](add-component-to-rhoai-konflux-central.md) -- RHOAI push pipelines
