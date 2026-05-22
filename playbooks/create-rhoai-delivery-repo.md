# Create RHOAI Delivery Repository

Creates a new RHOAI delivery repository in the Red Hat container registry by raising a merge request to the `pyxis-repo-configs` GitLab repository. The repository is provisioned automatically when the MR is merged by Release Engineering's GitOps pipeline.

**Applies to:** RHOAI
**Pipeline step:** 6

## When to use

Run this after the Quay repository has been created and the component has been onboarded to Konflux. The Jira ticket must have `component_onboarding_details.yaml` attached (created by the onboarding Jira skill). This step provisions the delivery repo entry so that built images can be shipped through the Red Hat container registry.

## Prerequisites

You need the following before starting:

- **GitLab credentials** -- `GITLAB_USER` and `GITLAB_TOKEN` (with `api` and `write_repository` scopes) for Red Hat's internal GitLab at `gitlab.cee.redhat.com`.
- **Jira credentials** -- `JIRA_USER_EMAIL` and `JIRA_API_TOKEN` (required when a Jira URL is provided).
- **Tools** -- `uv` (Python runner), `git`, `curl`.
- **VPN** -- Red Hat VPN must be active to access `gitlab.cee.redhat.com`.
- **Jira attachment** -- `component_onboarding_details.yaml` must be attached to the Jira ticket.

## What you'll be changing

**Repository:** `pyxis-repo-configs` on `gitlab.cee.redhat.com/releng/pyxis-repo-configs`

**File:** `products/rhoai/rhoai.yaml`

You are appending a repository entry to the YAML file. The entry looks like:

```yaml
- repository: rhoai/rhoai-my-component-rhel9
  content_stream_tags:
    - 'v3.4-{version}'
  release_categories:
    - Generally Available
  display_data:
    name: My Component
    short_description: "Short description from onboarding YAML"
    long_description: "Long description from onboarding YAML"
```

## Steps

### 1. Gather component details

Download `component_onboarding_details.yaml` from the Jira ticket and extract:
- `component_name` (e.g., `my-component`)
- `target_rhoai_version` (e.g., `3.4`)

From these, derive:
- `REPOSITORY_NAME` -- typically `rhoai/<component_name>-rhel9` (derived by version parsing rules)
- `CONTENT_STREAM_TAG` -- e.g., `v3.4-{version}` (derived from target version)
- `DISPLAY_NAME` -- title-cased component name with hyphens replaced by spaces

### 2. Check if the delivery repo already exists

Fetch the current `products/rhoai/rhoai.yaml` from the main branch and check for an existing entry:

    curl -sk -H "Authorization: Bearer $GITLAB_TOKEN" \
      "https://gitlab.cee.redhat.com/api/v4/projects/releng%2Fpyxis-repo-configs/repository/files/products%2Frhoai%2Frhoai.yaml/raw?ref=main" \
      -o /tmp/rhoai.yaml

    grep -F "repository: <REPOSITORY_NAME>" /tmp/rhoai.yaml

If the entry already exists, add Jira label `delivery-repo-exists` and comment that no changes are needed, then stop.

### 3. Clone pyxis-repo-configs and create a branch

Clone the repository using sparse checkout for just the file you need:

    git clone --filter=blob:none --sparse https://gitlab.cee.redhat.com/releng/pyxis-repo-configs.git
    cd pyxis-repo-configs
    git sparse-checkout set products/rhoai/rhoai.yaml
    git checkout -b <JIRA-ID>

### 4. Add the delivery repo entry

Edit `products/rhoai/rhoai.yaml` and append the new repository entry to the file. Include the repository name, content stream tags, release category, and display data fields.

### 5. Commit, push, and raise a merge request

    git add products/rhoai/rhoai.yaml
    git commit -m "Add <REPOSITORY_NAME> delivery repository for <COMPONENT_NAME>"
    git push origin <JIRA-ID>

    glab mr create \
      --source-branch "<JIRA-ID>" \
      --target-branch "main" \
      --title "Add <REPOSITORY_NAME> delivery repository for <COMPONENT_NAME>" \
      --description "Adds a new delivery repository entry to products/rhoai/rhoai.yaml.

    Repository: <REPOSITORY_NAME>
    Content stream tags: ['<CONTENT_STREAM_TAG>']
    Jira: <jira-url>"

### 6. Update Jira

Add the label `delivery-repo-mr-raised` to the Jira ticket and comment with the MR URL and repository details.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| VPN not active | Connect to Red Hat VPN; required for GitLab access |
| `target_rhoai_version` missing in YAML | Re-generate the YAML with the onboarding Jira skill |
| Push fails with "shallow update not allowed" | Run `git fetch --unshallow origin` then retry push |
| MR creation fails | Check VPN; verify branch was pushed; check `GITLAB_TOKEN` scopes |
| Delivery repo already exists | Expected -- exits cleanly; Jira labelled `delivery-repo-exists` |
| YAML attachment missing on Jira | Run the onboarding Jira skill first to create the YAML |

## Automation

The script `scripts/create-rhoai-delivery-repo.sh` automates this playbook end-to-end.

    ./scripts/create-rhoai-delivery-repo.sh [--jira-url <url>]

Beyond the manual steps above, the script also:
- Downloads `component_onboarding_details.yaml` from Jira automatically
- Derives `REPOSITORY_NAME`, `CONTENT_STREAM_TAG`, and display data from the YAML
- Performs a fast-path API check before cloning
- Handles "shallow update not allowed" errors with automatic unshallow/retry
- Retries MR creation up to 3 times with error classification
- Supports `--existing-mr-url` for idempotent re-runs
- Updates Jira labels and comments throughout the process

## Related playbooks

- [create-quay-repo](create-quay-repo.md) -- prerequisite: Quay repo must exist first
- [update-rhoai-product-listing](update-rhoai-product-listing.md) -- companion step for RHOAI product listing
- [onboard-component-to-konflux-release-data](onboard-component-to-konflux-release-data.md) -- Konflux onboarding
