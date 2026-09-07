################################################################################
#
# proaudio-spotifyd
#
################################################################################

PROAUDIO_SPOTIFYD_VERSION = 0.4.2
PROAUDIO_SPOTIFYD_SOURCE = spotifyd-$(PROAUDIO_SPOTIFYD_VERSION).crate
PROAUDIO_SPOTIFYD_SITE = https://static.crates.io/crates/spotifyd
PROAUDIO_SPOTIFYD_LICENSE = GPL-3.0-only
PROAUDIO_SPOTIFYD_LICENSE_FILES = LICENSE
PROAUDIO_SPOTIFYD_DEPENDENCIES = host-pkgconf openssl pulseaudio
PROAUDIO_SPOTIFYD_CARGO_BUILD_OPTS = --no-default-features --features pulseaudio_backend
PROAUDIO_SPOTIFYD_CARGO_INSTALL_OPTS = --no-default-features --features pulseaudio_backend

define PROAUDIO_SPOTIFYD_EXTRACT_CMDS
	$(TAR) -C $(@D) --strip-components=1 -xf \
		$(PROAUDIO_SPOTIFYD_DL_DIR)/$(PROAUDIO_SPOTIFYD_SOURCE)
endef

$(eval $(cargo-package))
