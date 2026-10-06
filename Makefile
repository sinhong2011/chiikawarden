# Chiikawarden — everyday commands. `make` lists them.
# Machine-specific values (dev box address) go in local.mk, which git ignores.
-include local.mk

DEV_HOST ?= devbox.local
DEV_IP   ?= 192.168.1.50
DEV_PASSWORD ?= chiikawa-dev-password
REGION   ?= us

APP     := build/Build/Products/Debug/Chiikawarden.app
BIN     := $(APP)/Contents/MacOS/Chiikawarden
XCB     := xcodebuild -project Chiikawarden.xcodeproj -scheme Chiikawarden -derivedDataPath build -allowProvisioningUpdates
DEV_CA  := $(CURDIR)/DevServer/data/root.crt

.DEFAULT_GOAL := help
.PHONY: help project build run test test-dev selftest selftest-cloud snapshots dev-up dev-seed dev-status dev-logs release clean

help: ## Show this list
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  \033[1m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

project: ## Regenerate the Xcode project from project.yml
	@xcodegen generate -q

build: project ## Build the app (Debug)
	@$(XCB) build 2>&1 | grep -E "error:|warning: .*deprecated|BUILD (SUCCEEDED|FAILED)" ; test -x "$(BIN)"

run: build ## Build and open the app
	@open "$(APP)"

test: ## VaultCore unit tests (dev-server tests skip themselves)
	@cd Packages/VaultCore && swift test 2>&1 | grep -E "✘|Test run"

test-dev: ## VaultCore tests including both dev Vaultwarden servers and SSO
	@cd Packages/VaultCore && CHIIKAWARDEN_DEV_HOST=$(DEV_IP) CHIIKAWARDEN_DEV_IP=$(DEV_IP) CHIIKAWARDEN_DEV_CA=$(DEV_CA) \
		swift test 2>&1 | grep -E "✘|Test run"

selftest: build ## In-app self-test against the dev server (isolated storage)
	@"$(BIN)" --selftest http://$(DEV_IP):18880 usagi@chiikawarden.test $(DEV_PASSWORD) \
		hachiware@chiikawarden.test $(DEV_PASSWORD) 2>/dev/null | grep -E "PASS|FAIL|SKIP|SELFTEST"

selftest-security: build ## Self-test plus the steps that sign in again (sign-in approval, password and KDF changes)
	@CHIIKAWARDEN_SELFTEST_SECURITY=1 "$(BIN)" --selftest http://$(DEV_IP):18880 usagi@chiikawarden.test $(DEV_PASSWORD) \
		hachiware@chiikawarden.test $(DEV_PASSWORD) 2>/dev/null | grep -E "PASS|FAIL|SKIP|SELFTEST"

selftest-cloud: build ## Self-test against Bitwarden cloud with the account in .env (REGION=us|eu)
	@test -f .env || { echo "Create .env with BITWARDEN_ACCOUNT=… and BITWARDEN_PASSWORD=… (an empty test account)"; exit 64; }
	@set -a; . ./.env; set +a; "$(BIN)" --selftest-cloud $(REGION) 2>/dev/null

sparkle-keys: build ## One-time: create the update-signing key (kept in your keychain) and put its public half in project.yml
	@BIN=build/SourcePackages/artifacts/sparkle/Sparkle/bin; \
	"$$BIN/generate_keys" >/dev/null; \
	KEY=$$("$$BIN/generate_keys" -p); \
	sed -i '' -E "s|^( *SPARKLE_PUBLIC_KEY: )\"[^\"]*\"|\1\"$$KEY\"|" project.yml; \
	echo "Public key $$KEY written to project.yml — commit it."; \
	echo "For CI, export the private key and store it as the SPARKLE_PRIVATE_KEY secret (see docs/RELEASING.md)."

uitest: ## Click-through UI tests in --demo mode (quit any running Chiikawarden first)
	@xcodebuild -project Chiikawarden.xcodeproj -scheme Chiikawarden -derivedDataPath build -allowProvisioningUpdates \
		test -only-testing:ChiikawardenUITests 2>&1 | grep -E "\.swift:[0-9]+: error|' (passed|failed)|TEST (SUCCEEDED|FAILED)"

snapshots: build ## Render UI snapshots (light + dark) into build/snapshots
	@dir=$$("$(BIN)" --snapshot 2>/dev/null | tail -1); mkdir -p build/snapshots; cp "$$dir"/*.png build/snapshots/; \
		echo "$$(ls build/snapshots | wc -l | tr -d ' ') images in build/snapshots"

dev-up: ## Start the dev servers on the dev box (Vaultwarden ×2, SSO + dex, Mailpit)
	@CHIIKAWARDEN_DEV_HOST=$(DEV_HOST) CHIIKAWARDEN_DEV_IP=$(DEV_IP) DevServer/dev.sh up

dev-seed: ## Seed test accounts and items
	@CHIIKAWARDEN_DEV_HOST=$(DEV_HOST) CHIIKAWARDEN_DEV_IP=$(DEV_IP) DevServer/dev.sh seed

dev-status: ## Dev server containers
	@CHIIKAWARDEN_DEV_HOST=$(DEV_HOST) CHIIKAWARDEN_DEV_IP=$(DEV_IP) DevServer/dev.sh status

dev-logs: ## Dev server logs (SERVICE=vaultwarden|vaultwarden-sso|dex|…)
	@CHIIKAWARDEN_DEV_HOST=$(DEV_HOST) CHIIKAWARDEN_DEV_IP=$(DEV_IP) DevServer/dev.sh logs $(SERVICE)

release: ## Signed, notarized release: make release VERSION=0.3.0 [ARGS=--publish]
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=0.3.0 [ARGS=--publish]"; exit 64; }
	@scripts/release.sh $(VERSION) $(ARGS)

clean: ## Remove build output
	@rm -rf build/Build build/Logs build/snapshots
