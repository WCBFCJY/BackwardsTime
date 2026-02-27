TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BackwardsTime

BackwardsTime_FILES = Tweak.x
BackwardsTime_CFLAGS = -fobjc-arc
BackwardsTime_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
