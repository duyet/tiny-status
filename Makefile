APP = TinyStatus.app
BIN = TinyStatus.app/Contents/MacOS/TinyStatus
SRC = $(wildcard Sources/TinyStatus/*.swift)
SDK := $(shell xcrun --show-sdk-path)

.PHONY: build app run

app:
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	swiftc -parse-as-library $(SRC) -o $(BIN) \
		-sdk "$(SDK)" -target arm64-apple-macos26 \
		-framework SwiftUI -framework AppKit -framework UserNotifications
	cp Info.plist $(APP)/Contents/Info.plist
	mkdir -p $(APP)/Contents/Resources
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp Resources/GitLab.png $(APP)/Contents/Resources/GitLab.png

build: app

run: app
	open $(APP)
