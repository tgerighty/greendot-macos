CONFIG ?= release
APP := greendot.app
BIN := greendot
SWIFTFLAGS ?=
BINDIR = $(shell swift build -c $(CONFIG) $(SWIFTFLAGS) --show-bin-path)

.PHONY: build test app install clean uitest lint bench

build:
	swift build -c $(CONFIG) $(SWIFTFLAGS)

test:
	swift test $(SWIFTFLAGS)

bench:
	swift test --filter PerformanceHarnessTests $(SWIFTFLAGS)

lint:
	swiftlint lint --strict

GIT_HASH = $(shell git rev-parse --short HEAD)

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :GitCommitHash string $(GIT_HASH)" "$(APP)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	cp "$(BINDIR)/$(BIN)" "$(APP)/Contents/MacOS/$(BIN)"
	codesign --force --sign - "$(APP)"

install: app
	rm -rf "/Applications/$(APP)"
	cp -R "$(APP)" /Applications/
	@echo "Installed to /Applications/$(APP)"

clean:
	rm -rf .build "$(APP)" UITests/GreenDotUITests.xcodeproj

uitest: app
	-@pkill -f 'greendot.app/Contents/MacOS/greendot' 2>/dev/null || true
	@n=0; while pgrep -f 'greendot.app/Contents/MacOS/greendot' >/dev/null 2>&1; do \
		n=$$((n+1)); \
		if [ $$n -gt 50 ]; then \
			echo "ERROR: greendot is still running after 5s; kill it and retry" >&2; \
			exit 1; \
		fi; \
		sleep 0.1; \
	done
	cd UITests && xcodegen generate
	xcodebuild test \
		-project UITests/GreenDotUITests.xcodeproj \
		-scheme GreenDotUITests \
		-destination 'platform=macOS'
