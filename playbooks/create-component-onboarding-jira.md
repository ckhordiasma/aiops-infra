# Create Component Onboarding Jira

Collects all parameters needed to onboard an ODH or RHOAI component onto the Konflux CI/build platform, produces a validated `component_onboarding_details.yaml`, and creates or updates a Jira ticket with the YAML attached.

**Applies to:** Both
**Pipeline step:** 0 (prerequisite for all other onboarding steps)

## When to use

Run this as the first step of the onboarding process, before any other onboarding skills. You need this to create the Jira ticket that tracks the entire onboarding pipeline and to generate the YAML configuration file that all downstream steps consume.

## Prerequisites

- Jira credentials: `JIRA_USER_EMAIL` and `JIRA_API_TOKEN` environment variables
- `jq` installed (needed for the template clone flow)
- `uv` Python runner installed
- Knowledge of the component being onboarded (repo URL, branch, Dockerfile path, etc.)

## What you'll be changing

A new Jira ticket is created (by cloning a product-specific template) or an existing ticket is updated. The `component_onboarding_details.yaml` file is generated and attached to the ticket.

Templates:
- ODH: cloned from `RHOAIENG-35683`
- RHOAI: cloned from `RHOAIENG-17225`

## Steps

### 1. Determine product context

Decide whether this component is being onboarded for ODH or RHOAI. This determines which fields are required and which template is used.

### 2. Collect the onboarding details

Gather the following information about the component:

**Common fields (both ODH and RHOAI):**

| Field | Description | Example |
|-------|-------------|---------|
| `component_name` | Must start with `odh-`, lowercase with hyphens | `odh-my-component` |
| `repo_url` | Full HTTPS GitHub URL | `https://github.com/opendatahub-io/my-component` |
| `repo_branch` | Branch to build | `main` (ODH) or auto-derived for RHOAI |
| `context_path` | Docker build context relative to repo root | `./` |
| `dockerfile_path` | Path to Dockerfile relative to context | `Dockerfile` |
| `is_operator` | Whether this is an operator/controller | `true` or `false` |

**ODH-specific:**

| Field | Description | Example |
|-------|-------------|---------|
| `build_type` | CI or Release | `CI` |

**RHOAI-specific:**

| Field | Description | Example |
|-------|-------------|---------|
| `target_rhoai_version` | Target version (canonical form) | `3.4` or `3.4-ea-2` |
| `architectures` | CPU architectures to build for | `x86_64, arm64` |
| `release_category` | GA, Tech Preview, or Beta | `Generally Available` |
| `long_description` | One to two sentences describing the component | |
| `short_description` | A few words summarizing the component | |

**RHOAI Dockerfile naming:** For RHOAI components, the Dockerfile name must contain `Dockerfile.konflux` (e.g. `Dockerfile.konflux`, `docker/Dockerfile.konflux.cuda`).

**RHOAI branch derivation:** For RHOAI, the `repo_branch` is auto-derived from `target_rhoai_version`:
- Version `3.5` becomes branch `rhoai-3.5`
- Version `3.5-ea-1` becomes branch `rhoai-3.5-ea.1`

**Operator fields (only when `is_operator` is true):**

| Field | Description | Example |
|-------|-------------|---------|
| `operator_manifest_src_path` | Path to manifests in git repo | `config/manifests` |
| `operator_manifest_dest_path` | Destination path in operator image | `my-component` |

### 3. Generate the YAML file

Create a `component_onboarding_details.yaml` file with all collected values under an `inputs:` key. The file should match the JSON Schema at `playbooks/assets/component_onboarding_details.schema.json`.

### 4. Validate the YAML

Verify the generated YAML is valid against the schema. For RHOAI components, also check that the Dockerfile at the specified path uses `@sha256:` digest pinning for all `FROM` instructions.

### 5. Identify the parent feature

You need the Jira ID of the parent feature ticket (e.g. `RHAISTRAT-1234`) to link the onboarding ticket to.

### 6. Create or update the Jira ticket

**If you have an existing Jira ticket:**

Attach the YAML file to the ticket, add the label `yaml-attached`, link the ticket to the parent feature with a "relates to" link, and post a comment summarizing the component details.

**If creating a new ticket:**

Clone the appropriate template in Jira:
- ODH: clone `RHOAIENG-35683`
- RHOAI: clone `RHOAIENG-17225`

Then attach the YAML, add labels, link to the parent feature, and post the summary comment.

### 7. Update Jira metadata

Update the ticket title and description with the component details (component name, repo URL, branch, etc.). This step is non-critical -- if it fails, update the title and description manually in the Jira web UI.

### 8. Verify completion

Confirm the Jira ticket has:
- The `component_onboarding_details.yaml` attachment
- The `yaml-attached` label
- A "relates to" link to the parent feature
- A summary comment with the component details

The ticket is now ready for validation with `/validate-component-onboarding-jira`.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `JIRA_USER_EMAIL` / `JIRA_API_TOKEN` not set | Export the env vars |
| `uv` or `jq` not installed | `curl -LsSf https://astral.sh/uv/install.sh \| sh` / `brew install jq` |
| Template clone fails | Check Jira credentials and create permission |
| YAML generation fails | Check the input arguments |
| YAML validation fails | Correct the inputs and re-generate |
| Dockerfile digest violations | Pin all FROM images with `@sha256` digests |
| Attachment upload fails | Check credentials; re-run |
| Metadata update fails | Update title/description/labels manually in Jira |

## Automation

The script `scripts/create-component-onboarding-jira.sh` automates this playbook end-to-end.

    ./scripts/create-component-onboarding-jira.sh \
      --product-context RHOAI \
      --component-name odh-my-component \
      --repo-url https://github.com/opendatahub-io/my-component \
      --context-path ./ \
      --dockerfile-path Dockerfile.konflux \
      --parent-feature RHAISTRAT-1234 \
      --target-rhoai-version 3.5 \
      --architectures x86_64,arm64 \
      --release-category "Generally Available" \
      --long-description "My component does X and Y." \
      --short-description "My component" \
      [--jira-url https://redhat.atlassian.net/browse/RHOAIENG-1234]

Beyond the manual steps above, the script also:
- Accepts all inputs as command-line flags (no interactive prompts)
- Auto-derives the RHOAI branch from target version
- Generates and validates the YAML automatically
- Checks Dockerfile digest pinning for RHOAI components
- Clones the correct Jira template when no `--jira-url` is provided
- Attaches the YAML, adds labels, links to parent feature, and posts comments
- Updates Jira metadata (title, description) via the `update_onboarding_jira.py` helper

## Related playbooks

- [validate-component-onboarding-jira](validate-component-onboarding-jira.md) (downstream -- validates the ticket)
- [onboard-konflux-components-for-odh-and-rhoai](onboard-konflux-components-for-odh-and-rhoai.md) (downstream -- full pipeline)
