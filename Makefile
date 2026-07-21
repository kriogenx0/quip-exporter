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

.PHONY: build dev publish install uninstall open close reinstall-open clean reinstall icon test-note test-markdown-import

build:
	swift build --disable-sandbox
	$(call assemble,debug)

dev:
	-killall $(APP) 2>/dev/null; sleep 0.5
	$(MAKE) build
	/usr/bin/open $(BUILD_BUNDLE)

publish:
	swift build -c release
	$(call assemble,release)

install: publish
	cp -r $(BUILD_BUNDLE) /Applications/

close:
	-killall $(APP) 2>/dev/null

uninstall: close
	rm -rf $(INSTALL_BUNDLE)

open:
	@if [ ! -d "$(INSTALL_BUNDLE)" ]; then $(MAKE) install; fi
	/usr/bin/open $(INSTALL_BUNDLE)

reinstall-open: publish
	-killall $(APP) 2>/dev/null; sleep 0.5
	rm -rf $(INSTALL_BUNDLE)
	cp -r $(BUILD_BUNDLE) /Applications/
	/usr/bin/open $(INSTALL_BUNDLE)

clean: uninstall
	rm -rf .build build
	rm -rf "$(CACHE_DIR)"

icon:
	bash scripts/make_icon.sh

test-note: build
	$(BUILD_BUNDLE)/Contents/MacOS/$(APP) --test-note

test-markdown-import: build
	$(BUILD_BUNDLE)/Contents/MacOS/$(APP) --markdown-import-test

reinstall: uninstall install
