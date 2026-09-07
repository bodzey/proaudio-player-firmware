################################################################################
#
# proaudio-player
#
################################################################################

PROAUDIO_PLAYER_VERSION = 0.3.1
PROAUDIO_PLAYER_SITE = $(BR2_EXTERNAL_PROAUDIO_PATH)/../sources/proaudio-player
PROAUDIO_PLAYER_SITE_METHOD = local
PROAUDIO_PLAYER_SETUP_TYPE = setuptools

$(eval $(python-package))
