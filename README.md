# ProAudio Player Firmware

Buildroot firmware integration for ProAudio Player.

The production hardware target of this repository is currently Raspberry Pi 4 Model B (BCM2711, AArch64). QEMU AArch64 is the software-integration target for running the same pinned native/WebUI stack without reflashing physical hardware.

## Repository model

```text
proaudio-player-native
    native Rust control plane
            │
            ├────────────────────┐
            ▼                    ▼
proaudio_player_docker     proaudio-player-firmware
Docker dev/test            Buildroot / Raspberry Pi 4 Model B
```

This repository contains the embedded platform layer only. The native player
and its factory announcement media are provided by the
`sources/proaudio-player-native` Git submodule.

Branch pairing is explicit:

- `proaudio-player-firmware/main` is the production branch and pins a stable `proaudio-player-native/main` revision;
- `proaudio-player-firmware/dev` follows the current `origin/dev` revisions of
  native and Web UI before every build;
- Buildroot always remains at the exact gitlink revision recorded by firmware,
  so updating application sources cannot silently change the toolchain.

## Raspberry Pi 4 Model B hardware profile

`proaudio_rpi4_64_native_defconfig` is the native, intentionally headless appliance profile.

Display/video:

- there is no local graphical UI, framebuffer console or virtual terminal;
- VC4/KMS remains enabled only because the HDMI audio codec and HDMI hotplug/ELD path depend on it;
- firmware mode injection is disabled with `disable_fw_kms_setup=1`, so Linux KMS owns HDMI EDID/mode discovery;
- V3D rendering, framebuffer emulation, camera/media and composite-video support are disabled;
- UART remains available in the current development/recovery profile.

Audio/output:

- Raspberry Pi 4 analogue 3.5 mm audio is enabled in high-quality PWM mode;
- legacy `snd_bcm2835` owns only the analogue headphones device;
- HDMI audio is provided by VC4/KMS, not by the legacy `snd_bcm2835` HDMI path;
- standard USB Audio Class devices are enabled;
- generic BCM2835 I2S/simple-card support is retained for a future board-specific DAC profile.

USB host ports are intentionally narrow:

- USB Audio Class devices and hubs are supported;
- USB mass storage/UAS is disabled because the native appliance has no removable-drive mount contract;
- keyboards, mice, joysticks and HID are disabled;
- USB serial/RS-232 and USB network adapters are disabled;
- printers, USB/IP, gadget mode and unrelated USB device classes are disabled.

Appliance resilience on Raspberry Pi 4:

- Raspberry Pi firmware hands an armed hardware watchdog to Linux with a 30-second boot/open deadline;
- systemd services the watchdog with a 20-second runtime deadline and a 2-minute reboot watchdog;
- a kernel panic automatically reboots after 10 seconds;
- SYSTEM and DATA use `noatime` and `errors=remount-ro`; filesystem errors fail safe instead of continuing writes;
- journald is explicitly volatile and capped in RAM, so diagnostic logging does not continuously write to the SD card;
- persistent player/media state remains isolated on the DATA ext4 partition;
- SYSTEM remains read-write because NetworkManager provisioning, SSH host keys and other platform configuration still require mutable system state.

The relevant platform files are:

```text
br2-external/board/raspberrypi4-64/config.txt
br2-external/board/raspberrypi4-64/cmdline.txt
br2-external/board/raspberrypi4-64/linux-headless-usb.fragment
br2-external/board/raspberrypi4-64/linux-analogue-audio.fragment
br2-external/board/raspberrypi4-64/rootfs-overlay/etc/systemd/system.conf.d/20-proaudio-watchdog.conf
br2-external/board/raspberrypi4-64/rootfs-overlay/etc/systemd/journald.conf.d/20-proaudio-volatile.conf
br2-external/configs/proaudio_rpi4_64_native_defconfig
```

## Wi-Fi provisioning

Raspberry Pi 4 Model B uses its onboard Broadcom Wi-Fi through NetworkManager. Ethernet `end0` remains outside NetworkManager and continues to use the normal systemd-networkd DHCP path.

`proaudio-networkd` implements headless provisioning:

