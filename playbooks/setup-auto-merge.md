# Setup Auto-Merge

Configures auto-merge for a component's Konflux CI pull requests in the rhods-devops-infra repository.

**Applies to:** RHOAI
**Pipeline step:** 8

## When to use

After a RHOAI component is onboarded to Konflux and you need to enable automatic merging of Konflux-generated pull requests. This configures the auto-merge bot to automatically approve and merge PRs that pass CI checks.

## Prerequisites

- GitHub credentials: GITHUB_USER, GITHUB_TOKEN (scopes: repo, workflow)
- Tools: uv, git, gh
- Optional Jira credentials: JIRA_USER_EMAIL, JIRA_API_TOKEN (for tracking)

## What you'll be changing

Repository: `https://github.com/red-hat-data-services/rhods-devops-infra`
File: `auto-merge-config.yaml` or similar auto-merge configuration file

You'll be adding the component to the auto-merge configuration so that Konflux CI pull requests are automatically merged when tests pass.

## Steps

### 1. Fork and clone rhods-devops-infra

Fork the repository to your GitHub account and clone it.

    gh repo fork red-hat-data-services/rhods-devops-infra --clone
    cd rhods-devops-infra
    git checkout -b setup-auto-merge-my-component

### 2. Locate the auto-merge configuration file

Find the configuration file that controls auto-merge behavior. This is typically:
- `auto-merge-config.yaml`
- `config/auto-merge.yaml`
- Or another YAML/JSON file in the repository

Review existing entries to understand the format.

### 3. Parse component details

If working from a Jira ticket, extract from component_onboarding_details.yaml:
- `component_name`: The component identifier
- `repo_url`: The component's GitHub repository

Otherwise, obtain these values from the user.

### 4. Add component to auto-merge configuration

Edit the configuration file to add an entry for the new component.

Example entry (YAML format):

```yaml
repositories:
  - name: my-component
    owner: red-hat-data-services
    repo: my-component
    auto_merge:
      enabled: true
      required_checks:
        - konflux-ci
        - build-and-test
      merge_method: squash
```

The exact format depends on the configuration file structure. Follow existing patterns.

### 5. Commit and push

Stage the modified configuration file, commit, and push to your fork.

    git add auto-merge-config.yaml
    git commit -m "Enable auto-merge for my-component"
    git push origin setup-auto-merge-my-component

### 6. Create pull request

Raise a PR targeting the main branch.

    gh pr create --title "Enable auto-merge for my-component" \
      --body "Adds auto-merge configuration for my-component.\n\n**Component:** my-component\n**Repository:** red-hat-data-services/my-component\n**Jira:** <jira-url-if-available>" \
      --base main \
      --head $(git config user.name):setup-auto-merge-my-component

### 7. Update Jira (if applicable)

If a Jira ticket is provided, add label `auto-merge-pr-raised` and comment with PR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Fork fails | Check GITHUB_TOKEN has repo scope |
| Configuration file not found | Check repository structure; file name/location may have changed |
| Configuration format unclear | Review existing entries and repository documentation |
| PR creation fails | Check GITHUB_TOKEN permissions and that branch was pushed |
| Auto-merge not working after merge | Verify component repository has required CI checks configured |

## Automation

The script `scripts/setup-auto-merge.sh` automates this playbook end-to-end.

    ./scripts/setup-auto-merge.sh <component-name> [<jira-url>]

Beyond the manual steps above, the script also:
- Automatically downloads component_onboarding_details.yaml from Jira (if URL provided)
- Locates and parses the auto-merge configuration file
- Generates appropriate configuration entries following repository conventions
- Handles idempotency (skips if component already configured)
- Updates Jira with labels and structured comments (if URL provided)
- Validates configuration syntax before committing

## Related playbooks

- [onboard-component-to-konflux-release-data](onboard-component-to-konflux-release-data.md) - Prerequisite Konflux onboarding step
- [update-rhoai-product-listing](update-rhoai-product-listing.md) - Parallel pipeline step
