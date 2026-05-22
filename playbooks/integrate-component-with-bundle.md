# Integrate Component with Bundle

Updates the build-config repository with a new component's `relatedImages` entry in `bundle/bundle-patch.yaml` and, for RHOAI only, adds entries to `config/build-config.yaml` and `bundle/Dockerfile`. Raises a GitHub PR.

**Applies to:** Both (ODH and RHOAI)
**Pipeline step:** 8

## When to use

Run this after the component's Konflux PipelineRuns have been set up (Steps 4-5) and the Quay repo exists. The Jira ticket must have `component_onboarding_details.yaml` attached.

## Prerequisites

You need a GitHub account with push access to the build-config repo (or a fork), a GitHub personal access token with `repo` scope, and `git` installed. The target repo depends on the product context.

## What you'll be changing

**Repo:** Depends on product context:
- ODH: `opendatahub-io/ODH-Build-Config`
- RHOAI: `red-hat-data-services/RHOAI-Build-Config`
- Can be overridden via `BUILD_CONFIG_REPO_URL`

**Files modified:**
1. `bundle/bundle-patch.yaml` -- add `relatedImages` entry (both ODH and RHOAI)
2. `config/build-config.yaml` -- add `repo_mappings` entry (RHOAI only)
3. `bundle/Dockerfile` -- add ARG and LABEL entries for the component (RHOAI only)

The `relatedImages` entry maps the component name to its Quay image with a SHA256 digest:

```yaml
- name: RELATED_IMAGE_<COMPONENT_NAME>
  value: quay.io/<quay-org>/<component-name>@sha256:<digest>
```

For ODH, `quay-org` is `opendatahub`. For RHOAI, it is `rhoai` and the image name is `<component-name>-rhel9`.

## Steps

### 1. Download and parse the onboarding YAML

Download `component_onboarding_details.yaml` from the Jira ticket. Extract: `component_name`, `product_context`, `repo_url`, `repo_branch`, and `target_rhoai_version` (RHOAI only).

### 2. Resolve the image reference

Look up the latest image digest from Quay:

    skopeo inspect --no-creds docker://quay.io/<quay-org>/<image-name>:odh-stable | jq -r '.Digest'

If the image has not yet been built, use a placeholder digest. The PR description will note that the digest must be updated before merging.

### 3. Check if the component already exists

Fetch `bundle/bundle-patch.yaml` from the build-config repo and check if the `RELATED_IMAGE` name is already present. If so, add the label `bundle-changes-done` to Jira and stop.

### 4. Fork, clone, and create a branch

    gh repo fork <build-config-repo> --clone
    cd <build-config-repo-name>
    git checkout -b <jira-id>

For ODH, clone `main`. For RHOAI, clone the version-specific branch (e.g., `rhoai-2.16`).

### 5. Edit bundle/bundle-patch.yaml

Add the `relatedImages` entry under `patch.relatedImages`. For ODH, also include a `component` field.

### 6. Edit config/build-config.yaml (RHOAI only)

Add a `repo_mappings` entry under `config.replacements[0].repo_mappings`:

```yaml
rhoai/<component-name>-rhel9: rhoai/<component-name>-rhel9
```

### 7. Edit bundle/Dockerfile (RHOAI only)

Add ARG and LABEL entries for the component's git URL and commit references.

### 8. Commit, push, and create PR

    git add bundle/bundle-patch.yaml config/build-config.yaml bundle/Dockerfile
    git commit -m "Add <component-name> to bundle-patch.yaml"
    git push -u origin <jira-id>

    gh pr create \
      --title "Add <component-name> to bundle-patch.yaml" \
      --body "Adds '<component-name>' to the build-config bundle relatedImages.

    Product: <product-context>
    Jira: <jira-url>"

### 9. Update Jira

Add the label `bundle-pr-raised` and comment with the PR URL and list of files changed.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Component already in bundle-patch.yaml | Expected -- exits cleanly, Jira labelled `bundle-changes-done` |
| `target_rhoai_version` missing (RHOAI) | Add the field to the YAML and re-upload |
| Placeholder digest used | Update the digest in the PR before merging once Konflux has built the image |
| `bundle/bundle-patch.yaml` not found | Verify the build-config repo URL is correct |
| Push fails (shallow update) | Run `git fetch --unshallow origin` then retry |

## Automation

The script `scripts/integrate-component-with-bundle.sh` automates this playbook end-to-end.

    ./scripts/integrate-component-with-bundle.sh --jira-url <url>

Beyond the manual steps above, the script also:
- Downloads `component_onboarding_details.yaml` from Jira automatically
- Automatically determines the build-config repo from product context
- Resolves the image digest from Quay (falls back to placeholder)
- Updates all three files for RHOAI (bundle-patch, build-config, Dockerfile)
- Performs a fast-path check via GitHub API before cloning
- Retries PR creation up to 3 times with error classification
- Adds Jira labels and comments at each milestone

## Related playbooks

- [integrate-component-with-odh-operator](integrate-component-with-odh-operator.md) -- the subsequent operator integration step
- [add-component-to-rhoai-konflux-central](add-component-to-rhoai-konflux-central.md) -- must be done before this step
