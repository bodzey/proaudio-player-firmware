################################################################################
#
# proaudio-webui
#
################################################################################

PROAUDIO_WEBUI_VERSION = 0.1.0
PROAUDIO_WEBUI_SITE = $(BR2_EXTERNAL_PROAUDIO_PATH)/../sources/proaudio-player-webui
PROAUDIO_WEBUI_SITE_METHOD = local
PROAUDIO_WEBUI_LICENSE = MIT
PROAUDIO_WEBUI_DEPENDENCIES = host-nodejs

ifeq ($(BR2_PACKAGE_PROAUDIO_WEBUI),y)
ifeq ($(wildcard $(PROAUDIO_WEBUI_SITE)/package.json),)
$(error BR2_PACKAGE_PROAUDIO_WEBUI=y requires the pinned Web UI submodule; run 'git submodule update --init --recursive')
endif
ifeq ($(wildcard $(PROAUDIO_WEBUI_SITE)/package-lock.json),)
$(error BR2_PACKAGE_PROAUDIO_WEBUI=y requires package-lock.json for reproducible npm ci builds)
endif
endif

define PROAUDIO_WEBUI_BUILD_CMDS
	cd $(@D) && \
		PATH="$(HOST_DIR)/bin:$$PATH" \
		npm_config_cache="$(DL_DIR)/br-npm-cache" \
		npm_config_audit=false \
		npm_config_fund=false \
		npm_config_update_notifier=false \
		$(HOST_DIR)/bin/npm ci --include=dev
	cd $(@D) && \
		PATH="$(HOST_DIR)/bin:$$PATH" \
		$(HOST_DIR)/bin/npm run build
endef

define PROAUDIO_WEBUI_INSTALL_TARGET_CMDS
	test -f $(@D)/dist/index.html
	rm -rf $(TARGET_DIR)/usr/share/proaudio-player/webui
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/usr/share/proaudio-player/webui
	cp -a $(@D)/dist/. $(TARGET_DIR)/usr/share/proaudio-player/webui/
endef

$(eval $(generic-package))
