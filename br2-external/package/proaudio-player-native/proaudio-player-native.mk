################################################################################
#
# proaudio-player-native
#
################################################################################

PROAUDIO_PLAYER_NATIVE_VERSION = 0.1.0
PROAUDIO_PLAYER_NATIVE_SITE = $(BR2_EXTERNAL_PROAUDIO_PATH)/../sources/proaudio-player-native
PROAUDIO_PLAYER_NATIVE_SITE_METHOD = local
PROAUDIO_PLAYER_NATIVE_LICENSE = MIT
PROAUDIO_PLAYER_NATIVE_CARGO_ENV = \
	PKG_CONFIG_ALLOW_CROSS=1
PROAUDIO_PLAYER_NATIVE_DEPENDENCIES = \
	mpd \
	pipewire \
	pulseaudio \
	host-pkgconf

define PROAUDIO_PLAYER_NATIVE_USERS
	proaudio-player -1 proaudio-player -1 * /var/lib/proaudio-player /bin/false audio,dialout,pipewire ProAudio Player
endef

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_AIRPLAY),y)
PROAUDIO_PLAYER_NATIVE_DEPENDENCIES += proaudio-shairport-sync
endif
ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_DLNA),y)
PROAUDIO_PLAYER_NATIVE_DEPENDENCIES += gupnp-av gupnp-dlna
endif
ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_SPOTIFY),y)
PROAUDIO_PLAYER_NATIVE_DEPENDENCIES += proaudio-spotifyd
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_AIRPLAY),y)
define PROAUDIO_PLAYER_NATIVE_INSTALL_AIRPLAY_SYSTEMD
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-shairport.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-shairport.service
	ln -sf /usr/lib/systemd/system/proaudio-player-shairport.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-shairport.service
endef
else
define PROAUDIO_PLAYER_NATIVE_INSTALL_AIRPLAY_SYSTEMD
	rm -f $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-shairport.service
	rm -f $(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-shairport.service
endef
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_DLNA),y)
define PROAUDIO_PLAYER_NATIVE_INSTALL_DLNA_SYSTEMD
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-dlna.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-dlna.service
	ln -sf /usr/lib/systemd/system/proaudio-player-dlna.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-dlna.service
endef
else
define PROAUDIO_PLAYER_NATIVE_INSTALL_DLNA_SYSTEMD
	rm -f $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-dlna.service
	rm -f $(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-dlna.service
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
else
define PROAUDIO_PLAYER_NATIVE_INSTALL_SPOTIFY_SYSTEMD
	rm -f $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-spotifyd.service
	rm -f $(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-spotifyd.service
endef
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_ALERTS),y)
PROAUDIO_PLAYER_NATIVE_FEATURES += alerts
endif
ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_AIRPLAY),y)
PROAUDIO_PLAYER_NATIVE_FEATURES += airplay
endif
ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_DLNA),y)
PROAUDIO_PLAYER_NATIVE_FEATURES += dlna
endif
ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_SPOTIFY),y)
PROAUDIO_PLAYER_NATIVE_FEATURES += spotify
endif

ifneq ($(strip $(PROAUDIO_PLAYER_NATIVE_FEATURES)),)
PROAUDIO_PLAYER_NATIVE_CARGO_BUILD_OPTS += \
	--no-default-features \
	--features $(subst $(space),$(comma),$(strip $(PROAUDIO_PLAYER_NATIVE_FEATURES)))
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_AIRPLAY),y)
define PROAUDIO_PLAYER_NATIVE_INSTALL_AIRPLAY_CONFIG
	$(INSTALL) -D -m 0644 $(@D)/config/shairport-sync.conf \
		$(TARGET_DIR)/etc/proaudio-player-alert/shairport-sync.conf
endef
else
define PROAUDIO_PLAYER_NATIVE_INSTALL_AIRPLAY_CONFIG
	rm -f $(TARGET_DIR)/etc/proaudio-player-alert/shairport-sync.conf
endef
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_DLNA),y)
define PROAUDIO_PLAYER_NATIVE_INSTALL_DLNA_CONFIG
	$(INSTALL) -D -m 0755 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/dlna-renderer.sh \
		$(TARGET_DIR)/usr/libexec/proaudio-player/dlna-renderer.sh
endef
else
define PROAUDIO_PLAYER_NATIVE_INSTALL_DLNA_CONFIG
	rm -f $(TARGET_DIR)/usr/libexec/proaudio-player/dlna-renderer.sh
endef
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE_SPOTIFY),y)
define PROAUDIO_PLAYER_NATIVE_INSTALL_SPOTIFY_CONFIG
	$(INSTALL) -D -m 0644 $(@D)/config/spotifyd.conf \
		$(TARGET_DIR)/etc/proaudio-player-alert/spotifyd.conf
endef
else
define PROAUDIO_PLAYER_NATIVE_INSTALL_SPOTIFY_CONFIG
	rm -f $(TARGET_DIR)/etc/proaudio-player-alert/spotifyd.conf
endef
endif

