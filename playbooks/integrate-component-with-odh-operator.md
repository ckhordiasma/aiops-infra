# Integrate Component with ODH Operator

Adds a new operator component to the operator repository by updating `build/manifests-config.yaml` and raising a GitHub PR. The target repo depends on the product context: `opendatahub-io/opendatahub-operator` for ODH, `red-hat-data-services/rhods-operator` for RHOAI.

**Applies to:** Both (ODH and RHOAI)
**Pipeline step:** 5

## When to use

Run this only when `is_operator=true` in the component's onboarding YAML. If the component is not an operator, this step is a no-op. This step typically runs after the bundle integration (Step 8).

## Prerequisites

You need a GitHub account with push access to the target operator repo (or a fork), a GitHub personal access token with `repo` scope, and `git` installed. The Jira ticket must have `component_onboarding_details.yaml` attached with `is_operator: true` and the `operator_manifest_src_path` and `operator_manifest_dest_path` fields populated.

## What you'll be changing

**Repo:** Depends on product context:
- ODH: `opendatahub-io/opendatahub-operator`
- RHOAI: `red-hat-data-services/rhods-operator`
- Can be overridden via `ODH_OPERATOR_REPO_URL`

**File:** `build/manifests-config.yaml`
**Change:** Add a new entry under the `map:` key:

```yaml
map:
  <component-name>:
    src: <operator_manifest_src_path>
    dest: <operator_manifest_dest_path>
```

## Steps

### 1. Download and parse the onboarding YAML

Download `component_onboarding_details.yaml` from the Jira ticket. Extract: `component_name`, `product_context`, `is_operator`, `operator_manifest_src_path`, `operator_manifest_dest_path`, `repo_url`, and `repo_branch`.

### 2. Check is_operator gate

If `is_operator=false`, add the label `operator-changes-not-needed` to Jira, comment that no operator changes are needed, and stop. This is not an error.

If `is_operator=true`, verify that both `operator_manifest_src_path` and `operator_manifest_dest_path` are present in the YAML.

### 3. Determine the operator repo

Based on `product_context`:
- ODH: `https://github.com/opendatahub-io/opendatahub-operator.git`
- RHOAI: `https://github.com/red-hat-data-services/rhods-operator.git`

### 4. Check if the component already exists

    curl -s -w "%{http_code}" \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3.raw" \
      "https://api.github.com/repos/<operator-repo>/contents/build/manifests-config.yaml?ref=main" \
      -o /tmp/manifests-config.yaml

If the component name already appears as a key under `map:`, add the label `odh-operator-pr-raised` to Jira and stop.

### 5. Fork, clone, and create a branch

    gh repo fork <operator-repo> --clone
    cd <operator-repo-name>
    git checkout -b <jira-id>

### 6. Edit manifests-config.yaml

Add a new entry under the `map:` key for the component. The entry includes `src` (where the manifests live in the component repo) and `dest` (where they should be copied in the operator repo).

### 7. Commit, push, and create PR

    git add build/manifests-config.yaml
    git commit -m "Add <component-name> to manifests-config.yaml"
    git push -u origin <jira-id>

    gh pr create \
      --title "Add <component-name> to manifests-config.yaml" \
      --body "Adds '<component-name>' to the operator manifests config map.

    Manifest source path: <src-path>
    Manifest dest path: <dest-path>
    Jira: <jira-url>"

### 8. Update Jira

Add the label `operator-pr-raised` and comment with the PR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `is_operator=false` | Expected -- exits cleanly, Jira labelled `operator-changes-not-needed` |
| Component already in config | Expected -- exits cleanly, Jira labelled `odh-operator-pr-raised` |
| `operator_manifest_src_path` or `dest_path` missing | Add fields to YAML and re-upload to Jira |
| `manifests-config.yaml` not found | Verify the operator repo URL is correct |
| Push fails (shallow update) | Run `git fetch --unshallow origin` then retry |

## Automation

The script `scripts/integrate-component-with-odh-operator.sh` automates this playbook end-to-end.

    ./scripts/integrate-component-with-odh-operator.sh --jira-url <url>

Beyond the manual steps above, the script also:
- Downloads `component_onboarding_details.yaml` from Jira automatically
- Automatically determines the operator repo from product context
- Performs a fast-path check via GitHub API before cloning
- Uses `edit_yaml.py insert-map-key` for safe YAML manipulation
- Retries PR creation up to 3 times with error classification
- Adds Jira labels and comments at each milestone

## Related playbooks

- [integrate-component-with-bundle](integrate-component-with-bundle.md) -- the preceding bundle integration step
