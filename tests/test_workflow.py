import re
from pathlib import Path

WORKFLOW = Path(__file__).parents[1] / ".github" / "workflows" / "release.yml"


def test_release_workflow_has_safe_triggers_and_concurrency() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "schedule:" in text
    assert "workflow_dispatch:" in text
    assert "concurrency:" in text
    assert "cancel-in-progress: false" in text
    assert "pull_request:" not in text


def test_release_workflow_pins_actions_and_keeps_read_permissions() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    actions = re.findall(r"uses: ([^\s]+)@([^\s]+)", text)
    assert actions
    assert all(re.fullmatch(r"[0-9a-f]{40}", sha) for _, sha in actions)
    assert "permissions:\n  contents: read" in text
    assert "actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9" in text


def test_release_workflow_has_double_opt_in_protected_publish_gate() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "publish:" in text
    assert "vars.F1SQL_RELEASE_BUNDLE_READY == 'true'" in text
    assert "inputs.dry_run != true" in text
    assert "name: production" in text
    assert "permissions:\n      contents: write" in text
    assert "gh release create" in text
    assert '--notes-file "release-bundle/$TARGET/release-notes.md"' in text
    assert "--generate-notes" not in text
    assert "release-bundle" in text


def test_release_workflow_separates_detection_from_validation() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "  detect:" in text
    assert "  validation:" in text
    assert "needs: detect" in text
    assert "needs.detect.outputs.ready == 'true'" in text
    assert "  build:" in text
    assert "  restore_forward:" in text
    assert "scripts/build_live_candidate.py" in text
    assert "scripts/package_candidate_release.py" in text
    assert "needs: [detect, validation, build, restore_forward]" in text
    assert "repository: F1-SQL/f1-sql-database" not in text
    assert "--database-repository" not in text


def test_security_automation_is_pinned_and_read_only() -> None:
    workflow = WORKFLOW.parent / "security.yml"
    text = workflow.read_text(encoding="utf-8")
    assert "python -m pip install pip-audit==2.9.0" in text
    assert "pip-audit --strict ." in text
    assert "python -m pip install . pip-audit" not in text
    assert "permissions:\n  contents: read" in text
    assert all(
        re.fullmatch(r"[0-9a-f]{40}", sha)
        for _, sha in re.findall(r"uses: ([^\s]+)@([^\s]+)", text)
    )
    dependabot = WORKFLOW.parent.parent / "dependabot.yml"
    assert "package-ecosystem: pip" in dependabot.read_text(encoding="utf-8")


def test_sqlserver_workflow_has_2019_build_and_2022_restore_forward_jobs() -> None:
    workflow = WORKFLOW.parent / "sqlserver.yml"
    text = workflow.read_text(encoding="utf-8")
    assert "sqlserver-2019:" in text
    assert "sqlserver-2022:" in text
    assert "needs: sqlserver-2019" in text
    assert "scripts/sqlserver_integration.sh" in text
    assert "scripts/sqlserver_restore_forward.sh" in text
    assert "openssl rand -hex 16" in text
    assert "F1SqlPhase5!2026" not in text
    actions = re.findall(r"uses: ([^\s]+)@([^\s]+)", text)
    assert all(re.fullmatch(r"[0-9a-f]{40}", sha) for _, sha in actions)


def test_python_workflow_uses_monorepo_checkout() -> None:
    workflow = WORKFLOW.parent / "python.yml"
    text = workflow.read_text(encoding="utf-8")
    assert "f1-sql-database" not in text
    actions = re.findall(r"uses: ([^\s]+)@([^\s]+)", text)
    assert all(re.fullmatch(r"[0-9a-f]{40}", sha) for _, sha in actions)
