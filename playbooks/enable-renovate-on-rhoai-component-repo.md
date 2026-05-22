# Enable Renovate on RHOAI Component Repo

Registers a new RHOAI component repository in the Renovate configuration maintained in `rhoai-konflux-central` (`config.yaml` on `main`) so that the Renovate bot keeps its dependencies up to date.

**Applies to:** RHOAI
**Pipeline step:** 9 (RHOAI)

## When to use

Run this after the component repository has been created and onboarded to Konflux. The Renovate config entry tells the bot which repos to manage. This step is typically triggered by the master onboarding orchestrator once earlier steps are complete.

## Prerequisites

You need a GitHub account with push access to the `rhoai-konflux-central` repo (or a fork), a GitHub personal access token with `repo` scope, and the `component_onboarding_details.yaml` file (either downloaded from the Jira ticket or already in your working directory). You also need `git` and `curl` installed.

## What you'll be changing

**Repo:** `red-hat-data-services/konflux-central` (or the repo set by `RHOAI_KONFLUX_CENTRAL_REPO_URL`)
**File:** `config.yaml` on the `main` branch
**Change:** Append a new entry to the `sync-repositories` array of the first distribution group (the one using `renovate/default-renovate-distribution.json`).

The new entry looks like:

```yaml
  - name: "red-hat-data-services/<repo-name>"
```

## Steps

### 1. Download the onboarding YAML from the Jira ticket

If you do not already have `component_onboarding_details.yaml`, download it from the Jira ticket's attachments. Extract the `repo_url` field and derive the repo name (last path segment, without `.git`).

### 2. Check whether the entry already exists

Fetch the current `config.yaml` from the `main` branch and search for the repo name:

    curl -sf \
      -H "Authorization: token $GITHUB_TOKEN" \
      "https://raw.githubusercontent.com/red-hat-data-services/konflux-central/main/config.yaml" \
      | grep -F "red-hat-data-services/<repo-name>"

If the entry already exists, no action is needed. Add the label `renovate-changes-done` to the Jira ticket and comment that the entry is already present.

### 3. Fork and clone the repo

    gh repo fork red-hat-data-services/konflux-central --clone
    cd konflux-central
    git checkout -b renovate-<repo-name>

### 4. Edit config.yaml

Open `config.yaml` and find the first distribution group (the one with `renovate-config: "renovate/default-renovate-distribution.json"`). Under its `sync-repositories` array, add:

```yaml
  - name: "red-hat-data-services/<repo-name>"
```

Maintain alphabetical order if the existing entries follow that convention.

### 5. Commit and push

    git add config.yaml
    git commit -m "Enable Renovate for <repo-name>"
    git push -u origin renovate-<repo-name>

### 6. Create a pull request

    gh pr create \
      --title "Enable Renovate for <repo-name>" \
      --body "Adds 'red-hat-data-services/<repo-name>' to the default Renovate distribution in config.yaml.

    Jira: <jira-url>"

### 7. Update Jira

Add the label `renovate-pr-raised` to the Jira ticket and comment with the PR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Push rejected with "shallow update not allowed" | Run `git fetch --unshallow origin` then push again |
| PR creation fails with "branch not found" | Re-push the branch to origin and retry |
| Entry already exists | Expected -- the skill exits cleanly and labels Jira `renovate-changes-done` |

## Automation

The script `scripts/enable-renovate-on-rhoai-component-repo.sh` automates this playbook end-to-end.

    ./scripts/enable-renovate-on-rhoai-component-repo.sh [--jira-url <url>]

Beyond the manual steps above, the script also:
- Downloads `component_onboarding_details.yaml` from Jira automatically
- Performs a fast-path check via GitHub API before cloning
- Retries PR creation up to 3 times with error classification
- Handles shallow clone issues automatically
- Adds Jira labels and comments at each milestone

## Related playbooks

- [add-component-to-rhoai-konflux-central](add-component-to-rhoai-konflux-central.md) -- must be merged before this runs
- [sync-rhoai-renovate-configs](sync-rhoai-renovate-configs.md) -- run after this PR is merged to propagate config
