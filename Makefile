.PHONY: build run clean app icon test test-integration test-all

SCHEME = HermesDesktop
CONFIG = Debug
DEST = platform=macOS
DERIVED = .build
BINARY = $(DERIVED)/Build/Products/$(CONFIG)/HermesDesktop
APP = build/HermesDesktop.app
ICON_SRC = Resources/AppIcon.png
ICONSET = build/AppIcon.iconset
ICNS = build/AppIcon.icns

build:
	xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(DEST)' -derivedDataPath $(DERIVED) build

test:
	xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(DEST)' -derivedDataPath $(DERIVED) test 2>&1 | grep -E 'Test Suite|Executed|TEST'

icon:
	@rm -rf $(ICONSET)
	@mkdir -p $(ICONSET)
	@sips -z 16 16   $(ICON_SRC) --out $(ICONSET)/icon_16x16.png > /dev/null
	@sips -z 32 32   $(ICON_SRC) --out $(ICONSET)/icon_16x16@2x.png > /dev/null
	@sips -z 32 32   $(ICON_SRC) --out $(ICONSET)/icon_32x32.png > /dev/null
	@sips -z 64 64   $(ICON_SRC) --out $(ICONSET)/icon_32x32@2x.png > /dev/null
	@sips -z 128 128 $(ICON_SRC) --out $(ICONSET)/icon_128x128.png > /dev/null
	@sips -z 256 256 $(ICON_SRC) --out $(ICONSET)/icon_128x128@2x.png > /dev/null
	@sips -z 256 256 $(ICON_SRC) --out $(ICONSET)/icon_256x256.png > /dev/null
	@sips -z 512 512 $(ICON_SRC) --out $(ICONSET)/icon_256x256@2x.png > /dev/null
	@sips -z 512 512 $(ICON_SRC) --out $(ICONSET)/icon_512x512.png > /dev/null
	@cp $(ICON_SRC) $(ICONSET)/icon_512x512@2x.png
	@iconutil -c icns $(ICONSET) -o $(ICNS)

app: build icon
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@cp $(BINARY) "$(APP)/Contents/MacOS/HermesDesktop"
	@cp $(ICNS) "$(APP)/Contents/Resources/AppIcon.icns"
	@plutil -create xml1 "$(APP)/Contents/Info.plist"
	@plutil -replace CFBundleExecutable -string HermesDesktop "$(APP)/Contents/Info.plist"
	@plutil -replace CFBundleIdentifier -string com.hermes-desktop.app "$(APP)/Contents/Info.plist"
	@plutil -replace CFBundleName -string "Hermes Desktop" "$(APP)/Contents/Info.plist"
	@plutil -replace CFBundleIconFile -string AppIcon "$(APP)/Contents/Info.plist"
	@plutil -replace CFBundleVersion -string 1 "$(APP)/Contents/Info.plist"
	@plutil -replace CFBundleShortVersionString -string 1.0 "$(APP)/Contents/Info.plist"
	@plutil -replace CFBundlePackageType -string APPL "$(APP)/Contents/Info.plist"
	@plutil -replace LSMinimumSystemVersion -string 14.0 "$(APP)/Contents/Info.plist"
	@plutil -replace NSHighResolutionCapable -bool YES "$(APP)/Contents/Info.plist"
	@echo "✅ App ready: $(APP)"

run: app
	@open $(APP)

clean:
	rm -rf $(DERIVED) build

test-integration:
	@./scripts/test-integration.sh

test-all: test test-integration
	@echo "✅ All tests complete"