1. Ethernet has priority. While Ethernet has a default route, Wi-Fi remains disconnected.
2. If Ethernet is unavailable, the saved `proaudio-wifi` profile is used as the fallback.
3. On a device without a saved Wi-Fi profile, 15 seconds without connectivity starts the setup access point `ProAudio-Player-XXXX`.
4. If a saved Wi-Fi profile later becomes unavailable, provisioning is not exposed automatically; hold the setup button or run `proaudio-networkctl setup`.
5. The setup access point uses WPA protection. The development default is `proaudio-setup`; production/manufacturing may replace it in `/etc/proaudio-networkd.conf`.
6. The setup network does not route Internet/LAN traffic. DHCP and captive DNS direct setup clients to `http://192.168.4.1/`; normal LAN port 80 redirects to the player UI on port 8080.
7. The portal scans nearby Wi-Fi networks, accepts SSID/password and attempts the connection.
8. On success the credentials are saved as `proaudio-wifi` and the setup AP is removed. On failure the protected setup AP returns for another attempt.

A physical recovery/setup button is supported on BCM GPIO26:

```text
Raspberry Pi physical pin 37 (GPIO26) ---- momentary button ---- physical pin 39 (GND)
```

Holding the button for 5 seconds enters Setup Mode. No keyboard or display is required. GPIO is handled through the modern character-device API with `libgpiod`/`gpiomon`; no Python runtime is used.

Setup Mode can also be requested from a shell:

```bash
proaudio-networkctl setup
```

Useful diagnostics:

```bash
proaudio-networkctl status
proaudio-networkctl wifi
proaudio-networkctl connections
proaudio-networkctl logs 200
```

## Runtime architecture

`BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE=y` installs the pinned Rust control plane and selects PipeWire/WirePlumber, PulseAudio client compatibility, MPV, MPD/MPC and enabled network audio engines.

`BR2_PACKAGE_PROAUDIO_NETWORKD=y` is the Raspberry Pi provisioning layer. It owns Wi-Fi/AP switching, captive portal and the GPIO setup button; these platform-specific functions are intentionally kept outside the `proaudio-player-native` core.

AirPlay, DLNA and Spotify Connect are enabled by default. PulseAudio is used only for client/libpulse compatibility; `pipewire-pulse` is the audio server.

The native source arbiter owns ordinary-source exclusivity. The transitional `audio-buses.sh` adapter creates the music and alert buses until direct PipeWire API control replaces command adapters.

Application services run system-wide under the dedicated `proaudio-player` account. `systemd-timesyncd` provides clock synchronization for HTTPS API access and scheduled events.

## Build-host setup

The repository separates privileged host setup from the firmware build:

- `bootstrap-build-host.sh` installs only host tools, initializes pinned
  Buildroot and synchronizes the current native/Web UI `dev` sources;
- `check-build-host.sh` only validates the host and never installs anything;
- `build.sh` never uses `sudo` and performs an incremental build by default.

On Debian/Ubuntu, Fedora/RHEL-compatible systems, Arch, openSUSE or Alpine:

```bash
git clone --branch dev \
  --recurse-submodules \
  https://github.com/bodzey/proaudio-player-firmware.git
cd proaudio-player-firmware
./scripts/bootstrap-build-host.sh -y
```

Run the bootstrap without `-y` if package-manager confirmation is desired.
Add `--with-qemu` only on a development host that needs a system QEMU fallback;
the QEMU profile also builds a host `qemu-system-aarch64` binary inside its
isolated Buildroot output. The script may ask for `sudo`; the build itself must
be run as a regular user.

For an unsupported Linux distribution, or when modifying the host is
undesirable, use the controlled Debian container (Docker or Podman):

```bash
./scripts/build-container.sh
```

The repository and Buildroot download/output caches are bind-mounted, so
subsequent container builds remain incremental. A native Buildroot build
requires Linux; the container route is also the supported entry point from
macOS or Windows hosts running Linux containers.

To validate an already prepared host without changing it:

```bash
./scripts/check-build-host.sh
```

Buildroot remains responsible for downloading and building its own host-side
package tools. The bootstrap installs only the operating-system prerequisites
needed to run Buildroot.

## Raspberry Pi 4 development build

Synchronize the development branch first:

