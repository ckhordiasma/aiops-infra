---
name: create-component-onboarding-jira
description: Interactively collects ODH/RHOAI component onboarding parameters from the user, generates a validated component_onboarding_details.yaml, and creates or updates a Jira ticket with the YAML attached. When no Jira URL is provided, automatically creates a new ticket by cloning the product-specific onboarding template. Use this before running other onboarding skills.
allowed-tools: Bash
user-invocable: true
---

# Create Component Onboarding Jira

Collects component onboarding parameters, generates a validated YAML, and creates or
updates a Jira ticket with the YAML attached.
See the [playbook](${CLAUDE_SKILL_DIR}/../../../playbooks/create-component-onboarding-jira.md) for context.

## Usage

/create-component-onboarding-jira [<jira-url>]

## Implementation

Help the user accomplish this task by interactively collecting the required inputs
through a conversational Q&A, then running the automation script with all inputs
passed as flags.

### Interactive collection flow

Ask the user for each required field in sequence:

1. **Product context** (ODH or RHOAI)
2. **Build type** (ODH only: CI or Release) or **Target RHOAI version** + **Architectures** (RHOAI only)
3. **Component name** (must start with `odh-`)
4. **Release category** (RHOAI only: Generally Available, Tech Preview, or Beta)
5. **Repository URL** (full HTTPS GitHub URL)
6. **Component descriptions** (RHOAI only: long and short descriptions -- try to auto-suggest from README)
7. **Branch** (ODH: ask user; RHOAI: auto-derive from version)
8. **Build context path** and **Dockerfile path**
9. **Is operator?** and if yes, **manifest paths**
10. **Parent feature Jira ID** (e.g. RHAISTRAT-1234)

Show a summary of all collected values and ask for confirmation before proceeding.

### Running the script

Once all inputs are confirmed, pass them as flags to the automation script:

```bash
bash "${CLAUDE_SKILL_DIR}/../../../scripts/create-component-onboarding-jira.sh" \
  --product-context "$product_context" \
  --component-name "$component_name" \
  --repo-url "$repo_url" \
  --context-path "$context_path" \
  --dockerfile-path "$dockerfile_path" \
  --parent-feature "$parent_feature_id" \
  [--jira-url "$jira_url"] \
  [--build-type "$build_type"] \
  [--target-rhoai-version "$target_rhoai_version"] \
  [--architectures "$architectures"] \
  [--release-category "$release_category"] \
  [--long-description "$long_description"] \
  [--short-description "$short_description"] \
  [--repo-branch "$repo_branch"] \
  [--is-operator] \
  [--operator-manifest-src-path "$src_path"] \
  [--operator-manifest-dest-path "$dest_path"]
```

The Jira URL is optional. Without it, a new ticket is created by cloning the
product-specific template (ODH: RHOAIENG-35683, RHOAI: RHOAIENG-17225).
