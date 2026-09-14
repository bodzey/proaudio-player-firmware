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
    assert "submodule update --init --recursive" in script
    assert "submodule update --remote" not in script
    assert "rev-parse --is-inside-work-tree" in script
    assert "if ((CLEAN)); then" in script
    assert 'make "${make_args[@]}" clean' in script
    assert "proaudio-player-native-dirclean" in script
    assert "proaudio-webui-dirclean" in script
    assert "proaudio-networkd-dirclean" in script
    assert "flock -n 9" in script


def test_host_check_defers_authoritative_requirements_to_buildroot():
    script = (SCRIPTS / "check-build-host.sh").read_text(encoding="utf-8")
    assert 'command -v "$command_name"' in script
    assert 'BR2_EXTERNAL="$BR2_EXTERNAL_DIR" dependencies' in script
    assert "Do not build Buildroot as root" in script
    assert "case-insensitive" in script


def test_bootstrap_supports_major_linux_package_families_and_never_builds():
    script = (SCRIPTS / "bootstrap-build-host.sh").read_text(encoding="utf-8")
    for package_manager in ("apt-get", "dnf", "pacman", "zypper", "apk"):
        assert package_manager in script
    assert "util-linux" in script
    assert "submodule update --init --recursive" in script
    assert "submodule update --remote" not in script
    assert "make -j" not in script


def test_container_builder_preserves_unprivileged_output_ownership():
    wrapper = (SCRIPTS / "build-container.sh").read_text(encoding="utf-8")
    dockerfile = (ROOT / "containers/Dockerfile.build").read_text(encoding="utf-8")
    assert '--user "$(id -u):$(id -g)"' in wrapper
    assert "EUID == 0" in wrapper
    assert "rev-parse --is-inside-work-tree" in wrapper
    assert "util-linux" in dockerfile
    assert 'ENTRYPOINT ["./scripts/build.sh", "--no-submodules"]' in dockerfile
