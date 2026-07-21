APP            := QuipExporter
BUILD_BUNDLE   := build/$(APP).app
INSTALL_BUNDLE := /Applications/$(APP).app
CONTENTS       := $(BUILD_BUNDLE)/Contents
CACHE_DIR      := $(HOME)/Library/Application Support/$(APP)/BlobCache

define assemble
	rm -rf $(BUILD_BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp .build/$(1)/$(APP) $(CONTENTS)/MacOS/$(APP)
	cp Info.plist $(CONTENTS)/
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(CONTENTS)/Resources/; fi
	codesign --force --deep --sign - $(BUILD_BUNDLE)
endef

.PHONY: help build dev publish install uninstall open close reinstall-open clean reinstall icon test-note test-markdown-import

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

build: ## Build the debug app bundle
	swift build --disable-sandbox
	$(call assemble,debug)

dev: ## Kill, rebuild, and relaunch the debug app
	-killall $(APP) 2>/dev/null; sleep 0.5
	$(MAKE) build
	/usr/bin/open $(BUILD_BUNDLE)

publish: ## Build the release app bundle
	swift build -c release
	$(call assemble,release)

install: publish ## Build release and copy it to /Applications
	cp -r $(BUILD_BUNDLE) /Applications/

close: ## Quit the running app
	-killall $(APP) 2>/dev/null

uninstall: close ## Quit the app and remove it from /Applications
	rm -rf $(INSTALL_BUNDLE)

open: ## Install if needed, then open the installed app
	@if [ ! -d "$(INSTALL_BUNDLE)" ]; then $(MAKE) install; fi
	/usr/bin/open $(INSTALL_BUNDLE)

reinstall-open: publish ## Rebuild release, reinstall, and relaunch
	-killall $(APP) 2>/dev/null; sleep 0.5
	rm -rf $(INSTALL_BUNDLE)
	cp -r $(BUILD_BUNDLE) /Applications/
	/usr/bin/open $(INSTALL_BUNDLE)

clean: uninstall ## Remove build artifacts and the blob cache
	rm -rf .build build
	rm -rf "$(CACHE_DIR)"

icon: ## Regenerate the app icon
	bash scripts/make_icon.sh

test-note: build ## Build and run the Apple Notes formatting test
	$(BUILD_BUNDLE)/Contents/MacOS/$(APP) --test-note

test-markdown-import: build ## Build and run the Markdown import test
	$(BUILD_BUNDLE)/Contents/MacOS/$(APP) --markdown-import-test

reinstall: uninstall install ## Uninstall then reinstall the release build
