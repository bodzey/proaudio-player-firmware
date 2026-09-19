################################################################################
#
# proaudio-networkd
#
################################################################################

PROAUDIO_NETWORKD_VERSION = 2.0.0
PROAUDIO_NETWORKD_SITE = $(PROAUDIO_NETWORKD_PKGDIR)/rust
PROAUDIO_NETWORKD_SITE_METHOD = local
PROAUDIO_NETWORKD_DEPENDENCIES = \
	brcmfmac_sdio-firmware-rpi \
	dnsmasq \
	iw \
	libgpiod2 \
	network-manager \
	wireless-regdb \
	wpa_supplicant

define PROAUDIO_NETWORKD_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 \
		$(@D)/target/$(RUSTC_TARGET_NAME)/release/proaudio-networkd \
		$(TARGET_DIR)/usr/sbin/proaudio-networkd
	$(INSTALL) -D -m 0755 $(PROAUDIO_NETWORKD_PKGDIR)/proaudio-networkctl \
		$(TARGET_DIR)/usr/sbin/proaudio-networkctl
	$(INSTALL) -D -m 0600 $(PROAUDIO_NETWORKD_PKGDIR)/proaudio-networkd.conf \
		$(TARGET_DIR)/etc/proaudio-networkd.conf
	$(INSTALL) -D -m 0644 $(PROAUDIO_NETWORKD_PKGDIR)/10-proaudio-networkmanager.conf \
		$(TARGET_DIR)/etc/NetworkManager/conf.d/10-proaudio.conf
	$(INSTALL) -D -m 0644 $(PROAUDIO_NETWORKD_PKGDIR)/10-proaudio-ethernet.network \
		$(TARGET_DIR)/etc/systemd/network/10-proaudio-ethernet.network
endef

define PROAUDIO_NETWORKD_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(PROAUDIO_NETWORKD_PKGDIR)/proaudio-networkd.service \
		$(TARGET_DIR)/usr/lib/systemd/system/proaudio-networkd.service
	mkdir -p $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants
	ln -sf /usr/lib/systemd/system/NetworkManager.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/NetworkManager.service
	ln -sf /usr/lib/systemd/system/proaudio-networkd.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/proaudio-networkd.service
endef

$(eval $(cargo-package))
