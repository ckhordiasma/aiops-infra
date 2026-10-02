"""Render the RHOAI PipelineRun templates without invoking onboarding services."""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def _render_template(tmp_path: Path, script_name: str, version: str, prefetch: str) -> dict:
    source = (REPO_ROOT / "scripts" / script_name).read_text(encoding="utf-8")
    # Execute the real platform/prefetch formatting and heredoc, stopping before
    # the wrapper's commit, PR, Jira, and pipeline-state operations.
    section = re.search(
        r'^PLATFORM_LIST=""\n.*?^PIPELINERUN_EOF$', source, re.MULTILINE | re.DOTALL
    )
    assert section, f"PipelineRun rendering section not found in {script_name}"
    output = tmp_path / "pipelinerun.yaml"
    env = {
        "PATH": os.environ["PATH"],
        "VERSION_PARSER": str(REPO_ROOT / "scripts" / "parse_rhoai_version.sh"),
        "TARGET_RHOAI_VERSION": version,
        "COMPONENT_NAME": "odh-example",
        "REPO_URL": "https://github.com/example/component",
        "DOCKERFILE_PATH": "docker/Dockerfile.konflux",
        "CONTEXT_PATH_NORMALIZED": ".",
        "RKC_URL": "https://github.com/red-hat-data-services/konflux-central.git",
        "PREFETCH_INPUT": prefetch,
        "PIPELINERUN_PATH": str(output),
    }
    setup = (
        'set -euo pipefail\n'
        'eval "$(bash "$VERSION_PARSER" --version "$TARGET_RHOAI_VERSION")"\n'
        'PLATFORMS=("linux/x86_64" "linux-m2xlarge/arm64")\n'
    )
    subprocess.run(
        ["bash", "-c", setup + section.group(0)],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )
    return yaml.safe_load(output.read_text(encoding="utf-8"))


@pytest.mark.parametrize(
    "script_name",
    ["run_step_add_to_rhoai_okc.sh", "run_step_create_pull_pipelines.sh"],
    ids=["push", "pull"],
)
@pytest.mark.parametrize(
    "version, branch, version_var, rhoai_version",
    [
        ("3.6", "rhoai-3.6", "v3-6", "3.6.0"),
        ("3.6-ea-2", "rhoai-3.6-ea.2", "v3-6-ea-2", "3.6.0-ea.2"),
    ],
    ids=["ga", "ea"],
)
@pytest.mark.parametrize(
    "prefetch",
    ["[]", '[{"type": "gomod", "path": "."}]'],
    ids=["empty-prefetch", "gomod-prefetch"],
)
def test_pipeline_templates_bind_git_auth(
    tmp_path, script_name, version, branch, version_var, rhoai_version, prefetch
):
    data = _render_template(tmp_path, script_name, version, prefetch)
    assert data["apiVersion"] == "tekton.dev/v1"
    assert data["kind"] == "PipelineRun"
    spec = data["spec"]
    bindings = [
        workspace
        for workspace in spec.get("workspaces", [])
        if workspace.get("name") == "git-auth"
    ]
    assert bindings == [
        {"name": "git-auth", "secret": {"secretName": "{{ git_auth_secret }}"}}
    ]

    params = {param["name"]: param["value"] for param in spec["params"]}
    assert params["git-url"] == "{{source_url}}"
    assert params["revision"] == "{{revision}}"
    assert params["dockerfile"] == "docker/Dockerfile.konflux"
    assert params["path-context"] == "."
    assert params["build-platforms"] == ["linux/x86_64", "linux-m2xlarge/arm64"]
    if prefetch == "[]":
        assert "prefetch-input" not in params
    else:
        assert json.loads(params["prefetch-input"]) == json.loads(prefetch)
    pipeline_params = {
        param["name"]: param["value"] for param in spec["pipelineRef"]["params"]
    }
    assert pipeline_params["revision"] == "{{ target_branch }}"
    assert pipeline_params["pathInRepo"] == "pipelines/multi-arch-container-build.yaml"

    if script_name == "run_step_add_to_rhoai_okc.sh":
        assert data["metadata"]["name"] == f"odh-example-{version_var}-on-push"
        assert params["rhoai-version"] == rhoai_version
        assert f'target_branch == "{branch}"' in data["metadata"]["annotations"][
            "pipelinesascode.tekton.dev/on-cel-expression"
        ]
        assert spec["taskRunTemplate"]["serviceAccountName"] == (
            f"build-pipeline-odh-example-{version_var}"
        )
    else:
        assert data["metadata"]["name"] == (
            "odh-example-on-pull-request-{{pull_request_number}}"
        )
        assert spec["taskRunTemplate"]["serviceAccountName"] == (
            "build-pipeline-pull-request-pipelines"
        )
