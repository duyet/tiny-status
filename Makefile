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

.PHONY: build app run cli test

app:
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	swiftc -parse-as-library $(SRC) -o $(BIN) \
		-sdk "$(SDK)" -target "$(TARGET)" \
		-framework SwiftUI -framework AppKit -framework UserNotifications
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
		-framework SwiftUI -framework AppKit -framework UserNotifications
	$(TEST_BIN)
