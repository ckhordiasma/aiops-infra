# Onboard Component to Konflux Release Data

Creates Konflux Component resources for a new ODH or RHOAI component by appending YAML documents to the appropriate tenant config file in the `konflux-release-data` GitLab repository and raising a merge request. When the MR is merged, a GitOps pipeline provisions the Component on the Konflux OpenShift cluster.

**Applies to:** Both (ODH and RHOAI)
**Pipeline step:** 3

## When to use

Run this after the Quay repository has been created (Step 2). The Jira ticket must have `component_onboarding_details.yaml` attached with the component's repo URL, branch, Dockerfile path, and context path.

## Prerequisites

You need the following before starting:

- **GitLab credentials** -- `GITLAB_USER` and `GITLAB_TOKEN` (with `api` and `write_repository` scopes) for Red Hat's internal GitLab.
- **Jira credentials** -- `JIRA_USER_EMAIL` and `JIRA_API_TOKEN`.
- **Tools** -- `uv` (Python runner), `oc` (OpenShift CLI), `yamllint` (YAML linter), `kustomize` v5.7.1 (or `kubectl` with built-in kustomize).
- **VPN** -- Red Hat VPN must be active for both GitLab and the Konflux OpenShift cluster.
- **OpenShift tokens** (optional) -- `EXT_OC_TOKEN` for the external Konflux cluster (stone-prd-rh01, ODH builds) or `INT_OC_TOKEN` for the internal cluster (stone-prod-p02, RHOAI builds), if no matching kubeconfig context is found.

## What you'll be changing

**Repository:** `konflux-release-data` on `gitlab.cee.redhat.com/releng/konflux-release-data`

**For ODH components**, you modify one file:

| File | Description |
|------|-------------|
| `tenants-config/cluster/stone-prd-rh01/tenants/open-data-hub-tenant/opendatahub-ci-components.yaml` | Add a Konflux Component YAML document |

**For RHOAI components**, you modify up to four files:

| File | Description |
|------|-------------|
| `tenants-config/cluster/stone-prod-p02/tenants/rhoai-tenant/<version>/ProjectDevelopmentStream-<version>.yaml` | Add component to the `spec.resources` array |
| `config/stone-prod-p02.hjvn.p1/product/ReleasePlanAdmission/rhoai/rhoai-onprem-<rpa-var>-components-stage.yaml` | Add stage registry entry |
| `config/stone-prod-p02.hjvn.p1/product/ReleasePlanAdmission/rhoai/rhoai-onprem-<rpa-var>-components-prod.yaml` | Add prod registry entry |
| `tenants-config/cluster/stone-prod-p02/tenants/rhoai-tenant/automation/resources.yaml` | Add pull-request pipeline component |

The Konflux Component YAML document looks like:

```yaml
apiVersion: appstudio.redhat.com/v1alpha1
kind: Component
metadata:
  annotations:
    build.appstudio.openshift.io/request: configure-pac-no-mr
    mintmaker.appstudio.redhat.com/disabled: "true"
    build.appstudio.openshift.io/pipeline: '{"name":"docker-build-multi-platform-oci-ta","bundle":"latest"}'
  name: <component-name>-ci
spec:
  application: opendatahub-builds
  componentName: <component-name>-ci
  containerImage: quay.io/opendatahub/<component-name>
  source:
    git:
      context: <context-path>
      dockerfileUrl: <dockerfile-path>
      revision: <branch>
      url: <repo-url>
```

## Steps

### 1. Gather component details

Download `component_onboarding_details.yaml` from the Jira ticket and extract:
- `component_name`, `repo_url`, `repo_branch`, `context_path`, `dockerfile_path`
- `target_rhoai_version` (RHOAI only)

Determine the product context (ODH or RHOAI) from the Jira key prefix (`RHOAIENG` = RHOAI, `RHODS` = ODH) or the ticket title.

Compute `KONFLUX_COMPONENT_NAME`:
- ODH: `<component_name>-ci`
- RHOAI: `<component_name>-v<X>-<Y>` (e.g., `my-component-v3-4`)

### 2. Check if the Konflux Component already exists

Log in to the appropriate Konflux cluster and check:

    oc get component <KONFLUX_COMPONENT_NAME> -n <namespace>

Where namespace is `open-data-hub-tenant` (ODH) or `rhoai-tenant` (RHOAI). If it exists, add Jira label `konflux-component-created` and stop.

### 3. Clone konflux-release-data

