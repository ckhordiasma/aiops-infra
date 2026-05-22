# Onboard Component to Konflux Release Data

Onboards a new ODH/RHOAI component onto the Konflux CI platform by adding Component resources to konflux-release-data.

**Applies to:** Both (ODH and RHOAI)
**Pipeline step:** 3

## When to use

After the Quay repository exists and you're ready to set up CI/CD builds. This creates the Konflux Component resources that provision build pipelines on OpenShift.

## Prerequisites

- Red Hat VPN active (konflux-release-data and OpenShift clusters are internal)
- GitLab credentials: GITLAB_USER, GITLAB_TOKEN (scopes: api, write_repository)
- Jira credentials: JIRA_USER_EMAIL, JIRA_API_TOKEN
- Tools: uv, oc, yamllint, kustomize (v5.7.1), kubectl
- Jira ticket with component_onboarding_details.yaml attached
- OpenShift cluster access:
  - ODH: external cluster (stone-prd-rh01) - set EXT_OC_TOKEN if no matching kubeconfig
  - RHOAI: internal cluster (stone-prod-p02) - set INT_OC_TOKEN if no matching kubeconfig

## What you'll be changing

Repository: `https://gitlab.cee.redhat.com/releng/konflux-release-data`

**For ODH:**
File: `tenants-config/cluster/stone-prd-rh01/tenants/open-data-hub-tenant/opendatahub-ci-components.yaml`

**For RHOAI (version 3.4 example):**
Files:
- `tenants-config/cluster/stone-prod-p02/tenants/rhoai-tenant/v3.4/ProjectDevelopmentStream-v3.4.yaml`
- `config/stone-prod-p02.hjvn.p1/product/ReleasePlanAdmission/rhoai/rhoai-onprem-v3-4-components-stage.yaml`
- `config/stone-prod-p02.hjvn.p1/product/ReleasePlanAdmission/rhoai/rhoai-onprem-v3-4-components-prod.yaml`
- `tenants-config/cluster/stone-prod-p02/tenants/rhoai-tenant/automation/resources.yaml`

You'll be adding Konflux Component YAML documents that define build configuration (repo URL, branch, Dockerfile, context).

## Steps

### 1. Check if Konflux Component already exists

Verify the component doesn't already exist on the OpenShift cluster.

For ODH (external cluster):

    oc login <external-cluster-url> --token=$EXT_OC_TOKEN
    oc get component <component-name>-ci -n open-data-hub-tenant

For RHOAI (internal cluster):

    oc login <internal-cluster-url> --token=$INT_OC_TOKEN
    oc get component <component-name>-v3-4 -n rhoai-tenant

If the component exists, skip to Jira updates.

### 2. Clone konflux-release-data

Clone the repository using sparse checkout to fetch only the necessary directories.

**For ODH:**

    git clone --filter=blob:none --sparse https://gitlab.cee.redhat.com/releng/konflux-release-data
    cd konflux-release-data
    git sparse-checkout set tenants-config/cluster/stone-prd-rh01/tenants/open-data-hub-tenant \
                             tenants-config/auto-generated/cluster/stone-prd-rh01/tenants/open-data-hub-tenant

**For RHOAI:**

    git clone --filter=blob:none --sparse https://gitlab.cee.redhat.com/releng/konflux-release-data
    cd konflux-release-data
    git sparse-checkout set tenants-config/cluster/stone-prod-p02/tenants/rhoai-tenant \
                             tenants-config/auto-generated/cluster/stone-prod-p02/tenants/rhoai-tenant \
                             config/stone-prod-p02.hjvn.p1/product/ReleasePlanAdmission/rhoai

Create a feature branch:

    git checkout -b RHOAIENG-1234

### 3. Add Component to the tenant YAML file

**For ODH:**

Append a Component document to `opendatahub-ci-components.yaml`:
```yaml
---
apiVersion: appstudio.redhat.com/v1alpha1
kind: Component
metadata:
  annotations:
    build.appstudio.openshift.io/request: configure-pac-no-mr
    mintmaker.appstudio.redhat.com/disabled: "true"
    build.appstudio.openshift.io/pipeline: '{"name":"docker-build-multi-platform-oci-ta","bundle":"latest"}'
  name: my-component-ci
spec:
  application: opendatahub-builds
  componentName: my-component-ci
  containerImage: quay.io/opendatahub/my-component
  source:
    git:
      context: .
      dockerfileUrl: Dockerfile
      revision: main
      url: https://github.com/opendatahub/my-component
```

**For RHOAI:**

RHOAI requires updates to multiple files. Parse target_rhoai_version from the YAML to determine which version directory to use.

