################################################################################
#
# proaudio-shairport-sync
#
################################################################################

PROAUDIO_SHAIRPORT_SYNC_VERSION = 4.3.7
PROAUDIO_SHAIRPORT_SYNC_SOURCE = shairport-sync-$(PROAUDIO_SHAIRPORT_SYNC_VERSION).tar.gz
PROAUDIO_SHAIRPORT_SYNC_SITE = $(call github,mikebrady,shairport-sync,$(PROAUDIO_SHAIRPORT_SYNC_VERSION))
PROAUDIO_SHAIRPORT_SYNC_LICENSE = MIT, BSD-3-Clause
PROAUDIO_SHAIRPORT_SYNC_LICENSE_FILES = LICENSES
PROAUDIO_SHAIRPORT_SYNC_DEPENDENCIES = \
	avahi \
	dbus \
	host-pkgconf \
	libconfig \
	libglib2 \
	openssl \
	popt \
	pulseaudio
PROAUDIO_SHAIRPORT_SYNC_AUTORECONF = YES

PROAUDIO_SHAIRPORT_SYNC_CONF_OPTS = \
	--without-alsa \
	--with-pa \
	--with-avahi \
	--without-tinysvcmdns \
	--with-ssl=openssl \
	--with-metadata \
	--with-pipe \
	--with-stdout \
	--without-airplay-2 \
	--without-convolution \
	--with-dbus-interface \
	--with-mpris-interface \
	--without-libdaemon \
	--without-soxr \
	--without-mqtt-client

define PROAUDIO_SHAIRPORT_SYNC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/shairport-sync \
		$(TARGET_DIR)/usr/bin/shairport-sync
endef

$(eval $(autotools-package))
