################################################################################
#
# proaudio-webui
#
################################################################################

PROAUDIO_WEBUI_VERSION = 0.1.0
PROAUDIO_WEBUI_SITE = $(BR2_EXTERNAL_PROAUDIO_PATH)/../sources/proaudio-player-native/webui
PROAUDIO_WEBUI_SITE_METHOD = local
PROAUDIO_WEBUI_LICENSE = MIT

ifeq ($(BR2_PACKAGE_PROAUDIO_WEBUI),y)
ifeq ($(wildcard $(PROAUDIO_WEBUI_SITE)/index.html),)
$(error BR2_PACKAGE_PROAUDIO_WEBUI=y requires the pinned Web UI submodule; run 'git submodule update --init --recursive')
endif
endif

define PROAUDIO_WEBUI_INSTALL_TARGET_CMDS
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/usr/share/proaudio-player/webui
	cp -a $(@D)/. $(TARGET_DIR)/usr/share/proaudio-player/webui/
endef

$(eval $(generic-package))