define PROAUDIO_PLAYER_NATIVE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/target/$(RUSTC_TARGET_NAME)/release/proaudio-player-native \
		$(TARGET_DIR)/usr/bin/proaudio-player-native
	$(INSTALL) -D -m 0755 $(@D)/target/$(RUSTC_TARGET_NAME)/release/proaudio-player-limiter \
		$(TARGET_DIR)/usr/bin/proaudio-player-limiter
	$(INSTALL) -D -m 0644 $(@D)/config/config.yaml.example \
		$(TARGET_DIR)/etc/proaudio-player-alert/config.yaml
	$(INSTALL) -D -m 0644 $(@D)/config/audio.env.example \
		$(TARGET_DIR)/etc/proaudio-player-alert/audio.env
	$(INSTALL) -D -m 0644 $(@D)/config/mpd.conf \
		$(TARGET_DIR)/etc/proaudio-player-alert/mpd.conf
	$(INSTALL) -D -m 0644 $(@D)/config/wireplumber/51-proaudio-soft-mixer.conf \
		$(TARGET_DIR)/etc/wireplumber/wireplumber.conf.d/51-proaudio-soft-mixer.conf
	$(INSTALL) -D -m 0755 $(@D)/scripts/audio-buses.sh \
		$(TARGET_DIR)/usr/libexec/proaudio-player/audio-buses.sh
	$(INSTALL) -D -m 0755 $(@D)/scripts/proaudio-player-limiter-start \
		$(TARGET_DIR)/usr/libexec/proaudio-player/proaudio-player-limiter-start
	$(INSTALL) -D -m 0755 $(@D)/scripts/proaudio-player-output-watch \
		$(TARGET_DIR)/usr/libexec/proaudio-player/proaudio-player-output-watch
	$(INSTALL) -D -m 0755 $(@D)/scripts/proaudio-player-audioctl \
		$(TARGET_DIR)/usr/sbin/proaudio-player-audioctl
	$(INSTALL) -D -m 0644 $(@D)/assets/announcements/alarm_start.mp3 \
		$(TARGET_DIR)/usr/share/proaudio-player/announcements/alarm_start.mp3
	$(INSTALL) -D -m 0644 $(@D)/assets/announcements/alarm_end.mp3 \
		$(TARGET_DIR)/usr/share/proaudio-player/announcements/alarm_end.mp3
	$(INSTALL) -D -m 0644 $(@D)/assets/announcements/minute_silence.mp3 \
		$(TARGET_DIR)/usr/share/proaudio-player/announcements/minute_silence.mp3
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player.tmpfiles.conf \
		$(TARGET_DIR)/usr/lib/tmpfiles.d/proaudio-player.conf
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-mpris.conf \
		$(TARGET_DIR)/usr/share/dbus-1/system.d/proaudio-player-mpris.conf
	$(PROAUDIO_PLAYER_NATIVE_INSTALL_AIRPLAY_CONFIG)
	$(PROAUDIO_PLAYER_NATIVE_INSTALL_DLNA_CONFIG)
	$(PROAUDIO_PLAYER_NATIVE_INSTALL_SPOTIFY_CONFIG)
endef

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
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-output-watch.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-output-watch.service
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-limiter.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-limiter.service
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-limiter-restart.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-limiter-restart.service
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-limiter.path \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-limiter.path
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-mpd.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-mpd.service
	$(INSTALL) -D -m 0644 $(@D)/systemd/proaudio-player-native.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-native.service
	mkdir -p $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants
	# The stock MPD service and socket would compete with the ProAudio instance
	# for port 6600. Keep the packaged units disabled while retaining the
	# Buildroot-managed MPD binary and libraries.
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/00-proaudio-player.preset \
		$(TARGET_DIR)/usr/lib/systemd/system-preset/00-proaudio-player.preset
	rm -f $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/mpd.service
	rm -f $(TARGET_DIR)/etc/systemd/system/sockets.target.wants/mpd.socket
	ln -sf /usr/lib/systemd/system/proaudio-player-buses.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-buses.service
	ln -sf /usr/lib/systemd/system/proaudio-player-audio-output.path \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-audio-output.path
	ln -sf /usr/lib/systemd/system/proaudio-player-output-watch.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-output-watch.service
	ln -sf /usr/lib/systemd/system/proaudio-player-limiter.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-limiter.service
	ln -sf /usr/lib/systemd/system/proaudio-player-limiter.path \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-limiter.path
	ln -sf /usr/lib/systemd/system/proaudio-player-mpd.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-mpd.service
	ln -sf /usr/lib/systemd/system/proaudio-player-native.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-native.service
	$(PROAUDIO_PLAYER_NATIVE_INSTALL_AIRPLAY_SYSTEMD)
	$(PROAUDIO_PLAYER_NATIVE_INSTALL_DLNA_SYSTEMD)
	$(PROAUDIO_PLAYER_NATIVE_INSTALL_SPOTIFY_SYSTEMD)
endef

$(eval $(cargo-package))
