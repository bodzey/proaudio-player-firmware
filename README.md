# ProAudio Player Firmware

Buildroot firmware integration for ProAudio Player.

The production hardware target of this repository is currently Raspberry Pi 4 Model B (BCM2711, AArch64). QEMU AArch64 is retained only as an integration smoke-test target.

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

This repository contains the embedded platform layer only. The native player is pinned as the `sources/proaudio-player-native` Git submodule. The legacy `sources/proaudio-player` submodule is temporarily retained only as the source of standard announcement MP3 assets.

## Raspberry Pi 4 Model B hardware profile

`proaudio_rpi4_64_native_defconfig` is the native, intentionally headless appliance profile.

Display/video:

- no HDMI output;
- no firmware/KMS framebuffer setup;
- no DRM or framebuffer kernel stack;
- no virtual terminal/local graphical console;
- no camera/media kernel stack;
- minimal GPU memory allocation;
- UART remains available for recovery/debugging.

Audio/output:

- Raspberry Pi 4 analogue 3.5 mm audio is enabled;
- standard USB Audio Class devices are enabled;
- HDMI audio remains unavailable because HDMI output is disabled;
- an I2S DAC/HAT can be added later without changing the player core.

USB host ports are restricted to the device classes required by the appliance:

- USB Audio Class is allowed;
- USB mass storage and UAS are allowed;
- flash drives and external disks are supported;
- ext4, FAT/VFAT, exFAT and NTFS3 support is retained;
- keyboards, mice, joysticks and HID are disabled;
- USB serial/RS-232 adapters are disabled;
- USB network adapters are disabled;
- USB printers, test/instrument interfaces, USB/IP and gadget mode are disabled.

The relevant platform files are:

```text
br2-external/board/raspberrypi4-64/config.txt
br2-external/board/raspberrypi4-64/linux-headless-usb.fragment
br2-external/board/raspberrypi4-64/rootfs-overlay/etc/udev/rules.d/10-proaudio-usb-allowlist.rules
br2-external/configs/proaudio_rpi4_64_native_defconfig
```

## Wi-Fi provisioning

Raspberry Pi 4 Model B uses its onboard Broadcom Wi-Fi through NetworkManager. Ethernet `end0` remains outside NetworkManager and continues to use the normal systemd-networkd DHCP path.

`proaudio-networkd` implements headless provisioning:

1. Ethernet has priority. While Ethernet has a default route, Wi-Fi remains disconnected.
2. If Ethernet is unavailable, the saved `proaudio-wifi` profile is used as the fallback.
3. Only when neither Ethernet nor saved Wi-Fi provides a route, it creates the setup access point `ProAudio-Player-XXXX`.
4. The setup access point intentionally has no Wi-Fi password and does not route Internet/LAN traffic.
5. DHCP and captive DNS direct setup clients to `http://192.168.4.1/`; normal LAN port 80 redirects to the player UI on port 8080.
6. The portal scans nearby Wi-Fi networks, accepts SSID/password and attempts the connection.
7. On success the credentials are saved as `proaudio-wifi` and the setup AP is removed.
8. On failure the setup AP returns and allows another attempt.

A physical recovery/setup button is supported on BCM GPIO26:

```text
Raspberry Pi physical pin 37 (GPIO26) ---- momentary button ---- physical pin 39 (GND)
```

Holding the button for 5 seconds enters Setup Mode. No keyboard or display is required. GPIO is handled through the modern character-device API (`python-gpiod`), not deprecated sysfs GPIO.

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

`BR2_PACKAGE_PROAUDIO_NETWORKD=y` is the Raspberry Pi provisioning layer. It owns Wi-Fi/AP switching, captive portal and the GPIO setup button; these platform-specific functions are intentionally kept outside `proaudio_player` core.

AirPlay, DLNA and Spotify Connect are enabled by default. PulseAudio is used only for client/libpulse compatibility; `pipewire-pulse` is the audio server.

The native source arbiter owns ordinary-source exclusivity. The transitional `audio-buses.sh` adapter creates the music and alert buses until direct PipeWire API control replaces command adapters.

Application services run system-wide under the dedicated `proaudio-player` account. `systemd-timesyncd` provides clock synchronization for HTTPS API access and scheduled events.

## Completely clean Raspberry Pi 4 build

Synchronize all repositories first:

```bash
git switch native
git pull
git submodule sync --recursive
git submodule update --init --recursive
```

Remove all generated Buildroot state and the previous configuration:

```bash
rm -rf upstream/buildroot/output
rm -f upstream/buildroot/.config upstream/buildroot/.config.old
```

Downloaded source archives may remain in `upstream/buildroot/dl`; they are not build state.

Load the Raspberry Pi 4 Model B configuration:

```bash
make -C upstream/buildroot \
  BR2_EXTERNAL="$PWD/br2-external" \
  proaudio_rpi4_64_defconfig
```

Build:

```bash
make -j8 -C upstream/buildroot \
  BR2_EXTERNAL="$PWD/br2-external"
```

The SD-card image is produced under:

```text
upstream/buildroot/output/images/
```

## Verifying the generated kernel configuration

After the kernel has been configured during the build:

```bash
grep -E 'CONFIG_(DRM|FB|VT|INPUT|HID|USB_HID|SND_USB_AUDIO|SND_BCM2835|USB_SERIAL|USB_NET_DRIVERS|USB_STORAGE|USB_UAS|BRCMFMAC|GPIO_CDEV)=' \
  upstream/buildroot/output/build/linux-*/.config
```

Expected functional state includes USB storage, USB audio, analogue Pi audio, Broadcom Wi-Fi and GPIO character-device support. Display/input and unwanted USB classes should remain disabled.

## QEMU smoke test

QEMU is not the production hardware target:

```bash
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external" proaudio_qemu_aarch64_defconfig
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external"
```

## Player source integration

Native firmware builds use the exact revision pinned by `sources/proaudio-player-native`.

For a temporary local source override:

```make
PROAUDIO_PLAYER_NATIVE_OVERRIDE_SRCDIR = /path/to/proaudio-player-native
```

and rebuild with:

```bash
make -C upstream/buildroot BR2_EXTERNAL="$PWD/br2-external" proaudio-player-native-rebuild all
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
/etc/proaudio-player-alert/       player configuration
/etc/proaudio-networkd.conf       Wi-Fi provisioning configuration
/var/lib/NetworkManager/          saved NetworkManager state
/etc/NetworkManager/system-connections/ saved Wi-Fi profiles
/var/lib/proaudio-player-alert/   controller and MPD state
/var/lib/proaudio-player/         Spotify state
/srv/music/                       local music library
```
