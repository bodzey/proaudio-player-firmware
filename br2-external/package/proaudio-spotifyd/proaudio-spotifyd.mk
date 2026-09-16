################################################################################
#
# proaudio-spotifyd
#
################################################################################

PROAUDIO_SPOTIFYD_VERSION = 0.4.2
PROAUDIO_SPOTIFYD_SOURCE = spotifyd-$(PROAUDIO_SPOTIFYD_VERSION).crate
PROAUDIO_SPOTIFYD_SITE = https://static.crates.io/crates/spotifyd
# Keep Buildroot's Cargo post-processing base name identical to the
# previously verified spotifyd-0.4.2 vendored archive.
PROAUDIO_SPOTIFYD_DL_SUBDIR = spotifyd
PROAUDIO_SPOTIFYD_LICENSE = GPL-3.0-only
PROAUDIO_SPOTIFYD_LICENSE_FILES = LICENSE
PROAUDIO_SPOTIFYD_DEPENDENCIES = alsa-lib dbus host-pkgconf openssl
PROAUDIO_SPOTIFYD_CARGO_BUILD_OPTS = --no-default-features --features alsa_backend,dbus_mpris
PROAUDIO_SPOTIFYD_CARGO_INSTALL_OPTS = --no-default-features --features alsa_backend,dbus_mpris

define PROAUDIO_SPOTIFYD_EXTRACT_CMDS
	$(TAR) -C $(@D) --strip-components=1 -xf \
		$(PROAUDIO_SPOTIFYD_DL_DIR)/$(PROAUDIO_SPOTIFYD_SOURCE)
endef

# Buildroot's cargo download post-processing vendors librespot and records
# per-file hashes in .cargo-checksum.json. Our source patch intentionally
# changes librespot-discovery/src/server.rs, so update the pinned vendor hash
# after patching. Keep the expected pre-patch hash explicit so an upstream
# archive/layout change fails loudly instead of silently rewriting metadata.
define PROAUDIO_SPOTIFYD_FIX_LIBRESPOT_VENDOR_CHECKSUM
	grep -q '80e0f51c9c9d5dc86e0e67fa2478ddeb1e184529458655e538c70c5dec8ecccd' \
		$(@D)/VENDOR/librespot-discovery/.cargo-checksum.json
	$(SED) 's/80e0f51c9c9d5dc86e0e67fa2478ddeb1e184529458655e538c70c5dec8ecccd/e951845986dc9fce04f0e2f0e73c2bc54e74a7cb8614976e46c4b49d6779b5c0/' \
		$(@D)/VENDOR/librespot-discovery/.cargo-checksum.json
endef
PROAUDIO_SPOTIFYD_POST_PATCH_HOOKS += PROAUDIO_SPOTIFYD_FIX_LIBRESPOT_VENDOR_CHECKSUM

$(eval $(cargo-package))
