# Onboard Konflux Components for ODH and RHOAI

Master orchestrator for the full ODH/RHOAI component onboarding pipeline. Coordinates all sub-steps, tracks their PR/MR status, and advances the pipeline as dependencies are satisfied.

**Applies to:** Both
**Pipeline step:** Orchestrator

## When to use

Run this after a component onboarding Jira ticket has been created (via `create-component-onboarding-jira`) with a valid `component_onboarding_details.yaml` attached. Re-run as many times as needed -- each invocation syncs state from Jira, checks PR/MR merge status, executes newly-unblocked steps, and posts a progress summary.

## Prerequisites

- **Jira** credentials: `JIRA_USER_EMAIL` and `JIRA_API_TOKEN` environment variables
- **GitLab** credentials: `GITLAB_USER` and `GITLAB_TOKEN` (with `api` + `write_repository` scopes)
- **GitHub** credentials: `GITHUB_USER` and `GITHUB_TOKEN` (with `repo` + `actions:write` scopes)
- **OpenShift** tokens: `EXT_OC_TOKEN` (external cluster) and/or `INT_OC_TOKEN` (internal cluster) if no matching kubeconfig context exists
- **Tools**: `uv`, `git`, `oc`, `skopeo`, `yamllint`, `jq`, `kustomize` (or `kubectl`)
- **VPN must be active** for GitLab steps (Quay repo, delivery repo, konflux-release-data, product listing)

## What you'll be changing

This orchestrator does not modify a single repo directly. Instead, it invokes each sub-step which raises PRs/MRs across multiple repositories. The pipeline state is tracked via Jira labels and a local `pipeline_state.json` file.

**Pipeline steps by product:**

| Step key | Description | ODH | RHOAI | Depends on |
|----------|-------------|-----|-------|------------|
| `validate` | Validate Jira YAML | Yes | Yes | -- |
| `quay` | Create Quay repo (app-interface MR) | Yes | Yes | validate |
| `delivery_repo` | Create delivery repo (pyxis-repo-configs MR) | -- | Yes | validate |
| `krd` | Onboard to konflux-release-data (MR) | Yes | Yes | validate (ODH), delivery_repo (RHOAI) |
| `okc` | Add to konflux-central (PR) | Yes | Yes | validate |
| `pull_pipelines` | Pull-request pipelines (PR) | -- | Yes | validate |
| `onboarder_workflow` | Trigger onboarder GitHub Actions | Yes | -- | krd, okc |
| `operator` | Integrate with operator (PR) | Yes | Yes | validate |
| `bundle` | Integrate with bundle (PR) | Yes | Yes | validate |
| `product_listing` | Update product listing (MR) | -- | Yes | delivery_repo |
| `auto_merge` | Setup auto-merge (PR) | -- | Yes | validate |
| `renovate` | Enable Renovate (PR) | -- | Yes | validate |
| `renovate_sync` | Sync Renovate configs (workflow) | -- | Yes | renovate |

## Steps

### 1. Validate the Jira ticket

Open the Jira ticket in your browser and confirm that:
- A `component_onboarding_details.yaml` file is attached
- The YAML contains all required fields (component name, repo URL, product context, etc.)

Download the attachment and validate it against the schema. See the [validate-component-onboarding-jira playbook](validate-component-onboarding-jira.md) for details.

If validation fails, fix the YAML and re-upload it to Jira before proceeding.

### 2. Parse component details

From the validated YAML, identify the key values you will need throughout the pipeline:
- **Component name** (e.g., `odh-model-controller`)
- **Product context**: `ODH` or `RHOAI`
- **Repository URL and branch**
- **Quay organization and repository path**
- **Whether this is an operator component** (`is_operator: true/false`)

Use the product context to determine which steps apply (see the table above).

### 3. Check current pipeline state

