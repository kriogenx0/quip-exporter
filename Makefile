APP        := QuipExporter
BUNDLE     := $(APP).app
EXE        := .build/release/$(APP)
CONTENTS   := $(BUNDLE)/Contents
CACHE_DIR  := $(HOME)/Library/Application Support/QuipExporter/BlobCache

.PHONY: build app open clean clean-cache

build:
	swift build -c release

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(EXE) $(CONTENTS)/MacOS/$(APP)
	cp Info.plist $(CONTENTS)/
	codesign --force --deep --sign - $(BUNDLE)
	@echo "$(BUNDLE) ready"

open: app
	-killall $(APP) 2>/dev/null; sleep 0.5
	open $(BUNDLE)

clean:
	rm -rf .build $(BUNDLE)

clean-cache:
	rm -rf "$(CACHE_DIR)"
	@echo "Cache cleared"
