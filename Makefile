# Hermes Desktop — Build & Run
# 
# Prerequisites: Xcode 26.6+ with xcode-select set correctly

.PHONY: build run clean app test

SCHEME = HermesDesktop
CONFIG = Debug
DEST = platform=macOS
DERIVED = .build
BINARY = $(DERIVED)/Build/Products/$(CONFIG)/HermesDesktop
APP = build/HermesDesktop.app

build:
	xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(DEST)' -derivedDataPath $(DERIVED) build

test:
	xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(DEST)' -derivedDataPath $(DERIVED) test

app: build
	@echo "📦 Creating app bundle..."
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@cp $(BINARY) "$(APP)/Contents/MacOS/HermesDesktop"
	@cp App/Info.plist "$(APP)/Contents/Info.plist" 2>/dev/null || \
		plutil -create xml1 "$(APP)/Contents/Info.plist" && \
		plutil -replace CFBundleExecutable -string HermesDesktop "$(APP)/Contents/Info.plist" && \
		plutil -replace CFBundleIdentifier -string com.hermes-desktop.app "$(APP)/Contents/Info.plist" && \
		plutil -replace CFBundleName -string "Hermes Desktop" "$(APP)/Contents/Info.plist" && \
		plutil -replace CFBundleVersion -string 1 "$(APP)/Contents/Info.plist" && \
		plutil -replace CFBundleShortVersionString -string 1.0 "$(APP)/Contents/Info.plist" && \
		plutil -replace CFBundlePackageType -string APPL "$(APP)/Contents/Info.plist" && \
		plutil -replace LSMinimumSystemVersion -string 14.0 "$(APP)/Contents/Info.plist" && \
		plutil -replace NSHighResolutionCapable -bool YES "$(APP)/Contents/Info.plist"
	@echo "✅ App ready: $(APP)"

run: app
	@echo "🚀 Launching..."
	open $(APP)

clean:
	rm -rf $(DERIVED) build
