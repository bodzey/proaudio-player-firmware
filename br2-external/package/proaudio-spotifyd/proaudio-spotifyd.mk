################################################################################
#
# proaudio-spotifyd
#
################################################################################

PROAUDIO_SPOTIFYD_VERSION = 0.4.2
PROAUDIO_SPOTIFYD_SITE = $(call github,Spotifyd,spotifyd,v$(PROAUDIO_SPOTIFYD_VERSION))
PROAUDIO_SPOTIFYD_LICENSE = GPL-3.0-only
PROAUDIO_SPOTIFYD_LICENSE_FILES = LICENSE
PROAUDIO_SPOTIFYD_DEPENDENCIES = host-pkgconf openssl pulseaudio
PROAUDIO_SPOTIFYD_CARGO_BUILD_OPTS = --no-default-features --features pulseaudio_backend
PROAUDIO_SPOTIFYD_CARGO_INSTALL_OPTS = --no-default-features --features pulseaudio_backend

$(eval $(cargo-package))
