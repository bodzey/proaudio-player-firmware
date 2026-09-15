from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "br2-external/package/proaudio-networkd"


def test_ap_to_station_patch_applies_and_serializes_scans(tmp_path):
    source = PACKAGE / "proaudio-networkd"
    patch_file = PACKAGE / "0001-stabilize-ap-to-station-provisioning.patch"
    work_source = tmp_path / "proaudio-networkd"
    work_source.write_bytes(source.read_bytes())

    result = subprocess.run(
        ["patch", "--batch", "--forward", "-p1", "--directory", str(tmp_path)],
        input=patch_file.read_text(encoding="utf-8"),
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr

    patched = work_source.read_text(encoding="utf-8")
    assert "def _prepare_station_connection(self, ssid):" in patched
    assert '"device", "wifi", "rescan", "ifname", self.iface' in patched
    assert '"ssid", ssid' in patched
    assert 'args += ["hidden", "yes"]' in patched
    assert "visible = self._prepare_station_connection(ssid)" in patched

    failure_tail = patched.split(
        'LOG.warning("Wi-Fi provisioning failed for %s: %s", ssid, error)', 1
    )[1].split("except Exception as exc:", 1)[0]
    assert "self.scan()" not in failure_tail
    assert "self.start_ap()" in failure_tail
