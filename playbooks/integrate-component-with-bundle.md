# Integrate Component with Bundle

Adds a component's relatedImages entry to the build config bundle and (for RHOAI) updates the repo mappings and Dockerfile git labels.

**Applies to:** ODH / RHOAI / Both
**Pipeline step:** 4

## When to use

After a component is onboarded to Konflux and you need to integrate it with the build config bundle. This ensures the component's container image is included in the bundle manifest.

## Prerequisites

- GitHub credentials: GITHUB_USER, GITHUB_TOKEN (scopes: repo, workflow)
- Tools: uv, git, gh
- Jira ticket with component_onboarding_details.yaml attached
- Jira credentials: JIRA_USER_EMAIL, JIRA_API_TOKEN

## What you'll be changing

**For ODH components:**
Repository: `https://github.com/opendatahub-io/ODH-Build-Config`
File: `bundle/bundle-patch.yaml` — add a `relatedImages` entry

**For RHOAI components:**
Repository: `https://github.com/red-hat-data-services/RHOAI-Build-Config`
Files:
- `bundle/bundle-patch.yaml` — add a `relatedImages` entry
- `config/build-config.yaml` — add a `repo_mappings` entry
- `bundle/Dockerfile` — add ARG and LABEL entries for git source tracking

## Steps

### 1. Determine the target build config repository

Based on product_context in the component YAML:
- ODH → `opendatahub-io/ODH-Build-Config`
- RHOAI → `red-hat-data-services/RHOAI-Build-Config`

### 2. Fork and clone the repository

Fork the target repository to your GitHub account and clone it.

    gh repo fork opendatahub-io/ODH-Build-Config --clone
    cd ODH-Build-Config
    git checkout -b RHOAIENG-1234

Or for RHOAI:

    gh repo fork red-hat-data-services/RHOAI-Build-Config --clone
    cd RHOAI-Build-Config
    git checkout -b RHOAIENG-1234

### 3. Parse component details from YAML

Extract the required fields from component_onboarding_details.yaml:
- `component_name`: The component identifier
- `repo_url`: The upstream GitHub repository
- `repo_branch`: The branch reference

### 4. Resolve bundle image reference

The bundle image reference typically follows the pattern:
- ODH: `quay.io/opendatahub/<component-name>:latest`
- RHOAI: `quay.io/rhoai/<component-name>:v<version>`

Check the component's Konflux configuration to verify the exact image reference.

### 5. Add relatedImages entry to bundle-patch.yaml

Edit `bundle/bundle-patch.yaml` to add a `relatedImages` entry for the component. Follow the existing pattern in the file — each entry has a `name` and `image` field under `patch.relatedImages`.

Example entry:

```yaml
patch:
  relatedImages:
    # ... existing entries ...
    - name: RELATED_IMAGE_my-component
      image: quay.io/rhoai/my-component-rhel9@sha256:<digest>
```

### 6. (RHOAI only) Update build-config.yaml and Dockerfile

For RHOAI components, also update:

1. `config/build-config.yaml` — add a `repo_mappings` entry under `config.replacements.0.repo_mappings`:

       rhoai/my-component-rhel9: rhoai/my-component-rhel9

2. `bundle/Dockerfile` — add ARG and LABEL entries for git source tracking. Use `update_bundle_dockerfile_git_labels.py` or follow the existing pattern.

### 7. Commit and push

Stage all modified files, commit, and push to your fork.

    # ODH:
    git add bundle/bundle-patch.yaml
    # RHOAI:
    git add bundle/bundle-patch.yaml config/build-config.yaml bundle/Dockerfile

    git commit -m "Add my-component to bundle-patch.yaml"
    git push origin RHOAIENG-1234

### 8. Create pull request

Raise a PR targeting the upstream repository's main or version-specific branch.

    gh pr create --title "Add my-component to bundle-patch.yaml" \
      --body "Adds my-component to the bundle relatedImages.

    **Component name:** my-component
    **Jira:** <jira-url>

    - \`bundle/bundle-patch.yaml\` — added RELATED_IMAGE_my-component" \
      --base main \
      --head $(git config user.name):RHOAIENG-1234

### 9. Update Jira

Add label `bundle-pr-raised` and comment with PR URL and bundle image details.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Fork fails | Check GITHUB_TOKEN has repo scope |
| component_onboarding_details.yaml not found | Run /create-component-onboarding-jira first |
| bundle-patch.yaml format unclear | Review existing `relatedImages` entries in `bundle/bundle-patch.yaml` |
| Image reference unknown | Check the component's Konflux configuration or Quay repository |
| PR creation fails | Check GITHUB_TOKEN permissions and that branch was pushed |
| build-config.yaml not found (RHOAI) | Ensure you used `--sparse-files "bundle config"` when cloning |

## Automation

The script `scripts/integrate-component-with-bundle.sh` automates this playbook end-to-end.

    ./scripts/integrate-component-with-bundle.sh <jira-url>

Beyond the manual steps above, the script also:
- Automatically downloads component_onboarding_details.yaml from Jira
- Determines the correct build config repository based on product_context
- Resolves the bundle image reference from Konflux or Quay
- Generates appropriate LABEL entries following repository conventions
- Handles idempotency (skips if entries already exist)
- Updates Jira with labels and structured comments
- Validates git label format and completeness

## Related playbooks

- [validate-component-onboarding-jira](validate-component-onboarding-jira.md) - Must validate before this step
- [integrate-component-with-odh-operator](integrate-component-with-odh-operator.md) - Parallel operator integration step (for operators only)
