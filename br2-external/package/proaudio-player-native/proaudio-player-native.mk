################################################################################
#
# proaudio-player-native
#
################################################################################

PROAUDIO_PLAYER_NATIVE_VERSION = 0.1.0
PROAUDIO_PLAYER_NATIVE_SITE = $(BR2_EXTERNAL_PROAUDIO_PATH)/../sources/proaudio-player-native
PROAUDIO_PLAYER_NATIVE_SITE_METHOD = local
PROAUDIO_PLAYER_NATIVE_LICENSE = MIT
PROAUDIO_PLAYER_NATIVE_DEPENDENCIES = \
	alsa-lib \
	alsa-utils \
	avahi \
	bash \
	ca-certificates \
	dbus \
	mpd \
	mpd-mpc \
	mpv \
	pipewire \
	pulseaudio \
	systemd \
	wireplumber

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_AIRPLAY),y)
PROAUDIO_PLAYER_NATIVE_DEPENDENCIES += proaudio-shairport-sync
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_DLNA),y)
PROAUDIO_PLAYER_NATIVE_DEPENDENCIES += \
	gmrender-resurrect \
	gst1-libav \
	gst1-plugins-good
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_SPOTIFY),y)
PROAUDIO_PLAYER_NATIVE_DEPENDENCIES += proaudio-spotifyd
endif

# cargo-package normally vendors crates during Buildroot's download step. This
# package intentionally uses SITE_METHOD=local so the firmware builds the exact
# pinned submodule working tree; local packages do not go through that download
# post-processing path. Vendor the locked dependency graph once in the synced
# build directory so the standard cargo-package --offline build/install steps
# remain reproducible and do not resolve dependencies on their own.
define PROAUDIO_PLAYER_NATIVE_VENDOR_CRATES
	if [ ! -d "$(@D)/VENDOR" ]; then \
		cd "$(@D)" && \
		PATH="$(HOST_DIR)/bin:$$PATH" \
		CARGO_HOME="$(DL_DIR)/br-cargo-home" \
		"$(HOST_DIR)/bin/cargo" vendor --locked VENDOR; \
	fi
	mkdir -p "$(@D)/.cargo"
	printf '%s\n' \
		'[source.crates-io]' \
		'replace-with = "vendored-sources"' \
		'' \
		'[source.vendored-sources]' \
		'directory = "VENDOR"' \
		> "$(@D)/.cargo/config.toml"
endef

PROAUDIO_PLAYER_NATIVE_PRE_BUILD_HOOKS += PROAUDIO_PLAYER_NATIVE_VENDOR_CRATES

define PROAUDIO_PLAYER_NATIVE_USERS
	proaudio-player -1 proaudio-player -1 * /var/lib/proaudio-player /bin/false audio,pipewire ProAudio Player
endef

define PROAUDIO_PLAYER_NATIVE_PERMISSIONS
	/etc/proaudio-player-alert/config.yaml f 640 root proaudio-player - - - - -
	/etc/proaudio-player-alert/alerts-token f 600 proaudio-player proaudio-player - - - - -
	/var/lib/proaudio-player-alert/provider-settings.yaml f 600 proaudio-player proaudio-player - - - - -
	/var/lib/proaudio-player-alert/audio-settings.yaml f 600 proaudio-player proaudio-player - - - - -
endef

