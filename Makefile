# BibleShare — dev workflow
# Requires: full Xcode (not just Command Line Tools), xcodegen.

APP        := BibleShare
SCHEME     := BibleShare
BUNDLE_ID  := com.bibleshare.app
DEVICE     ?= iPhone 16
CONFIG     ?= Debug
BUILD_DIR  := build
DERIVED    := $(BUILD_DIR)/DerivedData

.PHONY: help generate build run boot install launch clean lint

help:
	@echo "Targets:"
	@echo "  make generate  - regenerate BibleShare.xcodeproj from project.yml"
	@echo "  make build     - build the app for the iOS Simulator"
	@echo "  make run       - build, boot simulator, install & launch the app"
	@echo "  make lint      - run SwiftLint (if installed)"
	@echo "  make clean     - remove build artifacts"
	@echo "Vars: DEVICE='iPhone 16' CONFIG=Debug"

generate:
	xcodegen generate

build: generate
	xcodebuild \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination 'platform=iOS Simulator,name=$(DEVICE)' \
		-derivedDataPath $(DERIVED) \
		build

boot:
	@xcrun simctl boot "$(DEVICE)" 2>/dev/null || true
	@open -a Simulator

install: boot
	xcrun simctl install "$(DEVICE)" \
		"$(DERIVED)/Build/Products/$(CONFIG)-iphonesimulator/$(APP).app"

launch:
	xcrun simctl launch "$(DEVICE)" $(BUNDLE_ID)

run: build install launch
	@echo "Launched $(APP) on $(DEVICE)."

lint:
	@command -v swiftlint >/dev/null 2>&1 && swiftlint || echo "swiftlint not installed — skipping"

clean:
	rm -rf $(BUILD_DIR)
	xcodebuild -scheme $(SCHEME) clean 2>/dev/null || true
