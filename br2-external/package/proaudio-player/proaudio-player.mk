################################################################################
#
# proaudio-player
#
################################################################################

PROAUDIO_PLAYER_VERSION = 0.3.1
PROAUDIO_PLAYER_SITE = $(BR2_EXTERNAL_PROAUDIO_PATH)/../sources/proaudio-player
PROAUDIO_PLAYER_SITE_METHOD = local
PROAUDIO_PLAYER_SETUP_TYPE = setuptools

PROAUDIO_PLAYER_DEPENDENCIES = \
	alsa-lib \
	alsa-utils \
	bash \
	ca-certificates \
	mpd \
	mpd-mpc \
	mpv \
	pipewire \
	pulseaudio \
	python-aiohttp \
	python-pyyaml \
	python-serial \
	python3 \
	systemd \
	wireplumber

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_AIRPLAY),y)
PROAUDIO_PLAYER_DEPENDENCIES += avahi proaudio-shairport-sync
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_DLNA),y)
PROAUDIO_PLAYER_DEPENDENCIES += \
	gmrender-resurrect \
	gst1-libav \
	gst1-plugins-good
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_SPOTIFY),y)
PROAUDIO_PLAYER_DEPENDENCIES += proaudio-spotifyd
endif

define PROAUDIO_PLAYER_USERS
	proaudio-player -1 proaudio-player -1 * /var/lib/proaudio-player /bin/false audio,dialout,pipewire ProAudio Player
endef

define PROAUDIO_PLAYER_PERMISSIONS
	/etc/proaudio-player-alert/config.yaml f 640 root proaudio-player - - - - -
	/etc/proaudio-player-alert/alerts-token f 600 proaudio-player proaudio-player - - - - -
	/var/lib/proaudio-player-alert/media/alarm_start.mp3 f 644 proaudio-player proaudio-player - - - - -
	/var/lib/proaudio-player-alert/media/alarm_end.mp3 f 644 proaudio-player proaudio-player - - - - -
	/var/lib/proaudio-player-alert/media/minute_silence.mp3 f 644 proaudio-player proaudio-player - - - - -
	/var/lib/proaudio-player-alert/provider-settings.yaml f 600 proaudio-player proaudio-player - - - - -
	/var/lib/proaudio-player-alert/audio-settings.yaml f 600 proaudio-player proaudio-player - - - - -
endef

define PROAUDIO_PLAYER_INSTALL_RUNTIME_LAYOUT
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/etc/proaudio-player-alert
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
		$(@D)/src/proaudio_player_alert/default_media/alarm_start.mp3 \
		$(TARGET_DIR)/var/lib/proaudio-player-alert/media/alarm_start.mp3
	$(INSTALL) -D -m 0644 \
		$(@D)/src/proaudio_player_alert/default_media/alarm_end.mp3 \
		$(TARGET_DIR)/var/lib/proaudio-player-alert/media/alarm_end.mp3
	$(INSTALL) -D -m 0644 \
		$(@D)/src/proaudio_player_alert/default_media/minute_silence.mp3 \
		$(TARGET_DIR)/var/lib/proaudio-player-alert/media/minute_silence.mp3
	$(INSTALL) -D -m 0755 $(@D)/scripts/audio-buses.sh \
		$(TARGET_DIR)/usr/libexec/proaudio-player/audio-buses.sh
	$(INSTALL) -D -m 0755 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-audioctl \
		$(TARGET_DIR)/usr/sbin/proaudio-player-audioctl
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player.tmpfiles.conf \
		$(TARGET_DIR)/usr/lib/tmpfiles.d/proaudio-player.conf
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-mpris.conf \
		$(TARGET_DIR)/usr/share/dbus-1/system.d/proaudio-player-mpris.conf
endef

PROAUDIO_PLAYER_POST_INSTALL_TARGET_HOOKS += PROAUDIO_PLAYER_INSTALL_RUNTIME_LAYOUT

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_AIRPLAY),y)
define PROAUDIO_PLAYER_INSTALL_AIRPLAY_SYSTEMD
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-shairport.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-shairport.service
	ln -sf /usr/lib/systemd/system/proaudio-player-shairport.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-shairport.service
endef
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_DLNA),y)
define PROAUDIO_PLAYER_INSTALL_DLNA_SYSTEMD
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-dlna.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-dlna.service
	ln -sf /usr/lib/systemd/system/proaudio-player-dlna.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-dlna.service
endef
endif

ifeq ($(BR2_PACKAGE_PROAUDIO_PLAYER_SPOTIFY),y)
define PROAUDIO_PLAYER_INSTALL_SPOTIFY_SYSTEMD
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-spotifyd.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-spotifyd.service
	ln -sf /usr/lib/systemd/system/proaudio-player-spotifyd.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-spotifyd.service
endef
endif

define PROAUDIO_PLAYER_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-buses.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-buses.service
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-alert.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-alert.service
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-webui.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-webui.service
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-player/proaudio-player-mpd.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-mpd.service
	mkdir -p $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants
	ln -sf /usr/lib/systemd/system/proaudio-player-buses.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-buses.service
	ln -sf /usr/lib/systemd/system/proaudio-player-alert.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-alert.service
	ln -sf /usr/lib/systemd/system/proaudio-player-webui.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-webui.service
	ln -sf /usr/lib/systemd/system/proaudio-player-mpd.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-player-mpd.service
	$(PROAUDIO_PLAYER_INSTALL_AIRPLAY_SYSTEMD)
	$(PROAUDIO_PLAYER_INSTALL_DLNA_SYSTEMD)
	$(PROAUDIO_PLAYER_INSTALL_SPOTIFY_SYSTEMD)
endef

$(eval $(python-package))
