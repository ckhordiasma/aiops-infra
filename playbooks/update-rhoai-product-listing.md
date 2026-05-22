# Update RHOAI Product Listing

Adds the component's registry path to the RHOAI product listing in pyxis-repo-configs.

**Applies to:** RHOAI
**Pipeline step:** 7 (RHOAI)

## When to use

After the delivery repository is created and you need to make the component visible in the RHOAI product catalog. This is the final step in RHOAI component onboarding.

## Prerequisites

- Red Hat VPN active (pyxis-repo-configs is on internal GitLab)
- GitLab credentials: GITLAB_USER, GITLAB_TOKEN (scopes: api, write_repository)
- Tools: uv, git, curl
- Jira ticket with component_onboarding_details.yaml attached
- Optional Jira credentials: JIRA_USER_EMAIL, JIRA_API_TOKEN

## What you'll be changing

Repository: `https://gitlab.cee.redhat.com/releng/pyxis-repo-configs`
File: `product-listings/rhoai/rhoai.yaml`

You'll be adding a single line to the repositories array:
```yaml
repositories:
  - registry.access.redhat.com/rhoai/my-component-rhel9
```

## Steps

### 1. Verify entry doesn't already exist

Check the current state of product-listings/rhoai/rhoai.yaml to avoid duplicates.

    curl -H "Authorization: Bearer $GITLAB_TOKEN" \
      "https://gitlab.cee.redhat.com/api/v4/projects/releng%2Fpyxis-repo-configs/repository/files/product-listings%2Frhoai%2Frhoai.yaml/raw?ref=main" | \
      grep -F "registry.access.redhat.com/rhoai/<component>-rhel9"

If found, the entry already exists.

### 2. Clone pyxis-repo-configs

Clone the repository and create a feature branch.

    git clone https://gitlab.cee.redhat.com/releng/pyxis-repo-configs
    cd pyxis-repo-configs
    git checkout -b RHOAIENG-1234

You can use sparse checkout to only fetch the relevant file:

    git clone --filter=blob:none --sparse https://gitlab.cee.redhat.com/releng/pyxis-repo-configs
    cd pyxis-repo-configs
    git sparse-checkout set product-listings/rhoai/rhoai.yaml

### 3. Parse component name from YAML

Extract the component_name field from component_onboarding_details.yaml. The registry path follows the pattern:

    registry.access.redhat.com/rhoai/<component-name>-rhel9

### 4. Add entry to product-listings/rhoai/rhoai.yaml

Open the file and append the registry path to the repositories list. Ensure proper YAML list syntax with a leading dash and space:

```yaml
repositories:
  - registry.access.redhat.com/rhoai/existing-component-rhel9
  - registry.access.redhat.com/rhoai/my-component-rhel9
```

### 5. Commit and push

Stage the modified file, commit, and push to your branch.

    git add product-listings/rhoai/rhoai.yaml
    git commit -m "Add my-component to RHOAI product listing"
    git push origin RHOAIENG-1234

### 6. Create merge request

Raise an MR targeting the main branch.

    glab mr create --title "Add my-component to RHOAI product listing" \
      --description "Adds a new registry path entry to product-listings/rhoai/rhoai.yaml.\n\n**Registry path:** registry.access.redhat.com/rhoai/my-component-rhel9\n**Jira:** <jira-url>" \
      --source-branch RHOAIENG-1234 \
      --target-branch main

### 7. Update Jira

Add label `product-listing-mr-raised` and comment with MR URL and registry path.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| VPN connection fails | Connect to Red Hat VPN |
| YAML attachment missing | Run /create-component-onboarding-jira first |
| component_name missing | Ensure YAML has valid component_name field |
| Push rejected (shallow update) | Run `git fetch --unshallow origin` then retry push |
| MR creation fails | Check VPN and GITLAB_TOKEN scopes |

## Automation

The script `scripts/update-rhoai-product-listing.sh` automates this playbook end-to-end.

    ./scripts/update-rhoai-product-listing.sh [<jira-url>]

Beyond the manual steps above, the script also:
- Downloads component_onboarding_details.yaml from Jira automatically
- Computes the full registry path from component name
- Handles idempotency checks (skips if entry already exists)
- Uses sparse checkout for faster cloning
- Retries MR creation up to 3 times on transient failures
- Updates Jira with labels and structured comments

## Related playbooks

- [create-rhoai-delivery-repo](create-rhoai-delivery-repo.md) - Must complete before this step
- [onboard-component-to-konflux-release-data](onboard-component-to-konflux-release-data.md) - Parallel step
