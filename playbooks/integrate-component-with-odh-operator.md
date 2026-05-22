# Integrate Component with ODH Operator

Adds operator component manifests to the ODH or RHOAI operator repository by updating the Makefile.

**Applies to:** ODH / RHOAI / Both
**Pipeline step:** 3 (for operator components only)

## When to use

After an operator component is onboarded to Konflux and you need to integrate it with the operator repository. This only applies to components where `is_operator: true` in the component YAML.

## Prerequisites

- GitHub credentials: GITHUB_USER, GITHUB_TOKEN (scopes: repo, workflow)
- Tools: uv, git, gh
- Jira ticket with component_onboarding_details.yaml attached
- Jira credentials: JIRA_USER_EMAIL, JIRA_API_TOKEN

## What you'll be changing

**For ODH components:**
Repository: `https://github.com/opendatahub-io/opendatahub-operator`
File: `Makefile`

**For RHOAI components:**
Repository: `https://github.com/red-hat-data-services/rhods-operator`
File: `Makefile`

You'll be adding manifest copy entries to the Makefile that copy operator manifests from the component's upstream repository into the operator's manifest directory.

## Steps

### 1. Determine the target operator repository

Based on product_context in the component YAML:
- ODH → `opendatahub-io/opendatahub-operator`
- RHOAI → `red-hat-data-services/rhods-operator`

### 2. Fork and clone the repository

Fork the target repository to your GitHub account and clone it.

    gh repo fork opendatahub-io/opendatahub-operator --clone
    cd opendatahub-operator
    git checkout -b RHOAIENG-1234

Or for RHOAI:

    gh repo fork red-hat-data-services/rhods-operator --clone
    cd rhods-operator
    git checkout -b RHOAIENG-1234

### 3. Parse component details from YAML

Extract the required fields from component_onboarding_details.yaml:
- `component_name`: The component identifier
- `repo_url`: The upstream GitHub repository
- `repo_branch`: The branch to copy manifests from
- `manifests_path`: The path within the repo where manifests are located

### 4. Add Makefile entries

Edit the Makefile to add manifest copy commands. Find the section where manifests are copied and add entries following the existing pattern.

Example entry:

```makefile
# Copy my-component manifests
cp -r ../my-component/manifests/* manifests/my-component/
```

The exact format depends on the operator repository's structure. Review existing entries as a guide.

### 5. Commit and push

Stage the modified Makefile, commit, and push to your fork.

    git add Makefile
    git commit -m "Add my-component manifest copy entries"
    git push origin RHOAIENG-1234

### 6. Create pull request

Raise a PR targeting the upstream repository's main branch.

    gh pr create --title "Add my-component to operator manifests" \
      --body "Adds manifest copy entries for my-component.\n\n**Component name:** my-component\n**Manifests path:** manifests/my-component\n**Jira:** <jira-url>" \
      --base main \
      --head $(git config user.name):RHOAIENG-1234

### 7. Update Jira

Add label `operator-integration-pr-raised` and comment with PR URL and component details.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Fork fails | Check GITHUB_TOKEN has repo scope |
| component_onboarding_details.yaml not found | Run /create-component-onboarding-jira first |
| is_operator field is false | This step only applies to operator components |
| Makefile format unclear | Review existing entries in the Makefile for patterns |
| PR creation fails | Check GITHUB_TOKEN permissions and that branch was pushed |

## Automation

The script `scripts/integrate-component-with-odh-operator.sh` automates this playbook end-to-end.

    ./scripts/integrate-component-with-odh-operator.sh <jira-url>

Beyond the manual steps above, the script also:
- Automatically downloads component_onboarding_details.yaml from Jira
- Validates that `is_operator: true` before proceeding
- Determines the correct operator repository based on product_context
- Generates appropriate Makefile entries following repository conventions
- Handles idempotency (skips if entries already exist)
- Updates Jira with labels and structured comments

## Related playbooks

- [validate-component-onboarding-jira](validate-component-onboarding-jira.md) - Must validate before this step
- [integrate-component-with-bundle](integrate-component-with-bundle.md) - Parallel bundle integration step
