# Add RHOAI Dockerfile Labels

Checks a component Dockerfile for mandatory RHOAI labels, and if any are missing or incorrect, clones the component repo, adds the labels, and raises a GitHub PR.

**Applies to:** RHOAI
**Pipeline step:** 11

## When to use

As part of RHOAI component onboarding after the component is integrated with Konflux. This step ensures the Dockerfile contains all required metadata labels for RHOAI compliance.

## Prerequisites

**Tools:**
- `git` — version control
- `gh` CLI — GitHub operations (or use web UI for PR creation)
- `curl` — fetch Dockerfile from GitHub
- `uv` Python runner — for helper scripts

**Credentials:**
- `GITHUB_USER` — GitHub username
- `GITHUB_TOKEN` — GitHub personal access token with `repo` scope

**Optional:**
- `JIRA_USER_EMAIL`, `JIRA_API_TOKEN` — for Jira tracking

## What you'll be changing

**Repository:** The component's source repository (e.g., `opendatahub-io/<component-name>`)

**Files modified:**
- `<context-path>/<dockerfile-path>` — the Dockerfile to add labels to

**Branch:** Creates a new feature branch from the component's repo branch (e.g., `rhoai-3.5`)

## Steps

### 1. Fetch the Dockerfile from the component repository

Construct the raw GitHub URL for the Dockerfile using the component details from the onboarding YAML:

    REPO_URL=<component-repo-url>
    REPO_BRANCH=<repo-branch>
    CONTEXT_PATH=<context-path>
    DOCKERFILE_PATH=<dockerfile-path>

    RAW_BASE="${REPO_URL/github.com/raw.githubusercontent.com}"
    DOCKERFILE_URL="$RAW_BASE/$REPO_BRANCH/$CONTEXT_PATH/$DOCKERFILE_PATH"

Download the Dockerfile:

    curl -sf "$DOCKERFILE_URL" -o Dockerfile

### 2. Check for mandatory RHOAI labels

The following 7 labels are mandatory for RHOAI Dockerfiles:

1. `name`
2. `com.redhat.component`
3. `summary`
4. `description`
5. `maintainer`
6. `io.k8s.display-name`
7. `io.k8s.description`

Check each label in the Dockerfile:

    grep '^LABEL name=' Dockerfile
    grep '^LABEL com.redhat.component=' Dockerfile
    grep '^LABEL summary=' Dockerfile
    grep '^LABEL description=' Dockerfile
    grep '^LABEL maintainer=' Dockerfile
    grep '^LABEL io.k8s.display-name=' Dockerfile
    grep '^LABEL io.k8s.description=' Dockerfile

If all 7 labels are present and correctly formatted, no changes are needed. Exit cleanly.

### 3. Fork and clone the component repository

If labels are missing or incorrect, fork the component repository.

    gh repo fork <owner>/<repo> --clone

If you already have a fork, clone it instead.

    git clone https://github.com/$GITHUB_USER/<repo>
    cd <repo>

Add the upstream remote if not already present.

    git remote add upstream <component-repo-url>

### 4. Create a feature branch

Fetch the latest changes and create a new branch from the repo branch.

    git fetch upstream
    git checkout -b add-rhoai-labels upstream/<repo-branch>

### 5. Add missing labels to the Dockerfile

Navigate to the Dockerfile location:

    cd <context-path>

Edit the Dockerfile to add the missing LABEL instructions. Add them after the `FROM` instruction(s), typically at the top of the file.

Example labels:

```dockerfile
LABEL name="rhoai/<component-name>" \
      com.redhat.component="<component-name>" \
      summary="<Short description>" \
      description="<Longer description>" \
      maintainer="<team-email>" \
      io.k8s.display-name="<Display Name>" \
      io.k8s.description="<Description for Kubernetes>"
```

### 6. Commit and push changes

Stage the Dockerfile.

    git add <context-path>/<dockerfile-path>

Commit the changes.

    git commit -m "Add mandatory RHOAI labels to Dockerfile"

Push the branch to your fork.

    git push origin add-rhoai-labels

### 7. Raise a GitHub PR

Create a pull request targeting the upstream repo branch.

    gh pr create \
      --repo <owner>/<repo> \
      --base <repo-branch> \
      --head $GITHUB_USER:add-rhoai-labels \
      --title "Add mandatory RHOAI labels to Dockerfile" \
      --body "Adds the 7 mandatory RHOAI labels to the Dockerfile:
- name
- com.redhat.component
- summary
- description
- maintainer
- io.k8s.display-name
- io.k8s.description

Related Jira: <jira-url>"

Capture the PR URL for tracking.

### 8. Update Jira (if applicable)

If a Jira URL was provided, update the issue:
- Add label `dockerfile-labels-pr-raised`
- Post a comment with the PR URL

Use the Jira web UI or API:

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"update":{"labels":[{"add":"dockerfile-labels-pr-raised"}]}}' \
      "https://redhat.atlassian.net/rest/api/2/issue/<JIRA-ID>"

    curl -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"body":"Dockerfile labels PR raised: <pr-url>"}' \
      "https://redhat.atlassian.net/rest/api/2/issue/<JIRA-ID>/comment"

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Dockerfile not found (404) | Verify repo_url, repo_branch, context_path, and dockerfile_path in the YAML. The Dockerfile may not exist on the branch yet. |
| All labels already present | Exit cleanly without creating a PR. The step is already complete. |
| Fork already exists | Clone the existing fork and update it: `git fetch upstream && git rebase upstream/<repo-branch>`. |
| PR already exists for this branch | Use the existing PR or delete the remote branch and recreate it. |
| GITHUB_TOKEN lacks permissions | Ensure the token has `repo` scope. Regenerate the token at https://github.com/settings/tokens. |

## Automation

The script `scripts/add-rhoai-dockerfile-labels.sh` automates this playbook end-to-end.

    ./scripts/add-rhoai-dockerfile-labels.sh <jira-url>

Beyond the manual steps above, the script also:
- Automatically extracts component details from the Jira attachment
- Detects which labels are missing or incorrect
- Generates appropriate LABEL instructions
- Handles idempotency: skips if all labels are already correct
- Updates Jira labels and comments throughout the process

## Related playbooks

- [validate-component-onboarding-jira](validate-component-onboarding-jira.md) — validates Dockerfile digest pinning
- [onboard-konflux-components-for-odh-and-rhoai](onboard-konflux-components-for-odh-and-rhoai.md) — orchestrator
