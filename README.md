# ProAudio Player Firmware

Buildroot-based firmware integration for ProAudio Player embedded devices.

The primary hardware target is Raspberry Pi 4 Model B. Raspberry Pi 400 and Compute Module 4 use the same BCM2711/AArch64 Buildroot base and can remain compatible targets. QEMU AArch64 is kept only as a fast smoke-test environment for firmware integration.

## Repository model

ProAudio Player is split into independent layers:

```text
proaudio_player
    core application and shared player runtime resources
            │
            ├───────────────┐
            ▼               ▼
proaudio_player_docker   proaudio-player-firmware
Docker dev/test          Buildroot/Raspberry Pi runtime
```

This repository contains only the embedded/firmware integration layer. It does not contain the application implementation and it does not contain Docker development files.

The player source is pinned as a Git submodule under `sources/proaudio-player/`. Buildroot packages install and integrate that source into the Raspberry Pi root filesystem.

The relative core submodule URL follows the protocol used to clone this repository, so both SSH and HTTPS clones work without rewriting `.gitmodules`.

Current integration revision:

```text
616c41cca43ee9d7cf44483bd2bad5347015b775
```

## Targets

Primary target:

- Raspberry Pi 4 Model B: `proaudio_rpi4_64_defconfig`

Compatible BCM2711 targets:

- Raspberry Pi 400
- Compute Module 4

Integration smoke test:

- QEMU AArch64: `proaudio_qemu_aarch64_defconfig`

## Repository layout

```text
upstream/buildroot/          pinned Buildroot source
sources/proaudio-player/     pinned ProAudio Player core
br2-external/                Buildroot board/package integration
```

`BR2_PACKAGE_PROAUDIO_PLAYER=y` is the product-level Buildroot switch. The package selects the runtime dependencies required by the player: Python, PipeWire/WirePlumber, PulseAudio client compatibility, MPV, MPD/MPC and enabled network audio sources.

AirPlay, DLNA and Spotify Connect are enabled by default and can be disabled through the ProAudio Player Buildroot menu.

PulseAudio is present only for `libpulse` and client tools such as `pactl`; its daemon is not enabled. `pipewire-pulse` is the PulseAudio-compatible server.

The firmware uses system-wide PipeWire services. ProAudio application services run as the dedicated `proaudio-player` user, which belongs to the `pipewire`, `audio` and `dialout` groups. The services connect to the system PipeWire Pulse socket at `/run/pulse/native`. `systemd-timesyncd` synchronizes the clock after boot, which is required for HTTPS API requests and the daily minute-of-silence schedule.

The audio buses are created only by the shared `audio-buses.sh` from the player source. Firmware does not duplicate the bus creation logic. The script detects the physical audio output and creates the music and priority-alert loopbacks.

## Build for Raspberry Pi 4 Model B

Initialize the pinned sources:

```bash
git submodule update --init --recursive
```

Load the Raspberry Pi configuration:

```bash
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external" proaudio_rpi4_64_defconfig
```

Build the firmware:

```bash
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external"
```

The SD-card image is produced under:

```text
upstream/buildroot/output/images/
```

## QEMU smoke test

QEMU is not the production platform. It is available to verify the Buildroot userspace/package integration without writing an SD card:

```bash
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external" proaudio_qemu_aarch64_defconfig
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external"
```

## Player source integration

Production/reproducible firmware builds use the exact commit pinned by the `sources/proaudio-player` submodule.

For temporary local development, Buildroot can override that source tree with an output-local `local.mk`:

```make
PROAUDIO_PLAYER_OVERRIDE_SRCDIR = /path/to/proaudio_player
```

Then rebuild the package and image:

```bash
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external" proaudio-player-rebuild all
```

This keeps Buildroot-specific logic out of the player repository while still allowing rapid firmware testing of local player changes.

## Announcement media

The target firmware intentionally does not install `espeak-ng`, FFmpeg, compiler toolchains or other media-generation dependencies. Buildroot copies the ready-to-use standard announcement media from the pinned core into the image. The Raspberry Pi never synthesizes these files at runtime.

The runtime files are expected at:

```text
/var/lib/proaudio-player-alert/media/alarm_start.mp3
/var/lib/proaudio-player-alert/media/alarm_end.mp3
/var/lib/proaudio-player-alert/media/minute_silence.mp3
```

Replacing these files in a persistent deployment remains supported; rebuilding the standard image always starts from the core defaults.

## Runtime data

Application configuration is installed under `/etc/proaudio-player-alert/`.

Persistent runtime locations are:

```text
/var/lib/proaudio-player-alert/   player/alert and MPD state
/var/lib/proaudio-player/         Spotify state
/srv/music/                       local music library
```

The current writable ext4 image persists these paths normally. A later read-only/A-B firmware design should mount a dedicated persistent data partition over the relevant state and music paths.