define PROAUDIO_PLAYER_NATIVE_INSTALL_RUNTIME_LAYOUT
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/etc/proaudio-player-alert
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/etc/avahi/services
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/usr/share/proaudio-player/announcements
	$(INSTALL) -D -m 0644 $(@D)/config/config.yaml.example \
		$(TARGET_DIR)/etc/proaudio-player-alert/config.yaml
	$(INSTALL) -D -m 0644 $(@D)/config/audio.env.example \
		$(TARGET_DIR)/etc/proaudio-player-alert/audio.env
	$(INSTALL) -D -m 0644 $(@D)/config/mpd.conf \
		$(TARGET_DIR)/etc/proaudio-player-alert/mpd.conf
	$(INSTALL) -D -m 0644 $(@D)/config/shairport-sync.conf \
		$(TARGET_DIR)/etc/proaudio-player-alert/shairport-sync.conf
	$(INSTALL) -D -m 0644 $(@D)/config/spotifyd.conf \
		$(TARGET_DIR)/etc/proaudio-player-alert/spotifyd.conf
	$(INSTALL) -D -m 0644 $(@D)/config/avahi/proaudio-linkplay.service \
		$(TARGET_DIR)/etc/avahi/services/proaudio-linkplay.service
	$(INSTALL) -D -m 0600 /dev/null \
		$(TARGET_DIR)/etc/proaudio-player-alert/alerts-token
	$(INSTALL) -D -m 0600 /dev/null \
		$(TARGET_DIR)/var/lib/proaudio-player-alert/provider-settings.yaml
	$(INSTALL) -D -m 0600 /dev/null \
		$(TARGET_DIR)/var/lib/proaudio-player-alert/audio-settings.yaml
	$(INSTALL) -D -m 0644 \
		$(@D)/config/wireplumber/51-proaudio-soft-mixer.conf \
		$(TARGET_DIR)/etc/wireplumber/wireplumber.conf.d/51-proaudio-soft-mixer.conf
	$(INSTALL) -D -m 0644 \
		$(@D)/assets/announcements/alarm_start.mp3 \
		$(TARGET_DIR)/usr/share/proaudio-player/announcements/alarm_start.mp3
	$(INSTALL) -D -m 0644 \
		$(@D)/assets/announcements/alarm_end.mp3 \
		$(TARGET_DIR)/usr/share/proaudio-player/announcements/alarm_end.mp3
	$(INSTALL) -D -m 0644 \
		$(@D)/assets/announcements/minute_silence.mp3 \
		$(TARGET_DIR)/usr/share/proaudio-player/announcements/minute_silence.mp3
	$(INSTALL) -D -m 0755 $(@D)/scripts/audio-buses.sh \
		$(TARGET_DIR)/usr/libexec/proaudio-player/audio-buses.sh
	$(INSTALL) -D -m 0755 $(@D)/scripts/proaudio-player-audioctl \
		$(TARGET_DIR)/usr/sbin/proaudio-player-audioctl
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player.tmpfiles.conf \
		$(TARGET_DIR)/usr/lib/tmpfiles.d/proaudio-player.conf
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-mpris.conf \
		$(TARGET_DIR)/usr/share/dbus-1/system.d/proaudio-player-mpris.conf
endef

PROAUDIO_PLAYER_NATIVE_POST_INSTALL_TARGET_HOOKS += PROAUDIO_PLAYER_NATIVE_INSTALL_RUNTIME_LAYOUT

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_AIRPLAY),y)
define PROAUDIO_PLAYER_NATIVE_INSTALL_AIRPLAY_SYSTEMD
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-shairport.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-shairport.service
	ln -sf /usr/lib/systemd/system/proaudio-player-shairport.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-shairport.service
endef
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_DLNA),y)
define PROAUDIO_PLAYER_NATIVE_INSTALL_DLNA_SYSTEMD
	$(INSTALL) -D -m 0755 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/dlna-renderer.sh \
		$(TARGET_DIR)/usr/libexec/proaudio-player/dlna-renderer.sh
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-dlna.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-dlna.service
	ln -sf /usr/lib/systemd/system/proaudio-player-dlna.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-dlna.service
endef
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_SPOTIFY),y)
define PROAUDIO_PLAYER_NATIVE_INSTALL_SPOTIFY_SYSTEMD
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-spotifyd.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-spotifyd.service
	ln -sf /usr/lib/systemd/system/proaudio-player-spotifyd.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-spotifyd.service
endef
endif

define PROAUDIO_PLAYER_NATIVE_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-buses.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-buses.service
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-audio-output.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-audio-output.service
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-audio-output.path \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-audio-output.path
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-mpd.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-mpd.service
	$(INSTALL) -D -m 0644 $(@D)/systemd/proaudio-player-native.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-native.service
	mkdir -p $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants
	# The stock MPD unit would compete with the ProAudio instance for port
	# 6600. A systemd preset keeps the packaged unit disabled while retaining
	# the Buildroot-managed MPD binary and libraries.
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/00-proaudio-player.preset \
		$(TARGET_DIR)/usr/lib/systemd/system-preset/00-proaudio-player.preset
	rm -f $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/mpd.service
	ln -sf /usr/lib/systemd/system/proaudio-player-buses.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-buses.service
	ln -sf /usr/lib/systemd/system/proaudio-player-audio-output.path \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-audio-output.path
	ln -sf /usr/lib/systemd/system/proaudio-player-mpd.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-mpd.service
	ln -sf /usr/lib/systemd/system/proaudio-player-native.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-native.service
	$(PROAUDIO_PLAYER_NATIVE_INSTALL_AIRPLAY_SYSTEMD)
	$(PROAUDIO_PLAYER_NATIVE_INSTALL_DLNA_SYSTEMD)
	$(PROAUDIO_PLAYER_NATIVE_INSTALL_SPOTIFY_SYSTEMD)
endef

$(eval $(cargo-package))
