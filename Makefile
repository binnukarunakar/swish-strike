# Swish Strike — one entry point for every check that runs without Xcode,
# plus the two commands that need an Xcode Mac.

WEB := web-prototype
CORE := ios/SwishStrikeCore

.PHONY: verify web-test web-ui core-check parity icons typecheck xcodeproj clean

## Everything verifiable on a plain Mac (Command Line Tools only)
verify: web-test core-check parity typecheck
	@echo "── all non-Xcode checks passed ──"

web-test:            ## JS engine + parity + CV + pipeline suites
	cd $(WEB) && node --test

web-ui:              ## Full UI flow in real Chrome (needs: make serve, in another shell)
	cd $(WEB) && python3 test/ui_smoke.py

serve:               ## Static server for the web prototype / UI tests
	cd $(WEB) && python3 -m http.server 8777

core-check:          ## Swift engine headless harness (no Xcode)
	cd $(CORE) && swift run SwishStrikeCoreCheck

parity:              ## Cross-language golden-trace proof (JS ↔ Swift)
	cd $(CORE) && swift run SwishStrikeParity

icons:               ## Regenerate the app icon PNGs (CoreGraphics, license-clean)
	swift tools/gen-icon.swift

typecheck:           ## Best-effort macOS typecheck of platform-agnostic app sources
	bash tools/typecheck-macos.sh


## ── Xcode Mac only ──────────────────────────────────────────────────────────
xcodeproj:           ## Regenerate the project if the committed one won't open
	cd ios/SwishStrikeApp && xcodegen generate

# Build + test on a simulator (run on the Xcode Mac):
#   xcodebuild -project ios/SwishStrikeApp/SwishStrike.xcodeproj -scheme SwishStrike \
#     -destination 'platform=iOS Simulator,name=iPhone 16' build

clean:
	rm -rf dist $(CORE)/.build
