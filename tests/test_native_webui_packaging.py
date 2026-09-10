from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NATIVE_PACKAGE = ROOT / "br2-external/package/proaudio-player-native"
WEBUI_PACKAGE = ROOT / "br2-external/package/proaudio-webui"
NATIVE_DEFCONFIG = ROOT / "br2-external/configs/proaudio_rpi4_64_native_defconfig"


def test_webui_is_an_explicit_optional_package_separate_from_native_player():
    external_config = (ROOT / "br2-external/Config.in").read_text(encoding="utf-8")
    native_makefile = (NATIVE_PACKAGE / "proaudio-player-native.mk").read_text(encoding="utf-8")
    webui_config = (WEBUI_PACKAGE / "Config.in").read_text(encoding="utf-8")
    webui_makefile = (WEBUI_PACKAGE / "proaudio-webui.mk").read_text(encoding="utf-8")
    native_defconfig = NATIVE_DEFCONFIG.read_text(encoding="utf-8")

    assert "package/proaudio-webui/Config.in" in external_config
    assert "BR2_PACKAGE_PROAUDIO_WEBUI" in webui_config
    assert "default y" not in webui_config
    assert "sources/proaudio-player-native/webui" in webui_makefile
    assert "git submodule update --init --recursive" in webui_makefile
    assert "/usr/share/proaudio-player/webui" in webui_makefile

    # This development image explicitly opts into the frontend.
    assert "BR2_PACKAGE_PROAUDIO_WEBUI=y" in native_defconfig

    # With the Kconfig symbol unset, Buildroot must not select/package Web UI.
    # The native control plane itself has no build dependency on frontend assets.
    assert "proaudio-webui" not in native_makefile.lower()
    assert "/webui" not in native_makefile.lower()
