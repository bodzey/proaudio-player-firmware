# ProAudio Player Firmware

Buildroot-based firmware for ProAudio Player embedded devices.

## Targets

- QEMU AArch64: `proaudio_qemu_aarch64_defconfig`
- Raspberry Pi 4 / Raspberry Pi 400 / Compute Module 4: `proaudio_rpi4_64_defconfig`

The repository pins both Buildroot and the ProAudio Player application as Git submodules. Docker remains the development/integration-test environment of the application repository; Docker is not installed in the firmware.

## Repository layout

```text
upstream/buildroot/          pinned Buildroot
sources/proaudio-player/     pinned ProAudio Player source
br2-external/                board and package integration
```

`BR2_PACKAGE_PROAUDIO_PLAYER=y` is the product-level Buildroot switch. The package selects the Python runtime, PipeWire/WirePlumber/Pulse compatibility libraries, MPV, MPD/MPC and the enabled network audio sources. AirPlay, DLNA and Spotify Connect are enabled by default and can be disabled through the ProAudio Player menu.

PulseAudio is present only for `libpulse` and client tools such as `pactl`; the PulseAudio daemon is not selected. `pipewire-pulse` is the only Pulse server.

The firmware uses system-wide PipeWire services. ProAudio application services run as the dedicated `proaudio-player` user, which is a member of the `pipewire`, `audio` and `dialout` groups. They connect to the system PipeWire Pulse socket at `/run/pulse/native`.

The audio buses are created only by `audio-buses.sh`. The former static `pulse.cmd` bus definition was removed to avoid duplicate null sinks. The script also detects the physical output and creates both loopbacks to it.

## Build

Initialize the pinned sources:

```bash
git submodule update --init --recursive
```

QEMU AArch64:

```bash
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external" proaudio_qemu_aarch64_defconfig
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external"
```

Raspberry Pi 4 / CM4:

```bash
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external" proaudio_rpi4_64_defconfig
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external"
```

The Raspberry Pi SD-card image is produced in `upstream/buildroot/output/images/` by the upstream Raspberry Pi post-image script.

## Local application development

The normal firmware build uses the pinned `sources/proaudio-player` submodule. For a temporary local checkout, use Buildroot's override mechanism in an output-local `local.mk`, for example:

```make
PROAUDIO_PLAYER_OVERRIDE_SRCDIR = /path/to/proaudio_player
```

Then rebuild the application and image:

```bash
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external" proaudio-player-rebuild all
```

## Announcement media

The source repository currently generates `alarm_start.mp3`, `alarm_end.mp3` and `minute_silence.mp3` with `espeak-ng` and FFmpeg in the Debian/Docker workflow. Those build tools are intentionally not installed in the embedded target.

Until the generated media files are committed or supplied by a firmware provisioning step, copy the three files to:

```text
/var/lib/proaudio-player-alert/media/
```

The alert service contains `ConditionPathExists` checks and therefore stays inactive rather than entering a restart loop when the media have not yet been provisioned.

## Runtime configuration

Application configuration is installed under `/etc/proaudio-player-alert/`. Persistent application/MPD state is kept under `/var/lib/proaudio-player-alert/`, Spotify state under `/var/lib/proaudio-player/`, and the local music library under `/srv/music`.

For the current writable ext4 images these locations persist normally. A future read-only/A-B firmware layout should mount a dedicated persistent data partition over the relevant `/var/lib` and music paths.
