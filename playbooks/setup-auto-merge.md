# Setup Auto-Merge

Configures auto-merge for a new component repository by updating four files in the `rhods-devops-infra` repo and raising a GitHub PR targeting `main`.

**Applies to:** RHOAI
**Pipeline step:** 8 (RHOAI)

## When to use

Run this after the component repository has been fully onboarded (Konflux pipelines, bundle integration, Renovate). This step sets up automatic merging of upstream changes into the downstream (Red Hat) fork.

## Prerequisites

You need a GitHub account with push access to the `rhods-devops-infra` repo (or a fork), a GitHub personal access token with `repo` scope, and `git`, `curl` installed.

## What you'll be changing

**Repo:** `red-hat-data-services/rhods-devops-infra` (or the repo set by `RHODS_DEVOPS_INFRA_REPO_URL`)
**Four files modified on `main`:**

1. **`src/config/upstream-source-map.yaml`** -- new entry:
```yaml
- name: <repo-name>
  automerge: 'yes'
  src:
    url: <upstream-repo-url>.git
    branch: main
  dest:
    url: <repo-url>.git
    branch: main
```

2. **`src/config/main-release-source-map.yaml`** -- new entry:
```yaml
- name: <repo-name>
  automerge: 'yes'
  repo-url: <repo-url>.git
```

3. **`.github/workflows/upstream-auto-merge.yaml`** -- add `<repo-name>` to the `repositories` options list
4. **`.github/workflows/main-release-auto-merge.yaml`** -- add `<repo-name>` to the `repositories` options list

## Steps

### 1. Download and parse the onboarding YAML

Download `component_onboarding_details.yaml` from the Jira ticket. Extract `repo_url` and derive `repo_name` (last path segment without `.git`). Detect the upstream repo URL.

### 2. Check if entries already exist

Fetch both config files from the `main` branch via GitHub API and check if the repo name is already present in both:

    curl -s -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/red-hat-data-services/rhods-devops-infra/contents/src/config/upstream-source-map.yaml?ref=main"

If the repo is in both files, add the label `auto-merge-setup-done` to Jira and stop.

### 3. Fork, clone, and create a branch

    gh repo fork red-hat-data-services/rhods-devops-infra --clone
    cd rhods-devops-infra
    git checkout -b <jira-id>

Sparse checkout `src/config` and `.github/workflows`.

### 4. Edit upstream-source-map.yaml

Append a new entry at the end of the file with the repo name, upstream source URL and branch, and destination URL and branch.

### 5. Edit main-release-source-map.yaml

Append a new entry at the end of the file with the repo name and repo URL.

### 6. Edit upstream-auto-merge.yaml

Find the `repositories` input's `options` list and add the repo name as a new item.

### 7. Edit main-release-auto-merge.yaml

Find the `repositories` input's `options` list and add the repo name as a new item.

### 8. Commit, push, and create PR

    git add src/config/upstream-source-map.yaml src/config/main-release-source-map.yaml \
            .github/workflows/upstream-auto-merge.yaml .github/workflows/main-release-auto-merge.yaml
    git commit -m "Configure auto-merge for <repo-name>"
    git push -u origin <jira-id>

    gh pr create \
      --title "Configure auto-merge for <repo-name>" \
      --body "Sets up auto-merge for '<repo-name>' in rhods-devops-infra.

    Jira: <jira-url>"

### 9. Update Jira

Add the label `auto-merge-pr-raised` and comment with the PR URL and list of files changed.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Both entries already exist | Expected -- exits cleanly, Jira labelled `auto-merge-setup-done` |
| Config file not found in clone | Verify `RHODS_DEVOPS_INFRA_REPO_URL` points to the correct repo |
| Workflow file not found | Verify the repo structure has not changed |
| Push fails (shallow update) | Run `git fetch --unshallow origin` then retry |

## Automation

The script `scripts/setup-auto-merge.sh` automates this playbook end-to-end.

    ./scripts/setup-auto-merge.sh [--jira-url <url>]

Beyond the manual steps above, the script also:
- Downloads `component_onboarding_details.yaml` from Jira automatically
- Detects the upstream repo URL automatically
- Performs a fast-path check via GitHub API before cloning
- Inserts workflow options using structured YAML editing
- Retries PR creation up to 3 times with error classification
- Adds Jira labels and comments at each milestone

## Related playbooks

- [enable-renovate-on-rhoai-component-repo](enable-renovate-on-rhoai-component-repo.md) -- Renovate setup (often done in parallel)
- [integrate-component-with-bundle](integrate-component-with-bundle.md) -- prerequisite bundle integration
