APP = TinyStatus.app
BIN = TinyStatus.app/Contents/MacOS/TinyStatus
SRC = $(wildcard Sources/TinyStatus/*.swift)
APP_MAIN = Sources/TinyStatus/App.swift
LIB_SRC = $(filter-out $(APP_MAIN),$(SRC))
TEST_BIN = .build/tiny-status-test
SDK := $(shell xcrun --show-sdk-path)
ARCH := $(shell uname -m)
SDKVER := $(firstword $(subst ., ,$(shell xcrun --show-sdk-version 2>/dev/null)))
TARGET ?= $(ARCH)-apple-macos$(or $(SDKVER),26)
MINOS := $(or $(SDKVER),26)
VERSION ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
SIGN_ID ?= -
DIST = dist
DMG = $(DIST)/TinyStatus-v$(VERSION).dmg
ZIP = $(DIST)/TinyStatus-v$(VERSION).zip
FRAMEWORKS = -framework SwiftUI -framework AppKit -framework UserNotifications -framework Network

.PHONY: build app run cli test universal sign dmg zip release

app:
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	swiftc -parse-as-library $(SRC) -o $(BIN) \
		-sdk "$(SDK)" -target "$(TARGET)" \
		-framework SwiftUI -framework AppKit -framework UserNotifications -framework Network
	cp Info.plist $(APP)/Contents/Info.plist
	mkdir -p $(APP)/Contents/Resources
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp Resources/GitLab.png $(APP)/Contents/Resources/GitLab.png

build: app

run: app
	open $(APP)

cli: app
	@chmod +x scripts/tiny-status
	@echo "CLI: $(CURDIR)/scripts/tiny-status  or  $(CURDIR)/$(BIN)"
	@echo "Link: ln -sf $(CURDIR)/scripts/tiny-status ~/.local/bin/tiny-status"

test:
	mkdir -p .build
	swiftc -parse-as-library $(LIB_SRC) Tests/Run.swift -o $(TEST_BIN) \
		-sdk "$(SDK)" -target "$(TARGET)" \
		-framework SwiftUI -framework AppKit -framework UserNotifications -framework Network
	$(TEST_BIN)

# Release: universal binary (arm64 + x86_64), signed, packed as DMG + zip.
universal: app
	mkdir -p .build
	for a in arm64 x86_64; do \
		swiftc -O -parse-as-library $(SRC) -o .build/TinyStatus-$$a \
			-sdk "$(SDK)" -target "$$a-apple-macos$(MINOS)" $(FRAMEWORKS) || exit 1; \
	done
	lipo -create .build/TinyStatus-arm64 .build/TinyStatus-x86_64 -output $(BIN)

# SIGN_ID=- is ad-hoc. Set a "Developer ID Application: ..." identity for distribution.
sign:
	codesign --force --deep --options runtime $(if $(filter -,$(SIGN_ID)),--timestamp=none,--timestamp) --sign "$(SIGN_ID)" $(APP)
	codesign --verify --strict $(APP)

dmg: universal sign
	rm -rf $(DIST)/dmg && mkdir -p $(DIST)/dmg
	cp -R $(APP) $(DIST)/dmg/
	ln -s /Applications $(DIST)/dmg/Applications
	rm -f $(DMG)
	hdiutil create -volname "TinyStatus" -srcfolder $(DIST)/dmg -fs HFS+ -format UDZO -ov $(DMG)
	rm -rf $(DIST)/dmg

zip: universal sign
	mkdir -p $(DIST)
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)

release: dmg zip
	cd $(DIST) && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt && cat SHA256SUMS.txt
