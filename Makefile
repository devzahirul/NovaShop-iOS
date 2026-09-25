# NovaShop developer entry points. `make help` lists targets.
SHELL := /bin/bash
PROJECT := NovaShop.xcodeproj
SCHEME := NovaShop
# First available iPhone simulator (override: make test SIMULATOR_ID=<udid>)
SIMULATOR_ID ?= $(shell xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print(next(x['udid'] for r in d.values() for x in r if 'iPhone' in x['name']))")
DESTINATION := platform=iOS Simulator,id=$(SIMULATOR_ID)
XCBEAUTIFY := $(shell command -v xcbeautify 2>/dev/null || echo cat)

.PHONY: help bootstrap project open build test test-unit test-ui lint format screenshots fixtures launch-bench size clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Install tooling (XcodeGen, SwiftLint, SwiftFormat, xcbeautify)
	brew install xcodegen swiftlint swiftformat xcbeautify

project: ## Generate NovaShop.xcodeproj from project.yml
	xcodegen generate

open: project ## Generate and open in Xcode
	open $(PROJECT)

build: project ## Debug build for the simulator
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' build | $(XCBEAUTIFY)

test-unit: ## Unit tests for every NovaKit module (swift-testing)
	cd Packages/NovaKit && xcodebuild test -scheme NovaKit -destination '$(DESTINATION)' | $(XCBEAUTIFY)

test-ui: project ## Critical-path UI tests
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:NovaShopUITests/NovaShopUITests | $(XCBEAUTIFY)

test: test-unit test-ui ## All tests

lint: ## SwiftLint + SwiftFormat (check only)
	swiftlint lint --strict
	swiftformat --lint .

format: ## Auto-format sources
	swiftformat .
	swiftlint lint --fix

screenshots: project ## Capture light/dark screenshots into docs/screenshots
	rm -rf build/screenshots.xcresult build/attachments
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:NovaShopUITests/ScreenshotTests -resultBundlePath build/screenshots.xcresult | $(XCBEAUTIFY)
	xcrun xcresulttool export attachments --path build/screenshots.xcresult --output-path build/attachments
	python3 scripts/export_screenshots.py build/attachments docs/screenshots

fixtures: ## Regenerate the fixture API JSON
	python3 scripts/generate_fixtures.py

launch-bench: project ## Cold-launch 6× (Release) and print in-app signpost timings
	./scripts/launch_bench.sh '$(SIMULATOR_ID)'

size: project ## Stripped device binary size (App Thinning report needs an archive + signing)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination 'generic/platform=iOS' \
		-derivedDataPath build/size CODE_SIGNING_ALLOWED=NO DEPLOYMENT_POSTPROCESSING=YES build | $(XCBEAUTIFY)
	du -sh build/size/Build/Products/Release-iphoneos/NovaShop.app

clean: ## Remove build products
	rm -rf build DerivedData
