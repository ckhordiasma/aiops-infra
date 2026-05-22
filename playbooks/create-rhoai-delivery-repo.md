# Create RHOAI Delivery Repository

Creates an RHOAI delivery repository in the Red Hat container registry by adding an entry to pyxis-repo-configs.

**Applies to:** RHOAI
**Pipeline step:** 2 (RHOAI)

## When to use

After the component Quay repository exists and you're ready to configure delivery to the Red Hat container registry. This is an RHOAI-only step.

## Prerequisites

- Red Hat VPN active (pyxis-repo-configs is on internal GitLab)
- GitLab credentials: GITLAB_USER, GITLAB_TOKEN (scopes: api, write_repository)
- Tools: uv, git, curl
- Jira ticket with component_onboarding_details.yaml attached (created by /create-component-onboarding-jira)
- Optional Jira credentials: JIRA_USER_EMAIL, JIRA_API_TOKEN

## What you'll be changing

Repository: `https://gitlab.cee.redhat.com/releng/pyxis-repo-configs`
File: `products/rhoai/rhoai.yaml`

You'll be adding an entry like:
```yaml
- repository: rhoai/my-component-rhel9
  content_stream_tags: ['rhoai-3.4-rhel-9']
  release_category: Generally Available
  display_name: My Component
  short_description: "Short component description"
  long_description: "Longer component description"
```

## Steps

### 1. Verify delivery repo doesn't already exist

Check the current state of products/rhoai/rhoai.yaml to avoid duplicate entries.

    curl -H "Authorization: Bearer $GITLAB_TOKEN" \
      "https://gitlab.cee.redhat.com/api/v4/projects/releng%2Fpyxis-repo-configs/repository/files/products%2Frhoai%2Frhoai.yaml/raw?ref=main" | \
      grep -F "repository: rhoai/<component>-rhel9"

If found, the repo already exists.

### 2. Clone pyxis-repo-configs

Clone the repository and create a feature branch.

    git clone https://gitlab.cee.redhat.com/releng/pyxis-repo-configs
    cd pyxis-repo-configs
    git checkout -b RHOAIENG-1234

You can use sparse checkout to only fetch the relevant file:

    git clone --filter=blob:none --sparse https://gitlab.cee.redhat.com/releng/pyxis-repo-configs
    cd pyxis-repo-configs
    git sparse-checkout set products/rhoai/rhoai.yaml

### 3. Parse component details from YAML

Extract values from component_onboarding_details.yaml:
- component_name
- target_rhoai_version (e.g., "3.4" or "3.4-ea-2")
- short_description
- long_description
- release_category

Compute the repository name and content stream tag from target_rhoai_version. Version "3.4" becomes repository "rhoai/<component>-rhel9" with tag "rhoai-3.4-rhel-9".

### 4. Add entry to products/rhoai/rhoai.yaml

Open the file and append a new delivery repository entry:
```yaml
- repository: rhoai/<component>-rhel9
  content_stream_tags:
    - rhoai-3.4-rhel-9
  release_category: Generally Available
  display_name: My Component
  short_description: "Component short description"
  long_description: "Component detailed description"
```

Ensure required fields are present: repository, content_stream_tags, release_category, display_name, short_description, long_description.

### 5. Commit and push

Stage the modified file, commit, and push to your branch.

    git add products/rhoai/rhoai.yaml
    git commit -m "Add rhoai/<component>-rhel9 delivery repository for <component>"
    git push origin RHOAIENG-1234

### 6. Create merge request

Raise an MR targeting the main branch.

    glab mr create --title "Add rhoai/<component>-rhel9 delivery repository for <component>" \
      --description "Adds a new delivery repository entry to products/rhoai/rhoai.yaml.\n\n**Repository:** rhoai/<component>-rhel9\n**Content stream tag:** rhoai-3.4-rhel-9\n**Jira:** <jira-url>" \
      --source-branch RHOAIENG-1234 \
      --target-branch main

### 7. Update Jira

Add label `delivery-repo-mr-raised` and comment with MR URL and repository details.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| VPN connection fails | Connect to Red Hat VPN |
| YAML attachment missing | Run /create-component-onboarding-jira first to create the YAML |
| target_rhoai_version missing/invalid | Ensure YAML has valid version field (e.g., "3.4" or "3.4-ea-2") |
| Push rejected (shallow update) | Run `git fetch --unshallow origin` then retry push |
| MR creation fails | Check VPN and GITLAB_TOKEN scopes |

## Automation

The script `scripts/create-rhoai-delivery-repo.sh` automates this playbook end-to-end.

    ./scripts/create-rhoai-delivery-repo.sh [<jira-url>]

Beyond the manual steps above, the script also:
- Downloads component_onboarding_details.yaml from Jira automatically
- Parses version strings and computes repository names and tags
- Handles idempotency checks (skips if entry already exists)
- Uses sparse checkout for faster cloning
- Retries MR creation up to 3 times on transient failures
- Derives display name by title-casing component name with acronym capitalization
- Updates Jira with labels and structured comments

## Related playbooks

- [create-quay-repo](create-quay-repo.md) - Must complete before this step
- [onboard-component-to-konflux-release-data](onboard-component-to-konflux-release-data.md) - Next step
- [update-rhoai-product-listing](update-rhoai-product-listing.md) - Final step