```bash
git switch dev
git pull --ff-only
```

Build the Raspberry Pi 4 image:

```bash
./scripts/build.sh
```

This keeps the pinned Buildroot toolchain, updates native and Web UI to their
current `origin/dev`, validates the host, loads the canonical defconfig and
reuses compatible Buildroot output. It never cleans implicitly. The wrapper
records the successfully built native/Web UI/network revisions and automatically
invalidates only a local-source package whose source revision changed. An
existing output created before this mechanism gets one conservative refresh
of those local packages to establish the baseline.

After changing one of the local project components, invalidate only that
Buildroot package before continuing the normal image build:

```bash
./scripts/build.sh --rebuild native
./scripts/build.sh --rebuild webui
./scripts/build.sh --rebuild network
./scripts/build.sh --rebuild native --rebuild webui
```

Use `--jobs NUMBER` to control parallelism, `--configure-only` to load the
profile without compiling, or an out-of-tree output directory to keep builds
separate:

```bash
./scripts/build.sh --output /path/to/proaudio-rpi4-output
```

The SD-card image is produced under:

```text
upstream/buildroot/output/images/
```

A full clean build is not required after ordinary firmware, player or Web UI
changes. Use it only to recover from stale or incompatible Buildroot output,
for example after changing toolchain/architecture or when an incremental
build demonstrably fails:

```bash
./scripts/build.sh --clean
```

`--clean` runs Buildroot `distclean`, reloads the canonical profile and then
rebuilds every selected package. Downloaded source archives in `dl/` are kept;
they are an input cache rather than compiled build state.

## Verifying the generated kernel configuration

After the kernel has been configured during the build:

```bash
grep -E 'CONFIG_(DRM|FB|VT|INPUT|HID|USB_HID|SND_USB_AUDIO|SND_BCM2835|USB_SERIAL|USB_NET_DRIVERS|USB_STORAGE|USB_UAS|BRCMFMAC|GPIO_CDEV)=' \
  upstream/buildroot/output/build/linux-*/.config
```

Expected functional state includes analogue Pi audio, HDMI audio through VC4/KMS, USB Audio Class, generic I2S/simple-card support, Broadcom Wi-Fi and GPIO character-device support. Display/input, USB mass storage and unrelated USB classes should remain disabled.

## QEMU AArch64 integration target

QEMU runs the same pinned `proaudio-player-native` and `proaudio-player-webui`
revisions as the Raspberry Pi development firmware. The target deliberately
excludes Raspberry Pi provisioning/GPIO policy and injects one QEMU-only
`qemu_virtual_dac` null sink outside the native core. That gives the normal
`MUSIC -> MASTER -> physical output` routing code a deterministic output to
exercise without pretending to emulate Raspberry Pi audio hardware.

The QEMU profile uses a separate output tree by default:

```text
$HOME/build/proaudio-qemu
```

Build and start it with:

```bash
./scripts/build.sh --profile qemu-aarch64 --no-submodules
./scripts/run-qemu.sh
```

The first QEMU build is independent from the Raspberry Pi output and therefore
builds its own kernel/rootfs/tooling. Later builds are incremental. The launcher
uses the Buildroot-built `qemu-system-aarch64` when available and otherwise
falls back to the host binary.

Default launcher behaviour:

- AArch64 `virt` machine with Cortex-A53 CPU, 2 vCPUs and 1 GiB RAM;
- rootfs changes are discarded on exit (`QEMU_SNAPSHOT=1`) so the built image
  remains clean;
- QEMU user networking forwards guest port 8080 to
  `http://127.0.0.1:18080/`;
- `qemu_virtual_dac` is created through PipeWire-Pulse before the normal bus
  graph starts;
- the serial console is attached to the terminal; `Ctrl-A X` exits QEMU.

Useful overrides:

```bash
QEMU_WEB_PORT=18081 ./scripts/run-qemu.sh
QEMU_SNAPSHOT=0 ./scripts/run-qemu.sh
QEMU_MEMORY_MB=2048 QEMU_SMP=4 ./scripts/run-qemu.sh
```

User-mode QEMU networking is suitable for WebUI/API, mixer, alert, MPD, bus and
service integration tests, but it does not reproduce LAN multicast discovery.
For AirPlay/Spotify/DLNA discovery testing, attach the VM to an already prepared
host TAP interface:

