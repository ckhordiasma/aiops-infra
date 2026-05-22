# Onboard Konflux Components for ODH and RHOAI

Master orchestrator for the complete component onboarding pipeline — coordinates all individual playbooks and manages state transitions.

**Applies to:** Both
**Pipeline step:** Orchestrator

## When to use

When you need to onboard a new component onto Konflux for ODH or RHOAI. This orchestrator runs the entire pipeline from Jira validation through final integration and Jira resolution. It's idempotent — you can re-run it any number of times for the same Jira URL, and it will resume from where it left off.

## Prerequisites

**Required credentials:**
- **Jira:** `JIRA_USER_EMAIL`, `JIRA_API_TOKEN`
- **GitLab (VPN required):** `GITLAB_USER`, `GITLAB_TOKEN` (with `api` + `write_repository` scope)
- **GitHub:** `GITHUB_USER`, `GITHUB_TOKEN` (with `repo` + `actions:write` scope)

**OpenShift tokens (optional overrides if kubeconfig contexts are not available):**
- `EXT_OC_TOKEN` — external cluster (stone-prd-rh01, for ODH builds)
- `INT_OC_TOKEN` — internal cluster (stone-prod-p02, for RHOAI builds)

**Required tools:**
`uv`, `git`, `oc`, `skopeo`, `yamllint`, `jq`, `kustomize` (or `kubectl`)

**Optional repo URL overrides:**
- `APP_INTERFACE_REPO_URL`
- `KONFLUX_RELEASE_DATA_REPO_URL`
- `ODH_KONFLUX_CENTRAL_REPO_URL`
- `ODH_OPERATOR_REPO_URL`
- `OBC_REPO_URL`
- `RHOAI_KONFLUX_CENTRAL_REPO_URL` (default: `https://github.com/red-hat-data-services/konflux-central.git`)
- `PYXIS_REPO_CONFIGS_REPO_URL` (default: `https://gitlab.cee.redhat.com/releng/pyxis-repo-configs.git`)
- `RHODS_DEVOPS_INFRA_REPO_URL` (default: `https://github.com/red-hat-data-services/rhods-devops-infra.git`)
- `JIRA_SERVER`

**VPN requirement:** Red Hat VPN must be active for GitLab operations (Steps 3, 4, 10).

## What you'll be changing

This orchestrator coordinates changes across multiple repositories and systems:

**For ODH:**
1. GitLab app-interface (Quay repo creation)
2. GitLab konflux-release-data (component registration)
3. GitHub odh-konflux-central (Konflux pipeline configuration)
4. GitHub opendatahub-operator (operator integration, if `is_operator=true`)
5. GitHub ODH-Build-Config (bundle integration)
6. OpenShift cluster (Tekton onboarder workflow)

**For RHOAI (in addition to the above, with variations):**
1. GitLab pyxis-repo-configs (delivery repo creation)
2. GitLab app-interface (Quay repo creation)
3. GitLab konflux-release-data (component registration, blocked until delivery repo merges)
4. GitHub rhoai-konflux-central (Konflux pipeline configuration + pull pipelines)
5. GitHub opendatahub-operator (operator integration, if `is_operator=true`)
6. GitHub ODH-Build-Config (bundle integration)
7. GitLab pyxis-repo-configs (product listing update)
8. GitHub rhods-devops-infra (auto-merge setup)
9. GitHub rhoai-konflux-central (Renovate enablement)
10. GitHub Actions workflow (Renovate config sync)

**Jira updates throughout:**
- Status transitions: To Do → In Progress → Review → Resolved
- Labels added to track each step's state
- Comments posted with pending PRs/MRs summary after each run
- Final summary table on completion

## Steps

### 1. Parse and validate the Jira issue

Follow the [Validate Component Onboarding Jira](validate-component-onboarding-jira.md) playbook to:
- Fetch the Jira issue and extract the attached YAML
- Validate the YAML against the schema
- Parse component details (name, repo URL, product context, etc.)
- Transition Jira to "In Progress"

The orchestrator stores parsed details in `component_onboarding_details.json` and `component_onboarding_details.yaml` in the working directory.

### 2. Create Quay repository

Follow the [Create Quay Repo](create-quay-repo.md) playbook to create a GitLab MR to app-interface. The orchestrator:
- Raises the MR
- Records the MR URL in `pipeline_state.json`
- Adds the `quay-mr-raised` label to Jira
- On subsequent runs, checks the MR status via GitLab API
- When merged, adds `quay-mr-merged` label

### 3. Create RHOAI delivery repository (RHOAI only)

