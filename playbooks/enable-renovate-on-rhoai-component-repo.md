# Enable Renovate on RHOAI Component Repo

Registers a new RHOAI component repository in the Renovate configuration to enable automatic dependency updates.

**Applies to:** RHOAI  
**Pipeline step:** 9 (RHOAI)

## When to use

Use this after creating the component onboarding Jira ticket and YAML file. Renovate will keep the component's dependencies up to date once the PR is merged.

## Prerequisites

Tools and credentials needed:
- `uv` Python runner (install: `curl -LsSf https://astral.sh/uv/install.sh | sh`)
- `git`, `curl`
- GitHub personal access token with `repo` scope (set as `GITHUB_TOKEN`)
- GitHub username (set as `GITHUB_USER`)
- Jira API token and email (when updating Jira tickets)
- VPN: Not required

## What you'll be changing

Repo: `red-hat-data-services/konflux-central` (or custom fork via `RHOAI_KONFLUX_CENTRAL_REPO_URL`)  
File: `config.yaml` on the `main` branch

You'll add an entry to the `sync-repositories` array in the first distribution group:

```yaml
- renovate-config: "renovate/default-renovate-distribution.json"
  sync-repositories:
  - name: "red-hat-data-services/rhods-operator"
  - name: "red-hat-data-services/<your-repo-name>"  # NEW
```

## Steps

### 1. Fork and clone the rhoai-konflux-central repository

Fork the repository in the GitHub web interface, then clone your fork:

    gh repo fork red-hat-data-services/konflux-central --clone
    cd konflux-central
    git checkout -b <jira-id>

### 2. Add the component repository to config.yaml

Edit `config.yaml` and add your repository to the `sync-repositories` list under the first distribution group (the one with `renovate-config: "renovate/default-renovate-distribution.json"`).

Example entry:

    - name: "red-hat-data-services/my-component"

### 3. Commit and push your changes

Stage, commit, and push the modified file:

    git add config.yaml
    git commit -m "Enable Renovate for <component-name>"
    git push origin <jira-id>

### 4. Create a pull request

Open a pull request targeting the `main` branch:

    gh pr create --title "Enable Renovate for <component-name>" \
      --body "Adds <repo-name> to the default Renovate distribution in config.yaml."

### 5. Update the Jira ticket

Add the label `renovate-pr-raised` and comment with the PR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Entry already exists in config.yaml | No action needed — Renovate is already configured |
| GitHub API returns 401/403 | Check `GITHUB_TOKEN` has `repo` scope and write access |
| Shallow clone push rejected | Run `git fetch --unshallow origin` then retry push |

## Automation

The script `scripts/enable-renovate-on-rhoai-component-repo.sh` automates this playbook end-to-end.

    ./scripts/enable-renovate-on-rhoai-component-repo.sh [--jira-url <url>]

Beyond the manual steps above, the script also:
- Checks for existing entries before cloning (fast-path exit)
- Automatically resolves repo URLs from environment overrides
- Retries PR creation up to 3 times on transient failures
- Updates Jira with labels and comments

## Related playbooks

- [create-component-onboarding-jira](create-component-onboarding-jira.md) — prerequisite
- [add-component-to-rhoai-konflux-central](add-component-to-rhoai-konflux-central.md) — downstream step
