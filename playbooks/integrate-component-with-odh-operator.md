# Integrate Component with ODH Operator

Adds operator component entries to the ODH or RHOAI operator repository by updating `build/manifests-config.yaml`.

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
File: `build/manifests-config.yaml`

**For RHOAI components:**
Repository: `https://github.com/red-hat-data-services/rhods-operator`
File: `build/manifests-config.yaml`

You'll be adding a component entry under the `map:` key in `build/manifests-config.yaml` that configures how the operator copies manifests from the component's upstream repository.

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

### 4. Add component entry to manifests-config.yaml

Edit `build/manifests-config.yaml` to add the component under the `map:` key. Follow the existing pattern — each entry maps a component name to its upstream repo and manifest source path.

Check if the component already exists first:

    grep "^  my-component:" build/manifests-config.yaml

If not present, add an entry following the existing pattern in the file.

### 5. Commit and push

Stage the modified config, commit, and push to your fork.

    git add build/manifests-config.yaml
    git commit -m "Add my-component to manifests-config.yaml"
    git push origin RHOAIENG-1234

### 6. Create pull request

Raise a PR targeting the upstream repository's main branch.

    gh pr create --title "Add my-component to manifests-config.yaml" \
      --body "Adds my-component to the operator manifests config.

    **Component name:** my-component
    **Jira:** <jira-url>

    - \`build/manifests-config.yaml\` — added my-component entry under map:" \
      --base main \
      --head $(git config user.name):RHOAIENG-1234

### 7. Update Jira

Add label `operator-pr-raised` (RHOAI) or `odh-operator-pr-raised` (ODH) and comment with PR URL and component details. If the component has `is_operator=false`, add label `operator-changes-not-needed` instead and skip the PR.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Fork fails | Check GITHUB_TOKEN has repo scope |
| component_onboarding_details.yaml not found | Run /create-component-onboarding-jira first |
| is_operator field is false | This step only applies to operator components |
| manifests-config.yaml format unclear | Review existing entries under `map:` in `build/manifests-config.yaml` |
| PR creation fails | Check GITHUB_TOKEN permissions and that branch was pushed |

## Automation

The script `scripts/integrate-component-with-odh-operator.sh` automates this playbook end-to-end.

    ./scripts/integrate-component-with-odh-operator.sh <jira-url>

Beyond the manual steps above, the script also:
- Automatically downloads component_onboarding_details.yaml from Jira
- Validates that `is_operator: true` before proceeding
- Determines the correct operator repository based on product_context
- Uses `edit_yaml.py insert-map-key` for structured YAML editing of manifests-config.yaml
- Handles idempotency (skips if entries already exist)
- Updates Jira with labels and structured comments

## Related playbooks

- [validate-component-onboarding-jira](validate-component-onboarding-jira.md) - Must validate before this step
- [integrate-component-with-bundle](integrate-component-with-bundle.md) - Parallel bundle integration step