Add to `ProjectDevelopmentStream-v3.4.yaml` (under spec.resources):
```yaml
- apiVersion: appstudio.redhat.com/v1alpha1
  kind: Component
  metadata:
    annotations:
      build.appstudio.openshift.io/pipeline: '{"name":"docker-build-multi-platform-oci-ta","bundle":"latest"}'
      build.appstudio.openshift.io/request: configure-pac-no-mr
    name: my-component-{{.versionName}}
  spec:
    application: rhoai-{{.versionName}}
    build-nudges-ref:
      - odh-operator-{{.versionName}}
    componentName: my-component-{{.versionName}}
    containerImage: quay.io/rhoai/my-component-rhel9
    source:
      git:
        context: .
        dockerfileUrl: Dockerfile
        revision: "{{.branch}}"
        url: https://github.com/rhoai/my-component
```

Note: `{{.versionName}}` and `{{.branch}}` are Go template placeholders - keep them verbatim.

Add to `rhoai-onprem-v3-4-components-stage.yaml` (under spec.data.mapping.components):
```yaml
- name: my-component-v3-4
  repositories:
    - url: registry.stage.redhat.io/rhoai/my-component-rhel9
```

Add to `rhoai-onprem-v3-4-components-prod.yaml` (under spec.data.mapping.components):
```yaml
- name: my-component-v3-4
  repositories:
    - url: registry.redhat.io/rhoai/my-component-rhel9
```

Add to `automation/resources.yaml`:
```yaml
---
apiVersion: appstudio.redhat.com/v1alpha1
kind: Component
metadata:
  annotations:
    build.appstudio.openshift.io/request: configure-pac-no-mr
    build.appstudio.openshift.io/pipeline: '{"name":"docker-build-multi-platform-oci-ta","bundle":"latest"}'
  name: pull-request-pipelines-my-component
spec:
  application: automation
  componentName: pull-request-pipelines-my-component
  containerImage: quay.io/rhoai/pull-request-pipelines
  source:
    git:
      context: .
      dockerfileUrl: Dockerfile
      url: https://github.com/rhoai/my-component
```

### 4. Regenerate auto-generated manifests

Run the build script to regenerate the auto-generated directory:

    cd tenants-config
    ./build-manifests.sh kustomize

### 5. Validate YAML syntax

Run yamllint to catch formatting issues:

    cd ..
    yamllint -s -f colored .gitlab-ci.yml .gitlab tenants-config/cluster

Fix any reported errors (indentation, trailing spaces, line length).

### 6. Commit changes and verify manifests

Stage all changes (source YAML and auto-generated files):

    git add -A
    git commit -m "Add <component>-ci Component to konflux-release-data"

Verify the generated manifests:

    cd tenants-config
    ./verify-manifests.sh kustomize

Fix any errors reported, amend the commit if needed.

### 7. Push changes

Push the branch to the remote:

    git push origin RHOAIENG-1234

If you encounter "shallow update not allowed", unshallow and retry:

    git fetch --unshallow origin
    git push origin RHOAIENG-1234

### 8. Create merge request

Raise an MR targeting the main branch:

    glab mr create --title "Add <component>-ci Component for <component>" \
      --description "Add Konflux Component to konflux-release-data.\n\n**Product:** ODH\n**Application:** opendatahub-builds\n**Container image:** quay.io/opendatahub/<component>\n**Jira:** <jira-url>" \
      --source-branch RHOAIENG-1234 \
      --target-branch main

### 9. Update Jira

Add label `krd-mr-raised` and comment with MR URL.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| VPN connection fails | Connect to Red Hat VPN |
| oc login fails | Set EXT_OC_TOKEN or INT_OC_TOKEN for the appropriate cluster |
| component_onboarding_details.yaml missing | Run /create-component-onboarding-jira first |
| target_rhoai_version missing/invalid | Ensure YAML has valid version (e.g., "3.4" or "3.4-ea-2") |
| ProjectDevelopmentStream file not found | Sprint onboarding for that version is pending |
| build-manifests.sh fails | Review error output; fix YAML syntax or kustomize issues |
| yamllint errors | Fix indentation, trailing spaces, or line length issues |
| verify-manifests.sh fails | Inspect reported file and fix manifest validation errors |
| Shallow push rejected | Run `git fetch --unshallow origin` then retry |

## Automation

The script `scripts/onboard-component-to-konflux-release-data.sh` automates this playbook end-to-end.

    ./scripts/onboard-component-to-konflux-release-data.sh <jira-url>

Beyond the manual steps above, the script also:
- Downloads component_onboarding_details.yaml from Jira automatically
- Determines product context (ODH vs RHOAI) from Jira ticket
- Computes version-specific file paths and component names for RHOAI
- Handles idempotency checks (skips if component already exists)
- Uses sparse checkout for faster cloning
- Retries MR creation up to 3 times on transient failures
- Automatically fixes common yamllint and kustomize errors
- Updates Jira with labels and structured comments

## Related playbooks

- [create-quay-repo](create-quay-repo.md) - Must complete before this step
- [create-rhoai-delivery-repo](create-rhoai-delivery-repo.md) - RHOAI-only next step
- [update-rhoai-product-listing](update-rhoai-product-listing.md) - RHOAI-only final step
