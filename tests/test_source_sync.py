import os
import shutil
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATHS = (
    "sources/proaudio-player-native",
    "sources/proaudio-player-webui",
)


@pytest.fixture
def checkout(tmp_path):
    env = {
        **os.environ,
        "GIT_ALLOW_PROTOCOL": "file",
        "GIT_AUTHOR_NAME": "Source sync test",
        "GIT_AUTHOR_EMAIL": "source-sync@example.invalid",
        "GIT_COMMITTER_NAME": "Source sync test",
        "GIT_COMMITTER_EMAIL": "source-sync@example.invalid",
    }

    def git(path, *args):
        return subprocess.run(
            ["git", "-C", str(path), *args],
            env=env, check=True, text=True, capture_output=True,
        ).stdout.strip()

    firmware = tmp_path / "firmware"
    firmware.mkdir()
    git(firmware, "init", "-q", "-b", "dev")
    scripts = firmware / "scripts"
    scripts.mkdir()
    shutil.copy2(ROOT / "scripts/sync-dev-submodules.sh", scripts)

    remotes = {}
    for path in (*SOURCE_PATHS, "upstream/buildroot"):
        remote = tmp_path / Path(path).name
        remote.mkdir()
        git(remote, "init", "-q", "-b", "dev")
        (remote / "tracked.txt").write_text("initial\n", encoding="utf-8")
        git(remote, "add", ".")
        git(remote, "commit", "-qm", "initial")
        branch = ("-b", "dev") if path in SOURCE_PATHS else ()
        git(firmware, "submodule", "add", "-q", *branch, str(remote), path)
        remotes[path] = remote
    git(firmware, "add", ".")
    git(firmware, "commit", "-qm", "firmware")

    def sync():
        return subprocess.run(
            [scripts / "sync-dev-submodules.sh"],
            env=env, text=True, capture_output=True,
        )

    return firmware, remotes, git, sync


def test_source_preflight_preserves_both_checkouts(checkout):
    firmware, remotes, git, sync = checkout
    original = {
        path: git(firmware / path, "rev-parse", "HEAD") for path in remotes
    }
    for remote in remotes.values():
        (remote / "tracked.txt").write_text(
            "remote update\n", encoding="utf-8"
        )
        git(remote, "commit", "-qam", "update")

    webui = firmware / SOURCE_PATHS[1]
    (webui / "tracked.txt").write_text("local edit\n", encoding="utf-8")
    result = sync()
    assert result.returncode != 0
    assert "local changes" in result.stderr
    assert (webui / "tracked.txt").read_text(
        encoding="utf-8"
    ) == "local edit\n"
    for path, revision in original.items():
        assert git(firmware / path, "rev-parse", "HEAD") == revision

    git(webui, "restore", "tracked.txt")
    (webui / "untracked.txt").write_text("local file\n", encoding="utf-8")
    result = sync()
    assert result.returncode != 0
    assert "local changes" in result.stderr
    assert (webui / "untracked.txt").exists()
    (webui / "untracked.txt").unlink()

    git(webui, "commit", "-qm", "unpublished", "--allow-empty")
    local_commit = git(webui, "rev-parse", "HEAD")
    result = sync()
    assert result.returncode != 0
    assert "commits outside origin/dev" in result.stderr
    assert git(webui, "rev-parse", "HEAD") == local_commit
    assert git(firmware / SOURCE_PATHS[0], "rev-parse", "HEAD") == (
        original[SOURCE_PATHS[0]]
    )
    assert git(firmware / "upstream/buildroot", "rev-parse", "HEAD") == (
        original["upstream/buildroot"]
    )


def test_initial_sync_accepts_parent_changes_and_keeps_buildroot_pinned(
    checkout,
):
    firmware, remotes, git, sync = checkout
    buildroot = git(firmware / "upstream/buildroot", "rev-parse", "HEAD")
    for remote in remotes.values():
        (remote / "tracked.txt").write_text(
            "remote update\n", encoding="utf-8"
        )
        git(remote, "commit", "-qam", "update")
    git(firmware, "submodule", "deinit", "-q", "-f", "--all")
    (firmware / "untracked.txt").write_text("parent edit\n", encoding="utf-8")

    result = sync()
    assert result.returncode == 0, result.stderr
    for path in SOURCE_PATHS:
        assert git(firmware / path, "rev-parse", "HEAD") == git(
            remotes[path], "rev-parse", "HEAD"
        )
    assert git(
        firmware / "upstream/buildroot", "rev-parse", "HEAD"
    ) == buildroot
    assert (firmware / "untracked.txt").exists()