Look at the Jira labels to determine which steps have already been completed:
- `quay-mr-raised` / `quay-mr-merged` -- Quay repo step status
- `krd-mr-raised` / `krd-mr-merged` -- Konflux release data step status
- `okc-pr-raised` / `okc-pr-merged` -- Konflux central step status
- Similar patterns for all other steps

For any step showing a "raised" label, check whether the PR/MR has actually been merged by visiting the URL in the Jira comments.

### 4. Determine which steps are ready to run

A step is ready when:
1. Its status is still "pending" (not yet started)
2. All of its dependencies (see the table above) have been merged or completed

Work through the steps in order, running each one that is unblocked.

### 5. Run unblocked steps

For each ready step, follow the corresponding playbook. After raising the PR/MR, add the appropriate "raised" label to the Jira ticket and post the PR/MR URL as a comment.

**Step-by-step references:**

**a. Create Quay repo** (step key: `quay`)
Follow the [create-quay-repo playbook](create-quay-repo.md). After the MR is raised, add label `quay-mr-raised` to Jira. If the Quay repo already exists, add `quay-mr-merged` instead.

**b. Create delivery repo** (step key: `delivery_repo`, RHOAI only)
Follow the [create-rhoai-delivery-repo playbook](create-rhoai-delivery-repo.md). Requires VPN. Add label `delivery-repo-mr-raised`. This MR must merge before `krd` can proceed. If the delivery repo already exists, add `delivery-repo-exists`.

**c. Onboard to konflux-release-data** (step key: `krd`)
Follow the [onboard-component-to-konflux-release-data playbook](onboard-component-to-konflux-release-data.md). Requires VPN. For RHOAI, wait until the delivery-repo MR has merged. Add label `krd-mr-raised`. If component already exists, add `krd-mr-merged`.

**d. Add to konflux-central** (step key: `okc`)
For ODH: follow [add-component-to-odh-konflux-central playbook](add-component-to-odh-konflux-central.md). Add label `okc-pr-raised`.
For RHOAI: follow [add-component-to-rhoai-konflux-central playbook](add-component-to-rhoai-konflux-central.md). Add label `rkc-pr-raised`.

**e. Create pull-request pipelines** (step key: `pull_pipelines`, RHOAI only)
Follow the [create-pull-pipelines-in-rhoai-konflux-central playbook](create-pull-pipelines-in-rhoai-konflux-central.md). Add label `rkc-pull-pr-raised`.

**f. Integrate with operator** (step key: `operator`)
Follow the [integrate-component-with-odh-operator playbook](integrate-component-with-odh-operator.md). If `is_operator` is false, skip this step. Add label `operator-pr-raised`.

**g. Integrate with bundle** (step key: `bundle`)
Follow the [integrate-component-with-bundle playbook](integrate-component-with-bundle.md). Add label `bundle-pr-raised`.

**h. Update product listing** (step key: `product_listing`, RHOAI only)
Follow the [update-rhoai-product-listing playbook](update-rhoai-product-listing.md). Requires VPN. Only runs after delivery-repo is merged. Add label `product-listing-mr-raised`. If entry already exists, add `product-listing-exists`.

**i. Setup auto-merge** (step key: `auto_merge`, RHOAI only)
Follow the [setup-auto-merge playbook](setup-auto-merge.md). Add label `auto-merge-pr-raised`.

**j. Enable Renovate** (step key: `renovate`, RHOAI only)
Follow the [enable-renovate-on-rhoai-component-repo playbook](enable-renovate-on-rhoai-component-repo.md). Add label `renovate-pr-raised`.

### 6. Handle workflow triggers

These steps fire automatically once their dependencies merge:

**a. ODH onboarder workflow** (step key: `onboarder_workflow`, ODH only)
Once both `krd` and `okc` are merged, follow the [run-odh-konflux-onboarder-workflow playbook](run-odh-konflux-onboarder-workflow.md). Add label `tekton-pr-raised`.