```bash
QEMU_NET_MODE=tap QEMU_TAP_IF=tap0 ./scripts/run-qemu.sh
```

TAP/bridge creation remains a host-administration task and is intentionally not
performed by the unprivileged firmware scripts.

Inside the VM, useful checks are:

```bash
proaudio-version
systemctl --failed --no-pager
pactl list short sinks
pactl list short sink-inputs
```

The expected physical test sink is `qemu_virtual_dac`; the normal logical sinks
remain `proaudio_player_music`, `proaudio_player_alert`,
`proaudio_player_master` and `proaudio_player_parking`.

QEMU validates software integration. Raspberry Pi-specific PWM/HDMI/I2S/USB
hardware, device-tree policy, real hotplug timing and abrupt SD-card power-loss
behaviour still require physical hardware validation.

## Player source integration

Native firmware builds use the exact revision pinned by `sources/proaudio-player-native`.

For a temporary local source override:

```make
PROAUDIO_PLAYER_NATIVE_OVERRIDE_SRCDIR = /path/to/proaudio-player-native
```

and rebuild with:

```bash
./scripts/build.sh --rebuild native
```

## Announcement media

The firmware does not install `espeak-ng`, FFmpeg or compiler toolchains for runtime media generation. Standard announcement MP3 files are copied from the pinned core during image creation.

Runtime media paths:

```text
/var/lib/proaudio-player-alert/media/alarm_start.mp3
/var/lib/proaudio-player-alert/media/alarm_end.mp3
/var/lib/proaudio-player-alert/media/minute_silence.mp3
```

## Storage layout and first boot

The Raspberry Pi image has three MBR partitions with a fixed disk signature:

- a 32 MiB FAT boot partition;
- a fixed 768 MiB ext4 SYSTEM partition labelled `PROAUDIO_SYSTEM`;
- a minimal 64 MiB ext4 DATA partition labelled `PROAUDIO_DATA`.

The kernel locates SYSTEM by its stable partition UUID
(`PARTUUID=50524155-02`), so booting does not depend on names such as
`/dev/mmcblk0`. The same layout works on SD, eMMC, NVMe and USB/SATA media.

On first boot, `proaudio-storage.service` verifies that SYSTEM and DATA are
direct partitions on the same boot disk and that DATA is the last partition.
Only after those checks does it extend partition 3 to the remaining capacity.
It then requests one automatic reboot. On the next boot it grows the ext4
filesystem and initializes the persistent directory layout.

If another partition follows DATA, the service preserves the partition table
and uses the existing DATA size. It never guesses a device name and never
resizes SYSTEM. This isolates firmware capacity from user media growth and
prevents a full music library from filling the operating-system filesystem.

Application paths remain stable through systemd bind mounts into DATA:

```text
/srv/music                         -> /data/music
/var/lib/proaudio-player           -> /data/player
/var/lib/proaudio-player-alert     -> /data/player-alert
```

Factory announcement files live read-only under
`/usr/share/proaudio-player/announcements`. Missing files are copied into
DATA once; user replacements are never overwritten.

Verification after the automatic first-boot reboot:

```bash
findmnt / /data
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTUUID,MOUNTPOINTS
df -h / /data
systemctl status data.mount proaudio-storage.service --no-pager
journalctl -b -u data.mount -u proaudio-storage.service --no-pager
findmnt /srv/music /var/lib/proaudio-player /var/lib/proaudio-player-alert
```

This partition-layout change requires writing the new `sdcard.img`; it is not
an in-place package update for devices flashed with the former two-partition
image.

## Runtime data

```text
/etc/proaudio-player-alert/       player configuration (SYSTEM)
/etc/proaudio-networkd.conf       Wi-Fi provisioning configuration (SYSTEM)
/var/lib/NetworkManager/          saved NetworkManager state (SYSTEM)
/etc/NetworkManager/system-connections/ saved Wi-Fi profiles (SYSTEM)
/data/player-alert/               controller, MPD state and alert media (DATA)
/data/player/                     persistent player state (DATA)
/data/music/                      local music library (DATA)
```
