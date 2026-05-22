# Sync RHOAI Renovate Configs

Triggers the `sync-renovate-configs` GitHub Actions workflow in `konflux-central` to push the central Renovate configuration to all registered component repositories.

**Applies to:** RHOAI
**Pipeline step:** 9 (RHOAI)

## When to use

Run this after merging a PR that adds a new component repo to `config.yaml` via the [enable-renovate-on-rhoai-component-repo](enable-renovate-on-rhoai-component-repo.md) playbook. The sync workflow pushes the shared Renovate config directly to each registered repo's `main` branch.

## Prerequisites

- GitHub account with push access to `red-hat-data-services/konflux-central`
- `GITHUB_TOKEN` with `repo` + `actions:write` scope (or `workflow` scope on classic PATs)
- `gh` CLI installed and authenticated
- Jira credentials if you want to track progress on a ticket

## What you'll be changing

No repository file changes — this workflow pushes commits directly to registered component repos. Each repo receives a commit with the message `"sync config with renovate-central"` on its `main` branch, updating or adding the Renovate configuration files.

| Field | Value |
|-------|-------|
| Workflow file | `.github/workflows/sync-renovate-configs.yml` |
| Repo | `red-hat-data-services/konflux-central` |
| Trigger | `workflow_dispatch` |

## Steps

### 1. Trigger the sync workflow

Dispatch the workflow via the GitHub CLI:

    gh workflow run sync-renovate-configs.yml \
      --repo red-hat-data-services/konflux-central \
      --ref main \
      -f dry_run=false \
      -f renovate-config=all

### 2. Find the run ID

List recent workflow runs to find the one you just triggered:

    gh run list --repo red-hat-data-services/konflux-central \
      --workflow sync-renovate-configs.yml --limit 5

Note the run ID from the output.

### 3. Monitor the workflow run

Watch the run until it completes:

    gh run watch <run-id> --repo red-hat-data-services/konflux-central

Alternatively, check the status periodically:

    gh run view <run-id> --repo red-hat-data-services/konflux-central

The workflow typically completes within a few minutes but can take up to 30 minutes for many repos.

If tracking via Jira, add label `renovate-sync-triggered` when the run starts and post a comment with the run URL.

### 4. Verify success

Check that the run completed successfully:

    gh run view <run-id> --repo red-hat-data-services/konflux-central --json conclusion -q '.conclusion'

If the run failed, view the logs:

    gh run view <run-id> --repo red-hat-data-services/konflux-central --log-failed

If tracking via Jira and the run failed, add label `renovate-sync-failed` (removing `renovate-sync-triggered`) and post a comment with the failure details and log URL.

### 5. Update Jira

On success, remove label `renovate-sync-triggered` (if present), add label `renovate-sync-done`, and comment noting the workflow run URL and that the Renovate config sync completed successfully.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| HTTP 403 when triggering | Your `GITHUB_TOKEN` needs `actions:write` scope (or `workflow` scope on classic PATs). Regenerate the token. |
| HTTP 404 when triggering | Verify the repo URL and that the workflow file exists at `.github/workflows/sync-renovate-configs.yml`. |
| Workflow run fails | Check the "Sync" step logs via `gh run view --log-failed`. Common causes: missing repo access, branch protection rules. Retry after fixing. |
| Workflow cancelled | Re-trigger the workflow. |
| Run takes more than 30 minutes | The run may still be completing. Check the GitHub Actions UI. |

## Automation

The script `scripts/sync-rhoai-renovate-configs.sh` automates this playbook end-to-end.

    ./scripts/sync-rhoai-renovate-configs.sh [--jira-url <url>]

Beyond the manual steps above, the script also:
- Retries workflow dispatch up to 3 times on transient errors
- Polls the workflow run every 60 seconds with a 30-minute timeout
- Automatically retries the entire workflow once on failure
- Fetches failure logs for automated diagnosis
- Manages Jira labels (`renovate-sync-triggered`, `renovate-sync-done`, `renovate-sync-failed`) throughout

## Related playbooks

- [enable-renovate-on-rhoai-component-repo](enable-renovate-on-rhoai-component-repo.md)
