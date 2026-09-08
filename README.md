# ProAudio Player Firmware

Buildroot firmware integration for ProAudio Player.

The production hardware target of this repository is currently Raspberry Pi 4 Model B (BCM2711, AArch64). QEMU AArch64 is retained only as an integration smoke-test target.

## Repository model

```text
proaudio_player
    platform-independent player core
            │
            ├────────────────────┐
            ▼                    ▼
proaudio_player_docker     proaudio-player-firmware
Docker dev/test            Buildroot / Raspberry Pi 4 Model B
```

This repository contains the embedded platform layer only. The player implementation is pinned as the `sources/proaudio-player` Git submodule.

## Raspberry Pi 4 Model B hardware profile

`proaudio_rpi4_64_defconfig` is an intentionally headless appliance profile.

Display/video:

- no HDMI output;
- no firmware/KMS framebuffer setup;
- no DRM or framebuffer kernel stack;
- no virtual terminal/local graphical console;
- no camera/media kernel stack;
- minimal GPU memory allocation;
- UART remains available for recovery/debugging.

USB host ports are intentionally restricted to storage use:

- USB mass storage and UAS are enabled;
- flash drives and external disks are supported;
- ext4, FAT/VFAT, exFAT and NTFS3 support is retained;
- keyboards, mice, joysticks and HID are disabled;
- USB audio/MIDI is disabled;
- USB serial/RS-232 adapters are disabled;
- USB network adapters are disabled;
- USB printers, test/instrument interfaces, USB/IP and gadget mode are disabled.

The player audio output for this hardware profile is therefore expected to use non-USB hardware, for example an I2S DAC/HAT. The exact DAC overlay can be added once the production DAC is selected.

The relevant platform files are:

```text
br2-external/board/raspberrypi4-64/config.txt
br2-external/board/raspberrypi4-64/linux-headless-storage-only.fragment
br2-external/configs/proaudio_rpi4_64_defconfig
```

## Runtime architecture

`BR2_PACKAGE_PROAUDIO_PLAYER=y` is the product-level Buildroot switch. It installs the pinned core and selects the player runtime: Python, PipeWire/WirePlumber, PulseAudio client compatibility, MPV, MPD/MPC and enabled network audio sources.

AirPlay, DLNA and Spotify Connect are enabled by default. PulseAudio is used only for client/libpulse compatibility; `pipewire-pulse` is the audio server.

The shared `audio-buses.sh` comes from the player core and remains the single implementation of the music and alert buses.

Application services run system-wide under the dedicated `proaudio-player` account. `systemd-timesyncd` provides clock synchronization for HTTPS API access and scheduled events.

## Completely clean Raspberry Pi 4 build

Synchronize all repositories first:

```bash
git switch main
git pull
git submodule sync --recursive
git submodule update --init --recursive
```

Remove all generated Buildroot state and the previous configuration:

```bash
rm -rf upstream/buildroot/output
rm -f upstream/buildroot/.config upstream/buildroot/.config.old
```

Downloaded source archives may remain in `upstream/buildroot/dl`; they are not build state. If a completely cold build including fresh downloads is required, remove that directory as well.

Load the Raspberry Pi 4 Model B configuration:

```bash
make -C upstream/buildroot \
  BR2_EXTERNAL="$PWD/br2-external" \
  proaudio_rpi4_64_defconfig
```

Build:

```bash
make -C upstream/buildroot \
  BR2_EXTERNAL="$PWD/br2-external"
```

The SD-card image is produced under:

```text
upstream/buildroot/output/images/
```

## Verifying the generated kernel configuration

After the kernel has been configured during the build, verify the headless/USB restrictions with:

```bash
grep -E 'CONFIG_(DRM|FB|VT|INPUT|HID|USB_HID|SND_USB_AUDIO|USB_SERIAL|USB_NET_DRIVERS|USB_STORAGE|USB_UAS)=' \
  upstream/buildroot/output/build/linux-*/.config
```

Expected functional state:

```text
CONFIG_USB_STORAGE=y
CONFIG_USB_UAS=y
```

The display/input/USB non-storage options listed above should either be absent or appear as `# CONFIG_... is not set`.

## QEMU smoke test

QEMU is not the production hardware target:

```bash
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external" proaudio_qemu_aarch64_defconfig
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external"
```

## Player source integration

Production builds use the exact revision pinned by `sources/proaudio-player`.

For a temporary local source override:

```make
PROAUDIO_PLAYER_OVERRIDE_SRCDIR = /path/to/proaudio_player
```

and rebuild with:

```bash
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external" proaudio-player-rebuild all
```

## Announcement media

The firmware does not install `espeak-ng`, FFmpeg or compiler toolchains for runtime media generation. Standard announcement MP3 files are copied from the pinned core during image creation.

Runtime media paths:

```text
/var/lib/proaudio-player-alert/media/alarm_start.mp3
/var/lib/proaudio-player-alert/media/alarm_end.mp3
/var/lib/proaudio-player-alert/media/minute_silence.mp3
```

## Runtime data

```text
/etc/proaudio-player-alert/       configuration
/var/lib/proaudio-player-alert/   controller and MPD state
/var/lib/proaudio-player/         Spotify state
/srv/music/                       local music library
```