For RHOAI components, follow the [Create RHOAI Delivery Repo](create-rhoai-delivery-repo.md) playbook. This step:
- Creates a GitLab MR to pyxis-repo-configs
- Blocks the next step (konflux-release-data) until this MR merges
- Adds `delivery-repo-mr-raised` label when raised, `delivery-repo-mr-merged` when merged

**For ODH:** This step is skipped.

### 4. Onboard component to konflux-release-data

Follow the [Onboard Component to Konflux Release Data](onboard-component-to-konflux-release-data.md) playbook:
- Creates a GitLab MR to konflux-release-data
- For RHOAI, this step waits until the delivery repo MR (Step 3) is merged
- Adds `krd-mr-raised` label when raised, `krd-mr-merged` when merged

### 5. Add component to Konflux Central

**For ODH:** Follow the [Add Component to ODH Konflux Central](add-component-to-odh-konflux-central.md) playbook.

**For RHOAI:** Follow the [Add Component to RHOAI Konflux Central](add-component-to-rhoai-konflux-central.md) playbook.

Both:
- Create a GitHub PR to the respective konflux-central repo
- Add `okc-pr-raised` (ODH) or `rkc-pr-raised` (RHOAI) label when raised
- Track merge status via GitHub API

### 6. Create pull pipelines in RHOAI Konflux Central (RHOAI only)

For RHOAI components, follow the [Create Pull Pipelines in RHOAI Konflux Central](create-pull-pipelines-in-rhoai-konflux-central.md) playbook:
- Creates an additional GitHub PR to rhoai-konflux-central for pull request pipelines
- Adds `rkc-pull-pr-raised` label when raised

**For ODH:** This step is skipped.

### 7. Run ODH Konflux onboarder workflow (ODH only)

For ODH components, after both the konflux-release-data and odh-konflux-central PRs are merged, follow the [Run ODH Konflux Onboarder Workflow](run-odh-konflux-onboarder-workflow.md) playbook:
- Triggers the OpenShift workflow
- Captures the resulting Tekton PR URL
- Adds `tekton-pr-raised` label when the workflow completes

**For RHOAI:** This step is skipped.

### 8. Integrate component with ODH operator (if is_operator=true)

If the component is an operator (`is_operator=true` in the YAML), follow the [Integrate Component with ODH Operator](integrate-component-with-odh-operator.md) playbook:
- Creates a GitHub PR to opendatahub-operator
- Adds `operator-pr-raised` label when raised

If `is_operator=false`, this step is marked as skipped.

### 9. Integrate component with bundle

Follow the [Integrate Component with Bundle](integrate-component-with-bundle.md) playbook:
- Creates a GitHub PR to ODH-Build-Config
- Adds `bundle-pr-raised` label when raised

### 10. Update RHOAI product listing (RHOAI only)

For RHOAI components, after the delivery repo MR merges, follow the [Update RHOAI Product Listing](update-rhoai-product-listing.md) playbook:
- Creates a GitLab MR to pyxis-repo-configs
- Adds `product-listing-mr-raised` label when raised

**For ODH:** This step is skipped.

### 11. Setup auto-merge (RHOAI only)

For RHOAI components, follow the [Setup Auto-Merge](setup-auto-merge.md) playbook:
- Creates a GitHub PR to rhods-devops-infra
- Adds `auto-merge-pr-raised` label when raised

**For ODH:** This step is skipped.

### 12. Enable Renovate on RHOAI component repo (RHOAI only)

For RHOAI components, follow the [Enable Renovate on RHOAI Component Repo](enable-renovate-on-rhoai-component-repo.md) playbook:
- Creates a GitHub PR to rhoai-konflux-central
- Adds `renovate-pr-raised` label when raised

**For ODH:** This step is skipped.

### 13. Sync RHOAI Renovate configs (RHOAI only)

For RHOAI components, after the Renovate enablement PR merges, follow the [Sync RHOAI Renovate Configs](sync-rhoai-renovate-configs.md) playbook:
- Triggers a GitHub Actions workflow to sync Renovate configs
- Records the workflow run URL
- Adds `renovate-sync-triggered` label

**For ODH:** This step is skipped.

### 14. Monitor and resume

The orchestrator is idempotent. After each run:
- It checks all pending PRs/MRs via their respective APIs
- Updates `pipeline_state.json` with the latest status
- Adds/removes Jira labels to reflect the current state
- Posts a comment to Jira with the list of still-pending PRs/MRs (only if something changed)
- Transitions Jira to "Review" when PRs/MRs are pending

**To advance the pipeline:** Simply re-run the orchestrator after PRs/MRs are merged. It will detect the merges, unblock dependent steps, and execute the next wave of tasks.

