# Integrate Component with Bundle

Adds component image references to the ODH or RHOAI build config bundle Dockerfile.

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
File: `bundle/Dockerfile`

**For RHOAI components:**
Repository: `https://github.com/red-hat-data-services/RHOAI-Build-Config`
File: `bundle/Dockerfile`

You'll be adding LABEL entries to the bundle Dockerfile that reference the component's container image and metadata.

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

### 5. Add bundle Dockerfile entries

Edit `bundle/Dockerfile` to add LABEL entries for the component. Follow the existing pattern in the file.

Example entries:

```dockerfile
LABEL com.redhat.component.my-component.image="quay.io/rhoai/my-component:v2.15"
LABEL com.redhat.component.my-component.source.git.url="https://github.com/org/my-component"
LABEL com.redhat.component.my-component.source.git.ref="rhoai-2.15"
```

### 6. Commit and push

Stage the modified Dockerfile, commit, and push to your fork.

    git add bundle/Dockerfile
    git commit -m "Add my-component to bundle manifest"
    git push origin RHOAIENG-1234

### 7. Create pull request

Raise a PR targeting the upstream repository's main branch.

    gh pr create --title "Add my-component to bundle manifest" \
      --body "Adds bundle Dockerfile entries for my-component.\n\n**Component name:** my-component\n**Image:** quay.io/rhoai/my-component:v2.15\n**Jira:** <jira-url>" \
      --base main \
      --head $(git config user.name):RHOAIENG-1234

### 8. Update Jira

Add label `bundle-integration-pr-raised` and comment with PR URL and bundle image details.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Fork fails | Check GITHUB_TOKEN has repo scope |
| component_onboarding_details.yaml not found | Run /create-component-onboarding-jira first |
| Dockerfile format unclear | Review existing LABEL entries in bundle/Dockerfile |
| Image reference unknown | Check the component's Konflux configuration or Quay repository |
| PR creation fails | Check GITHUB_TOKEN permissions and that branch was pushed |

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
