import os
import stat
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


BUILD_SCRIPTS = (
    SCRIPTS / "check-build-host.sh",
    SCRIPTS / "bootstrap-build-host.sh",
    SCRIPTS / "build.sh",
    SCRIPTS / "build-container.sh",
    SCRIPTS / "sync-dev-submodules.sh",
)


def test_build_scripts_are_executable_and_valid_bash():
    for script in BUILD_SCRIPTS:
        assert script.stat().st_mode & stat.S_IXUSR
        subprocess.run(["bash", "-n", script], check=True)


def test_build_script_help_works_without_initialized_submodules():
    result = subprocess.run(
        [SCRIPTS / "build.sh", "--help"],
        check=True,
        text=True,
        capture_output=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    assert "The default build is incremental" in result.stdout
    assert "--rebuild native|webui|network" in result.stdout


def test_incremental_build_requires_explicit_cleanup_and_pinned_submodules():
    script = (SCRIPTS / "build.sh").read_text(encoding="utf-8")
    assert "rm -rf" not in script
    assert '"$ROOT_DIR/scripts/sync-dev-submodules.sh"' in script
    assert "if ((CLEAN)); then" in script
    assert 'make "${make_args[@]}" clean' in script
    assert "proaudio-player-native-dirclean" in script
    assert "proaudio-webui-dirclean" in script
    assert "proaudio-networkd-dirclean" in script
    assert "flock -n 9" in script
    assert ".proaudio-source-revisions" in script
    assert "previous_native" in script
    assert "previous_webui" in script
    assert "previous_network" in script
    assert "HEAD:br2-external/package/proaudio-player-native" in script
    assert "HEAD:br2-external/package/proaudio-webui" in script
    assert "HEAD:br2-external/package/proaudio-networkd" in script
    assert 'mv -f "$state_tmp" "$state_file"' in script


def test_host_check_defers_authoritative_requirements_to_buildroot():
    script = (SCRIPTS / "check-build-host.sh").read_text(encoding="utf-8")
    assert 'command -v "$command_name"' in script
    assert "configuration-specific checks run during build" in script
    assert " dependencies" not in script
    assert "Do not build Buildroot as root" in script
    assert "case-insensitive" in script

    build = (SCRIPTS / "build.sh").read_text(encoding="utf-8")
    assert 'make -s "${make_args[@]}" dependencies' in build
    assert build.index('"$defconfig"') < build.index('"${make_args[@]}" dependencies')


def test_bootstrap_supports_major_linux_package_families_and_never_builds():
    script = (SCRIPTS / "bootstrap-build-host.sh").read_text(encoding="utf-8")
    for package_manager in ("apt-get", "dnf", "pacman", "zypper", "apk"):
        assert package_manager in script
    assert "util-linux" in script
    assert '"$ROOT_DIR/scripts/sync-dev-submodules.sh"' in script
    assert "make -j" not in script


def test_source_sync_follows_dev_but_keeps_buildroot_pinned():
    script = (SCRIPTS / "sync-dev-submodules.sh").read_text(encoding="utf-8")
    assert "submodule update --init --recursive upstream/buildroot" in script
    assert 'submodule update --init --remote --checkout "$path"' in script
    assert '[[ "$branch" != dev ]]' in script
    assert "refs/remotes/origin/dev" in script
    assert "status --porcelain" in script
    assert "Buildroot submodule has local changes" in script


def test_container_builder_preserves_unprivileged_output_ownership():
    wrapper = (SCRIPTS / "build-container.sh").read_text(encoding="utf-8")
    dockerfile = (ROOT / "containers/Dockerfile.build").read_text(encoding="utf-8")
    assert '--user "$(id -u):$(id -g)"' in wrapper
    assert "EUID == 0" in wrapper
    assert '"$ROOT_DIR/scripts/sync-dev-submodules.sh"' in wrapper
    assert "util-linux" in dockerfile
    assert 'ENTRYPOINT ["./scripts/build.sh", "--no-submodules"]' in dockerfile
