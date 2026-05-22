# Update RHOAI Product Listing

Adds the new component's registry path to the RHOAI product listing in `pyxis-repo-configs` by appending an entry to the `repositories` array in `product-listings/rhoai/rhoai.yaml` and raising a GitLab merge request.

**Applies to:** RHOAI
**Pipeline step:** 7

## When to use

Run this after the delivery repository has been created and the Konflux release data MR has been merged. The Jira ticket must have `component_onboarding_details.yaml` attached. This step adds the component to the RHOAI product listing so it can be published through the Red Hat container registry.

## Prerequisites

You need the following before starting:

- **GitLab credentials** -- `GITLAB_USER` and `GITLAB_TOKEN` (with `api` and `write_repository` scopes) for Red Hat's internal GitLab at `gitlab.cee.redhat.com`.
- **Jira credentials** (if tracking via Jira) -- `JIRA_USER_EMAIL` and `JIRA_API_TOKEN`.
- **Tools** -- `uv` (Python runner), `git`, `curl`.
- **VPN** -- Red Hat VPN must be active to access `gitlab.cee.redhat.com`.

## What you'll be changing

**Repository:** `pyxis-repo-configs` on `gitlab.cee.redhat.com/releng/pyxis-repo-configs`

**File:** `product-listings/rhoai/rhoai.yaml`

You are appending a single line to the `repositories` array:

```yaml
repositories:
  # ... existing entries ...
  - registry.access.redhat.com/rhoai/<component-name>-rhel9
```

## Steps

### 1. Gather component details

Download `component_onboarding_details.yaml` from the Jira ticket and extract `component_name`. The registry path to add is:

    registry.access.redhat.com/rhoai/<component_name>-rhel9

### 2. Check if the product listing entry already exists

Fetch the current `product-listings/rhoai/rhoai.yaml` from the main branch and check for an existing entry:

    curl -sk -H "Authorization: Bearer $GITLAB_TOKEN" \
      "https://gitlab.cee.redhat.com/api/v4/projects/releng%2Fpyxis-repo-configs/repository/files/product-listings%2Frhoai%2Frhoai.yaml/raw?ref=main" \
      -o /tmp/product-listing.yaml

    grep -F "registry.access.redhat.com/rhoai/<component_name>-rhel9" /tmp/product-listing.yaml

If the entry already exists, add Jira label `product-listing-exists` and comment that no changes are needed, then stop.

### 3. Clone pyxis-repo-configs and create a branch

Clone the repository using sparse checkout for just the product listing file:

    git clone --filter=blob:none --sparse https://gitlab.cee.redhat.com/releng/pyxis-repo-configs.git
    cd pyxis-repo-configs
    git sparse-checkout set product-listings/rhoai/rhoai.yaml
    git checkout -b <JIRA-ID>

### 4. Add the product listing entry

Edit `product-listings/rhoai/rhoai.yaml` and append the new registry path to the `repositories` array:

```yaml
  - registry.access.redhat.com/rhoai/<component_name>-rhel9
```

Verify the entry was added by searching for it in the file.

### 5. Commit, push, and raise a merge request

    git add product-listings/rhoai/rhoai.yaml
    git commit -m "Add <component_name> to RHOAI product listing"
    git push origin <JIRA-ID>

    glab mr create \
      --source-branch "<JIRA-ID>" \
      --target-branch "main" \
      --title "Add <component_name> to RHOAI product listing" \
      --description "Adds a new registry path entry to product-listings/rhoai/rhoai.yaml.

    Component: <component_name>
    Registry path: registry.access.redhat.com/rhoai/<component_name>-rhel9
    Jira: <jira-url>"

### 6. Update Jira

Add the label `product-listing-mr-raised` to the Jira ticket and comment with the MR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| VPN not active | Connect to Red Hat VPN; required for GitLab access |
| `component_name` missing in YAML | Re-generate the YAML with the onboarding Jira skill |
| Push fails with "shallow update not allowed" | Run `git fetch --unshallow origin` then retry push |
| MR creation fails | Check VPN; verify branch was pushed; check `GITLAB_TOKEN` scopes |
| Product listing entry already exists | Expected -- exits cleanly; Jira labelled `product-listing-exists` |

## Automation

The script `scripts/update-rhoai-product-listing.sh` automates this playbook end-to-end.

    ./scripts/update-rhoai-product-listing.sh [--jira-url <url>]

Beyond the manual steps above, the script also:
- Downloads `component_onboarding_details.yaml` from Jira automatically
- Performs a fast-path API check before cloning
- Handles "shallow update not allowed" errors with automatic unshallow/retry
- Retries MR creation up to 3 times with error classification
- Supports `--existing-mr-url` for idempotent re-runs
- Updates Jira labels and comments throughout the process

## Related playbooks

- [create-rhoai-delivery-repo](create-rhoai-delivery-repo.md) -- prerequisite: delivery repo should be created first
- [create-quay-repo](create-quay-repo.md) -- prerequisite: Quay repo must exist
