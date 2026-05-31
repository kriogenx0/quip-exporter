APP            := QuipExporter
BUILD_BUNDLE   := build/$(APP).app
INSTALL_BUNDLE := /Applications/$(APP).app
CONTENTS       := $(BUILD_BUNDLE)/Contents
CACHE_DIR      := $(HOME)/Library/Application Support/$(APP)/BlobCache

.PHONY: build dev publish install uninstall open close reinstall-open clean reinstall

build:
	swift build
	rm -rf $(BUILD_BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp .build/debug/$(APP) $(CONTENTS)/MacOS/$(APP)
	cp Info.plist $(CONTENTS)/
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(CONTENTS)/Resources/; fi
	codesign --force --deep --sign - $(BUILD_BUNDLE)

dev:
	-killall $(APP) 2>/dev/null; sleep 0.5
	rm -rf $(BUILD_BUNDLE)
	$(MAKE) build
	/usr/bin/open $(BUILD_BUNDLE)

publish:
	swift build -c release
	rm -rf $(BUILD_BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp .build/release/$(APP) $(CONTENTS)/MacOS/$(APP)
	cp Info.plist $(CONTENTS)/
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(CONTENTS)/Resources/; fi
	codesign --force --deep --sign - $(BUILD_BUNDLE)

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

reinstall: uninstall install