Clone with sparse checkout for the tenant config files:

    git clone --filter=blob:none --sparse https://gitlab.cee.redhat.com/releng/konflux-release-data.git
    cd konflux-release-data
    git sparse-checkout set <sparse-paths>
    git checkout -b <JIRA-ID>

For ODH, sparse paths are:
- `tenants-config/cluster/stone-prd-rh01/tenants/open-data-hub-tenant`
- `tenants-config/auto-generated/cluster/stone-prd-rh01/tenants/open-data-hub-tenant`

For RHOAI, sparse paths are:
- `tenants-config/cluster/stone-prod-p02/tenants/rhoai-tenant`
- `tenants-config/auto-generated/cluster/stone-prod-p02/tenants/rhoai-tenant`
- `config/stone-prod-p02.hjvn.p1/product/ReleasePlanAdmission/rhoai`

### 4. Add the Component YAML document

**For ODH:** Append a Component YAML document to `opendatahub-ci-components.yaml` using a YAML document separator (`---`).

**For RHOAI:** Modify up to four files:
1. Append a component entry to `ProjectDevelopmentStream-<version>.yaml` in the `spec.resources` array. Use Go template placeholders `{{.versionName}}` and `{{.branch}}` verbatim.
2. Add an entry to `rhoai-onprem-<rpa-var>-components-stage.yaml` under `spec.data.mapping.components` with `registry.stage.redhat.io`.
3. Add an entry to `rhoai-onprem-<rpa-var>-components-prod.yaml` under `spec.data.mapping.components` with `registry.redhat.io`.
4. Append a pull-request pipeline Component document to `automation/resources.yaml`.

### 5. Build and verify manifests

Regenerate the `auto-generated/` directory and validate:

    cd tenants-config
    ./build-manifests.sh kustomize
    cd ..
    yamllint -s -f colored .gitlab-ci.yml .gitlab tenants-config/cluster
    cd tenants-config
    ./verify-manifests.sh kustomize

Fix any yamllint or verification errors before proceeding.

### 6. Commit, push, and raise a merge request

    git add -A
    git commit -m "Add <KONFLUX_COMPONENT_NAME> Component to konflux-release-data"
    git push origin <JIRA-ID>

    glab mr create \
      --source-branch "<JIRA-ID>" \
      --target-branch "main" \
      --title "Add <KONFLUX_COMPONENT_NAME> Component for <COMPONENT_NAME>" \
      --description "Add Konflux Component '<KONFLUX_COMPONENT_NAME>' to <TARGET_YAML>.

    Product: <ODH|RHOAI>
    Application: <KRD_APPLICATION>
    Container image: quay.io/<org>/<component_name>
    Source repo: <repo_url> @ <branch>
    Jira: <jira-url>"

### 7. Update Jira

Add the label `krd-mr-raised` to the Jira ticket and comment with the MR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `oc` not installed | Download from console.redhat.com/openshift/downloads |
| `yamllint` errors after edit | Read the error output; fix indentation/trailing whitespace |
| `verify-manifests.sh` fails | Read the error, fix the manifest file, re-stage and amend commit |
| VPN not active | Connect to Red Hat VPN; required for GitLab and Konflux cluster |
| `EXT_OC_TOKEN` / `INT_OC_TOKEN` not set | Get token from the OpenShift console login page |
| `ProjectDevelopmentStream` file not found | Sprint onboarding for that version is pending; complete it first |
| `target_rhoai_version` missing or invalid | Expected `x.y` or `x.y-ea-n` format; re-generate the onboarding YAML |
| Push fails with "shallow update not allowed" | Run `git fetch --unshallow origin` then retry |

## Automation

The script `scripts/onboard-component-to-konflux-release-data.sh` automates this playbook end-to-end.

    ./scripts/onboard-component-to-konflux-release-data.sh --jira-url <url>

Beyond the manual steps above, the script also:
- Downloads `component_onboarding_details.yaml` from Jira automatically
- Determines product context from Jira key prefix or title
- Handles ODH vs RHOAI file paths and naming conventions automatically
- Runs `build-manifests.sh`, `yamllint`, and `verify-manifests.sh` with error recovery
- Handles "shallow update not allowed" errors with automatic unshallow/retry
- Retries MR creation up to 3 times with error classification
- Supports `--existing-mr-url` for idempotent re-runs
- Updates Jira labels and comments throughout the process

## Related playbooks

- [create-quay-repo](create-quay-repo.md) -- prerequisite: Quay repo must exist first
- [create-rhoai-delivery-repo](create-rhoai-delivery-repo.md) -- downstream step for RHOAI components
