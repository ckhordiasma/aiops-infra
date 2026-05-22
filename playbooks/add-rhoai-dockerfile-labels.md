# Add RHOAI Dockerfile Labels

Ensures a component Dockerfile contains all seven mandatory RHOAI OCI labels. If any labels are missing or incorrect, clones the component repo, adds the labels, and raises a GitHub PR.

**Applies to:** RHOAI
**Pipeline step:** 7

## When to use

Run this after the component repository exists and has a Dockerfile. This step can run in parallel with other onboarding steps. The labels are required for Red Hat container certification.

## Prerequisites

You need a GitHub account with push access to the component repo, a GitHub personal access token with `repo` scope, and `git`, `curl` installed. If using a Jira URL, you also need `JIRA_USER_EMAIL` and `JIRA_API_TOKEN`.

## What you'll be changing

**Repo:** The component repository specified in `component_onboarding_details.yaml`
**File:** The Dockerfile at the path specified by `context_path` + `dockerfile_path`

The seven mandatory labels and their expected values:

| Label | Expected value |
|-------|----------------|
| `name` | `rhoai/<component-name>-rhel9` |
| `com.redhat.component` | `<component-name>-rhel9` |
| `summary` | `<component-name>` |
| `description` | `<component-name>` |
| `maintainer` | `<component-name>` |
| `io.k8s.display-name` | `<component-name>` |
| `io.k8s.description` | `<component-name>` |

## Steps

### 1. Download and parse the onboarding YAML

Download `component_onboarding_details.yaml` from the Jira ticket. Extract `component_name`, `repo_url`, `context_path`, and `dockerfile_path`. Derive the full Dockerfile path within the repo.

### 2. Check labels via GitHub API (fast path)

Fetch the raw Dockerfile content without cloning:

    curl -s -w "%{http_code}" \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3.raw" \
      "https://api.github.com/repos/<owner>/<repo>/contents/<dockerfile-path>?ref=main" \
      -o /tmp/Dockerfile.check

Parse all `LABEL` instructions. If all seven labels are present with correct values, add the label `dockerfile-labels-present` to Jira and stop -- no PR needed.

### 3. Fork, clone, and create a branch

    gh repo fork <owner>/<repo> --clone
    cd <repo>
    git checkout -b <jira-id>

### 4. Add or correct labels in the Dockerfile

Open the Dockerfile and ensure all seven labels are present after the last `FROM` instruction. Add any missing labels as `LABEL` instructions. If a label has an incorrect value, update it.

### 5. Commit, push, and create PR

    git add <dockerfile-path>
    git commit -m "Add mandatory RHOAI Dockerfile labels for <component-name>"
    git push -u origin <jira-id>

    gh pr create \
      --title "Add mandatory RHOAI Dockerfile labels for <component-name>" \
      --body "Adds the seven mandatory RHOAI OCI labels to the Dockerfile.

    Labels: name, com.redhat.component, summary, description,
            maintainer, io.k8s.display-name, io.k8s.description

    Jira: <jira-url>"

### 6. Update Jira

Add the label `dockerfile-labels-pr-raised` and comment with the PR URL and the list of labels added.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| All labels already correct | Expected -- exits cleanly, Jira labelled `dockerfile-labels-present` |
| Dockerfile not found | Verify `context_path` and `dockerfile_path` in the onboarding YAML |
| Push fails (shallow update) | Run `git fetch --unshallow origin` then retry |
| Multi-stage Dockerfile | Labels should be added after the last `FROM` instruction |

## Automation

The script `scripts/add-rhoai-dockerfile-labels.sh` automates this playbook end-to-end.

    ./scripts/add-rhoai-dockerfile-labels.sh [--jira-url <url>]

Beyond the manual steps above, the script also:
- Downloads `component_onboarding_details.yaml` from Jira automatically
- Performs a fast-path label check via GitHub API before cloning
- Uses a helper script to add/update labels programmatically
- Retries PR creation up to 3 times with error classification
- Adds Jira labels and comments at each milestone

## Related playbooks

- [add-component-to-rhoai-konflux-central](add-component-to-rhoai-konflux-central.md) -- also modifies the component repo
- [integrate-component-with-bundle](integrate-component-with-bundle.md) -- subsequent bundle integration
