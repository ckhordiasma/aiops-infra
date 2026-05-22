# Create Quay Repository

Creates a new Quay repository for an ODH component by raising a merge request to the `app-interface` GitLab repository (GitOps-driven). The Quay repo is automatically provisioned when the MR is merged.

**Applies to:** Both (ODH and RHOAI)
**Pipeline step:** 2

## When to use

Run this after the Jira onboarding ticket has been created (with `component_onboarding_details.yaml` attached). This step creates the container image repository on Quay where the component's images will be pushed.

## Prerequisites

You need the following before starting:

- **GitLab credentials** -- `GITLAB_USER` and `GITLAB_TOKEN` (with `api` and `write_repository` scopes) for Red Hat's internal GitLab at `gitlab.cee.redhat.com`.
- **Jira credentials** (if tracking via Jira) -- `JIRA_USER_EMAIL` and `JIRA_API_TOKEN`.
- **Tools** -- `uv` (Python runner), `skopeo` (container image inspection).
- **VPN** -- Red Hat VPN must be active to access `gitlab.cee.redhat.com`.

## What you'll be changing

**Repository:** `app-interface` on `gitlab.cee.redhat.com/service/app-interface`

**File path** depends on the Quay organization:

| Quay org | File path |
|----------|-----------|
| `opendatahub` | `data/services/rhoai/quay/opendatahub.yml` |
| `rhoai` | `data/services/rhoai/quay/rhoai.yml` |
| `modh` | `data/services/rhoai/quay/modh.yml` |

You are appending an entry to the `items` array in the YAML file:

```yaml
- name: my-new-component
  description: "my-new-component container image"
  public: true
```

## Steps

### 1. Check if the Quay repo already exists

Before doing any work, verify whether the Quay repository already exists:

    skopeo inspect docker://quay.io/<org>/<repo>

If the repo already exists, no further action is needed. Update the Jira ticket with label `quay-repo-created` and a comment noting it already exists.

### 2. Fork the app-interface repository

Fork the `app-interface` repo on GitLab. You can do this via the GitLab web UI or programmatically:

    glab repo fork service/app-interface --remote=false

### 3. Clone your fork and create a branch

Clone your fork and set up a working branch. Note: `app-interface` is a large repository and can take a long time to clone (up to 45 minutes).

    git clone https://gitlab.cee.redhat.com/<your-username>/app-interface
    cd app-interface
    git checkout -b <JIRA-ID>

### 4. Edit the Quay config YAML

Open the appropriate YAML file (see table above) and add the new repository entry to the `items` array. For RHOAI components, use the `short_description` from the onboarding YAML; for ODH, use `"<org> <repo> container image"`.

For a public repo:
```yaml
- name: <repo>
  description: "<description>"
  public: true
```

For a private repo (default for `rhoai` org):
```yaml
- name: <repo>
  description: "<description>"
  public: false
```

### 5. Commit, push, and raise a merge request

Commit the change and push to your fork:

    git add data/services/rhoai/quay/<org>.yml
    git commit -m "Add <repo> to quay <org> config"
    git push origin <JIRA-ID>

Then create the merge request targeting the `master` branch of `app-interface`:

    glab mr create \
      --source-branch "<JIRA-ID>" \
      --target-branch "master" \
      --title "Add <repo> quay repository for <org>" \
      --description "Add quay.io/<org>/<repo> to app-interface GitOps config.

    Visibility: <public|private>
    Jira: <jira-url or N/A>"

### 6. Update Jira

Add the label `quay-mr-raised` to the Jira ticket and comment with the MR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `skopeo` not installed | `brew install skopeo` (macOS) or `sudo dnf install skopeo` (RHEL/Fedora) |
| VPN not active | Connect to Red Hat VPN; required for GitLab access |
| Fork creation fails | Verify `GITLAB_TOKEN` has `api` scope |
| Clone times out | Check VPN stability; `app-interface` is very large |
| Push fails | Verify `GITLAB_TOKEN` has `write_repository` scope |
| MR creation fails | Check VPN; verify branch was pushed; inspect error details |

## Automation

The script `scripts/create-quay-repo.sh` automates this playbook end-to-end.

    ./scripts/create-quay-repo.sh <org>/<repo> [--jira-url <url>] [--visibility public|private]

Beyond the manual steps above, the script also:
- Accepts `quay.io/<org>/<repo>` or `<org>/<repo>` format and normalizes automatically
- Defaults visibility to `private` for `rhoai` org, `public` otherwise
- Wraps the clone in a 45-minute timeout to handle large repo fetches
- Retries MR creation up to 3 times with error classification
- Supports `--existing-mr-url` for idempotent re-runs
- Updates Jira labels and comments throughout the process

## Related playbooks

- [create-rhoai-delivery-repo](create-rhoai-delivery-repo.md) -- downstream step for RHOAI components
- [update-rhoai-product-listing](update-rhoai-product-listing.md) -- adds registry path to product listing
