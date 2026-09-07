################################################################################
#
# proaudio-player
#
################################################################################

PROAUDIO_PLAYER_VERSION = 0.3.1
PROAUDIO_PLAYER_SITE = $(BR2_EXTERNAL_PROAUDIO_PATH)/../sources/proaudio-player
PROAUDIO_PLAYER_SITE_METHOD = local
PROAUDIO_PLAYER_SETUP_TYPE = setuptools

define PROAUDIO_PLAYER_INSTALL_RUNTIME_LAYOUT
	$(INSTALL) -D -m 0644 \
		$(@D)/config/config.yaml.example \
		$(TARGET_DIR)/etc/proaudio-player-alert/config.yaml
	$(INSTALL) -d -m 0755 \
		$(TARGET_DIR)/var/lib/proaudio-player-alert
	$(INSTALL) -d -m 0755 \
		$(TARGET_DIR)/var/lib/proaudio-player-alert/media
endef

PROAUDIO_PLAYER_POST_INSTALL_TARGET_HOOKS += PROAUDIO_PLAYER_INSTALL_RUNTIME_LAYOUT

$(eval $(python-package))
