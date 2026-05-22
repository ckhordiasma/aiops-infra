# Sync RHOAI Renovate Configs

Triggers the `sync-renovate-configs.yml` GitHub Actions workflow in `rhoai-konflux-central` to propagate the central Renovate configuration to all registered component repositories.

**Applies to:** RHOAI
**Pipeline step:** 9 (RHOAI)

## When to use

Run this after merging a PR that adds a new component repo to `config.yaml` via the `enable-renovate-on-rhoai-component-repo` playbook. The sync workflow pushes the Renovate config directly to each registered repo's `main` branch (no PRs created).

## Prerequisites

You need a GitHub personal access token with `repo` scope AND `actions:write` scope (or `workflow` scope on classic PATs). The `GITHUB_USER` and `GITHUB_TOKEN` environment variables must be set.

## What you'll be changing

**Repo:** `red-hat-data-services/konflux-central` (or the repo set by `RHOAI_KONFLUX_CENTRAL_REPO_URL`)
**Action:** Triggers the `sync-renovate-configs.yml` workflow on the `main` branch. This workflow commits `"sync config with renovate-central"` directly to each registered repo.

No files are edited -- this is a workflow dispatch operation.

## Steps

### 1. Trigger the workflow

    gh workflow run sync-renovate-configs.yml \
      --repo red-hat-data-services/konflux-central \
      --ref main \
      -f dry_run=false \
      -f renovate-config=all

### 2. Monitor the workflow run

Find the run ID:

    gh run list --repo red-hat-data-services/konflux-central \
      --workflow sync-renovate-configs.yml --limit 1 --json databaseId

Watch the run:

    gh run watch <run-id> --repo red-hat-data-services/konflux-central

The workflow typically completes within a few minutes. If it fails, check the logs:

    gh run view <run-id> --repo red-hat-data-services/konflux-central --log

### 3. Handle outcomes

**Success:** Remove the `renovate-sync-triggered` label, add `renovate-sync-done`, and comment with the run URL.

**Failure:** Remove the `renovate-sync-triggered` label, add `renovate-sync-failed`, and comment with the run URL. Check the workflow logs for errors. Common issues include permission problems pushing to component repos. You can retry by triggering the workflow again.

**Timeout:** If the run takes more than 30 minutes, it may still be completing. Check the GitHub Actions UI.

### 4. Update Jira

If not already done in Step 3, add the label `renovate-sync-done` to the Jira ticket and comment confirming that the Renovate config has been synced to all registered repos. At the start of the workflow (Step 2), add the `renovate-sync-triggered` label to track that a sync is in progress.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| HTTP 403 on trigger | Regenerate GITHUB_TOKEN with `actions:write` (or `workflow`) scope |
| HTTP 404 on trigger | Verify the repo URL and workflow file path |
| Workflow fails | Check logs; common cause is missing push permissions on component repos |
| Workflow cancelled | Re-trigger the workflow |
| Timeout after 30 minutes | The run may still be in progress; check GitHub Actions UI |

## Automation

The script `scripts/sync-rhoai-renovate-configs.sh` automates this playbook end-to-end.

    ./scripts/sync-rhoai-renovate-configs.sh [--jira-url <url>]

Beyond the manual steps above, the script also:
- Triggers the workflow programmatically with retry logic (up to 3 attempts)
- Monitors the run for up to 30 minutes with 60-second polling
- Retries once automatically on workflow failure
- Fetches failure logs for automated diagnosis
- Adds Jira labels and comments throughout the process
- Classifies HTTP errors (403 = permissions, 404 = not found) for clear diagnosis

## Related playbooks

- [enable-renovate-on-rhoai-component-repo](enable-renovate-on-rhoai-component-repo.md) -- must be merged before running this
