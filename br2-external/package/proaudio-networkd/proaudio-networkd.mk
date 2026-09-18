################################################################################
#
# proaudio-networkd
#
################################################################################

PROAUDIO_NETWORKD_VERSION = 1.0
PROAUDIO_NETWORKD_SITE = $(BR2_EXTERNAL_PROAUDIO_PATH)/package/proaudio-networkd
PROAUDIO_NETWORKD_SITE_METHOD = local
PROAUDIO_NETWORKD_DEPENDENCIES = \
	brcmfmac_sdio-firmware-rpi \
	dnsmasq \
	iw \
	network-manager \
	python-gpiod \
	python3 \
	wireless-regdb \
	wpa_supplicant

# Local-site packages are rsynced directly and do not run Buildroot's normal
# package-directory patch phase. Apply our runtime fixes explicitly before
# configure so the daemon installed into the image is the patched copy.
define PROAUDIO_NETWORKD_APPLY_LOCAL_PATCHES
	$(APPLY_PATCHES) $(@D) $(PROAUDIO_NETWORKD_PKGDIR) \
		0001-stabilize-ap-to-station-provisioning.patch
	$(APPLY_PATCHES) $(@D) $(PROAUDIO_NETWORKD_PKGDIR) \
		0002-set-unique-runtime-hostname.patch
endef
PROAUDIO_NETWORKD_PRE_CONFIGURE_HOOKS += PROAUDIO_NETWORKD_APPLY_LOCAL_PATCHES

define PROAUDIO_NETWORKD_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/proaudio-networkd \
		$(TARGET_DIR)/usr/sbin/proaudio-networkd
	$(INSTALL) -D -m 0755 $(@D)/proaudio-networkctl \
		$(TARGET_DIR)/usr/sbin/proaudio-networkctl
	$(INSTALL) -D -m 0600 $(@D)/proaudio-networkd.conf \
		$(TARGET_DIR)/etc/proaudio-networkd.conf
	$(INSTALL) -D -m 0644 $(@D)/10-proaudio-networkmanager.conf \
		$(TARGET_DIR)/etc/NetworkManager/conf.d/10-proaudio.conf
	$(INSTALL) -D -m 0644 $(@D)/10-proaudio-ethernet.network \
		$(TARGET_DIR)/etc/systemd/network/10-proaudio-ethernet.network
endef

define PROAUDIO_NETWORKD_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(@D)/proaudio-networkd.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-networkd.service
	mkdir -p $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants
	ln -sf /usr/lib/systemd/system/NetworkManager.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/NetworkManager.service
	ln -sf /usr/lib/systemd/system/proaudio-networkd.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-networkd.service
endef

$(eval $(generic-package))