### 15. Completion and resolution

When all applicable steps are complete (status = `done`, `merged`, or `skipped`), the orchestrator:
- Posts a final summary table to Jira
- Adds the `component-onboarding-completed` label
- Transitions Jira to "Resolved"

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `YAML not attached to Jira` | Run the [Create Component Onboarding Jira](create-component-onboarding-jira.md) playbook first to create the Jira with a valid YAML attachment |
| `YAML fails schema validation` | Fix the YAML according to the validation errors, re-upload to Jira, and re-run |
| `VPN not active` | Activate Red Hat VPN and re-run (Steps 3, 4, 10 require VPN) |
| `Credential not set` | Export the required environment variable per the prerequisites list |
| `Tool not installed` | Install the missing tool (see prerequisites) |
| `kustomize not found` | Run the `install.sh` script to create a kubectl-backed shim at `~/.local/bin/kustomize` |
| `Quay MR fails 3× retries` | Check VPN connection and verify `GITLAB_TOKEN` has `api` scope |
| `Delivery repo MR fails` | Check VPN connection and verify `GITLAB_TOKEN` has `write_repository` scope |
| `KRD MR fails` | Check VPN connection and verify `GITLAB_TOKEN` has `write_repository` scope |
| `OKC/RKC PR fails` | Verify `GITHUB_TOKEN` has `repo` scope and push access to the konflux-central repo |
| `Pull pipelines PR fails` | Check `GITHUB_TOKEN` push access to rhoai-konflux-central |
| `Operator PR fails` | Verify `GITHUB_TOKEN` push access to opendatahub-operator |
| `Bundle PR fails` | Verify `GITHUB_TOKEN` push access to ODH-Build-Config |
| `Product listing MR fails` | Check VPN; ensure delivery repo MR has merged first |
| `Onboarder workflow 422` | KRD or OKC PRs not yet merged — check their status and re-run after merge |
| `Auto-merge PR fails` | Check `GITHUB_TOKEN` push access to rhods-devops-infra |
| `Renovate PR fails` | Check `GITHUB_TOKEN` push access to rhoai-konflux-central |
| `Renovate sync workflow 403` | `GITHUB_TOKEN` needs `actions:write` scope |
| `Jira resolution fails` | Check available Jira transitions for the issue; may need manual transition |
| `State lost after fresh checkout` | Re-run the orchestrator; it will restore state from Jira labels |
| `PR/MR not detected as merged` | Verify the URL in `pipeline_state.json` is correct; check API connectivity |

## Automation

The script `scripts/onboard-konflux-components-for-odh-and-rhoai.sh` automates this playbook end-to-end.

```bash
./scripts/onboard-konflux-components-for-odh-and-rhoai.sh <jira-url>
```

Beyond the manual steps above, the script also:
- Maintains idempotent state in `pipeline_state.json` for resumable execution
- Automatically detects and skips already-completed steps based on Jira labels
- Polls PR/MR status via GitHub and GitLab APIs on each run
- Posts incremental progress updates to Jira (only when state changes)
- Handles dependency blocking (e.g., RHOAI delivery repo must merge before KRD)
- Triggers workflows when dependencies are satisfied
- Transitions Jira through In Progress → Review → Resolved automatically
- Supports parallel execution of independent steps (not currently implemented, but the state model supports it)

## Related playbooks

- [Create Component Onboarding Jira](create-component-onboarding-jira.md)
- [Validate Component Onboarding Jira](validate-component-onboarding-jira.md)
- [Create Quay Repo](create-quay-repo.md)
- [Create RHOAI Delivery Repo](create-rhoai-delivery-repo.md)
- [Onboard Component to Konflux Release Data](onboard-component-to-konflux-release-data.md)
- [Add Component to ODH Konflux Central](add-component-to-odh-konflux-central.md)
- [Add Component to RHOAI Konflux Central](add-component-to-rhoai-konflux-central.md)
- [Create Pull Pipelines in RHOAI Konflux Central](create-pull-pipelines-in-rhoai-konflux-central.md)
- [Run ODH Konflux Onboarder Workflow](run-odh-konflux-onboarder-workflow.md)
- [Integrate Component with ODH Operator](integrate-component-with-odh-operator.md)
- [Integrate Component with Bundle](integrate-component-with-bundle.md)
- [Update RHOAI Product Listing](update-rhoai-product-listing.md)
- [Setup Auto-Merge](setup-auto-merge.md)
- [Enable Renovate on RHOAI Component Repo](enable-renovate-on-rhoai-component-repo.md)
- [Sync RHOAI Renovate Configs](sync-rhoai-renovate-configs.md)