**b. Sync Renovate configs** (step key: `renovate_sync`, RHOAI only)
Once the `renovate` PR is merged, follow the [sync-rhoai-renovate-configs playbook](sync-rhoai-renovate-configs.md). Add label `renovate-sync-triggered`.

### 7. Post progress summary to Jira

After each run where something changed (a PR/MR was raised or merged), post a comment to Jira listing the PRs/MRs that are still pending review. Tag the ticket assignee if any PRs/MRs have been open for more than 2 days.

### 8. Resolve or keep in review

Check whether all applicable steps are complete:
- If **all done**: add label `component-onboarding-completed` and transition the Jira ticket to "Resolved". Post a final summary comment showing the full pipeline status.
- If **some pending**: transition Jira to "Review" status. Re-run the orchestrator after the outstanding PRs/MRs are merged.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Credential not set | Export the missing env var per the prerequisites list |
| Tool not installed | Install the required tool (uv, git, oc, skopeo, etc.) |
| YAML not attached to Jira | Run the create-component-onboarding-jira playbook first |
| YAML fails schema validation | Fix the YAML, re-upload to Jira, re-run |
| VPN not active | Activate Red Hat VPN; re-run (the pipeline is idempotent) |
| PR/MR not detected as merged | Check that the URL in Jira comments is correct; verify GitHub/GitLab API connectivity |
| Jira status transition fails | Check available Jira transitions for the ticket's current state |
| State lost / fresh checkout | Re-run -- pipeline state is reconstructed from Jira labels |
| Delivery-repo MR still open | `krd` and `product_listing` are blocked until it merges |
| Onboarder workflow returns 422 | Both `krd` and `okc` must be merged first |

## Automation

The script `scripts/onboard-konflux-components-for-odh-and-rhoai.sh` automates this playbook end-to-end.

    ./scripts/onboard-konflux-components-for-odh-and-rhoai.sh <jira-url>

Beyond the manual steps above, the script also:
- Maintains a local `pipeline_state.json` file tracking each step's status, PR/MR URLs, and timestamps
- Automatically syncs state from Jira labels on each run (survives fresh checkouts)
- Queries GitHub/GitLab APIs to detect newly-merged PRs/MRs
- Manages Jira labels (adding "raised"/"merged" labels) and status transitions automatically
- Posts structured progress summaries to Jira only when something has changed
- Posts idle reminders when PRs/MRs have been open for more than 2 days
- Handles per-step idempotency: already-completed steps are skipped automatically
- Calls each sub-step's automation script in the correct dependency order

## Related playbooks

- [validate-component-onboarding-jira](validate-component-onboarding-jira.md) (prerequisite)
- [create-quay-repo](create-quay-repo.md)
- [create-rhoai-delivery-repo](create-rhoai-delivery-repo.md) (RHOAI only)
- [onboard-component-to-konflux-release-data](onboard-component-to-konflux-release-data.md)
- [add-component-to-odh-konflux-central](add-component-to-odh-konflux-central.md) (ODH)
- [add-component-to-rhoai-konflux-central](add-component-to-rhoai-konflux-central.md) (RHOAI)
- [create-pull-pipelines-in-rhoai-konflux-central](create-pull-pipelines-in-rhoai-konflux-central.md) (RHOAI)
- [run-odh-konflux-onboarder-workflow](run-odh-konflux-onboarder-workflow.md) (ODH)
- [integrate-component-with-odh-operator](integrate-component-with-odh-operator.md)
- [integrate-component-with-bundle](integrate-component-with-bundle.md)
- [update-rhoai-product-listing](update-rhoai-product-listing.md) (RHOAI)
- [setup-auto-merge](setup-auto-merge.md) (RHOAI)
- [enable-renovate-on-rhoai-component-repo](enable-renovate-on-rhoai-component-repo.md) (RHOAI)
- [sync-rhoai-renovate-configs](sync-rhoai-renovate-configs.md) (RHOAI)
