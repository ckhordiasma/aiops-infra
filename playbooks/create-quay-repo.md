# Create Quay Repository

Creates a new Quay repository for an ODH/RHOAI component via GitOps merge request to app-interface.

**Applies to:** Both (ODH and RHOAI)
**Pipeline step:** 1

## When to use

After creating a component onboarding Jira ticket. This sets up the container registry before you can build and push images.

## Prerequisites

- Red Hat VPN active (app-interface is on internal GitLab)
- GitLab credentials: GITLAB_USER, GITLAB_TOKEN (scopes: api, write_repository)
- Tools: uv, skopeo
- Optional Jira credentials if tracking progress: JIRA_USER_EMAIL, JIRA_API_TOKEN

## What you'll be changing

Repository: `https://gitlab.cee.redhat.com/service/app-interface`
File: `data/services/rhoai/quay/<org>.yml` (where <org> is opendatahub, rhoai, or modh)

You'll be adding an entry like:
```yaml
- name: my-component
  description: "My Component container image"
  public: true
```

## Steps

### 1. Check if the Quay repository already exists

Before making changes, verify the repo doesn't already exist.

    skopeo inspect docker://quay.io/<org>/<repo>

If the command succeeds, the repo exists and you can skip to Jira updates.

### 2. Fork the app-interface repository

Via GitLab UI or use the CLI to fork:

    glab repo fork https://gitlab.cee.redhat.com/service/app-interface

### 3. Clone your fork and create a feature branch

Clone the repository and create a branch (named after your Jira ticket if applicable).

    git clone https://gitlab.cee.redhat.com/<your-username>/app-interface
    cd app-interface
    git checkout -b RHOAIENG-1234

### 4. Edit the appropriate YAML file

Determine which file to edit based on the org:
- opendatahub → `data/services/rhoai/quay/opendatahub.yml`
- rhoai → `data/services/rhoai/quay/rhoai.yml`
- modh → `data/services/rhoai/quay/modh.yml`

Open the file and append a new entry under the items array:
```yaml
- name: <repo-name>
  description: "<org> <repo> container image"
  public: true  # or false for private repos
```

For RHOAI repos (rhoai org), default visibility is private unless specified otherwise.

### 5. Commit and push your changes

Stage the file, commit with a descriptive message, and push to your fork.

    git add data/services/rhoai/quay/<org>.yml
    git commit -m "Add <repo> to quay <org> config"
    git push origin RHOAIENG-1234

### 6. Create a merge request

Create an MR from your fork to the upstream app-interface repository.

    glab mr create --title "Add <repo> quay repository for <org>" \
      --description "Add quay.io/<org>/<repo> to app-interface GitOps config.\n\nVisibility: <visibility>\nJira: <jira-url or N/A>" \
      --source-branch RHOAIENG-1234 \
      --target-branch master

### 7. Update Jira (if applicable)

Add the label `quay-mr-raised` and post a comment with the MR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| VPN connection fails | Ensure you're connected to Red Hat VPN; app-interface is on internal GitLab |
| Fork creation fails | Check GITLAB_TOKEN has `api` scope |
| Push rejected | Check GITLAB_TOKEN has `write_repository` scope |
| Clone timeout (large repo) | Wait for completion; app-interface can take 30+ minutes to clone |
| MR creation fails | Verify VPN is active and branch exists on fork |

## Automation

The script `scripts/create-quay-repo.sh` automates this playbook end-to-end.

    ./scripts/create-quay-repo.sh quay.io/<org>/<repo> [--jira-url <url>] [--visibility public|private]

Beyond the manual steps above, the script also:
- Automatically resolves visibility based on org (rhoai defaults to private)
- Handles idempotency by checking if the repo already exists
- Uses sparse checkout for faster cloning
- Retries MR creation up to 3 times on transient failures
- Updates Jira with labels and MR URLs

## Related playbooks

- [create-rhoai-delivery-repo](create-rhoai-delivery-repo.md) - Next step after Quay repo is created
- [onboard-component-to-konflux-release-data](onboard-component-to-konflux-release-data.md) - CI/CD setup
