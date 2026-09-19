NAME := VexSign
PLATFORM := iphoneos
SCHEMES := VexSign
# TMPDIR is unset in some environments (plain Linux CI, bare shells); without a
# fallback the paths below would resolve to "/$(NAME)" and fail on permissions.
TMP := $(if $(TMPDIR),$(TMPDIR),/tmp)/$(NAME)
STAGE := $(TMP)/stage
APP := $(TMP)/Build/Products/Release-$(PLATFORM)
CERT_JSON_URL := https://vexsign-install.vexsign.workers.dev/pack.json

.PHONY: all deps clean deploy-server $(SCHEMES)

all: $(SCHEMES)

clean:
	rm -rf $(TMP)
	rm -rf packages
	rm -rf Payload

deps:
	rm -rf deps || true
	mkdir -p deps

	@if curl -fsSL "$(CERT_JSON_URL)" -o cert.json; then \
	    jq -r '.cert, .ca' cert.json > deps/server.crt; \
	    jq -rj '.key1, .key2' cert.json > deps/server.pem; \
	    jq -r '.info.domains.commonName' cert.json > deps/commonName.txt; \
	else \
	    echo "warning: $(CERT_JSON_URL) unavailable, building without a bundled certificate"; \
	fi

$(SCHEMES): deps
	xcodebuild \
	    -project VexSign.xcodeproj \
	    -scheme "$@" \
	    -configuration Release \
	    -arch arm64 \
	    -sdk $(PLATFORM) \
	    -derivedDataPath $(TMP) \
	    -skipPackagePluginValidation \
	    CODE_SIGNING_ALLOWED=NO \
	    ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=NO

	rm -rf Payload
	rm -rf $(STAGE)/
	mkdir -p $(STAGE)/Payload

	mv "$(APP)/$@.app" "$(STAGE)/Payload/$@.app"

	chmod -R 0755 "$(STAGE)/Payload/$@.app"
	codesign --force --sign - --timestamp=none "$(STAGE)/Payload/$@.app"

	cp deps/* "$(STAGE)/Payload/$@.app/" || true

	rm -rf "$(STAGE)/Payload/$@.app/_CodeSignature"
	ln -sf "$(STAGE)/Payload" Payload
	
	mkdir -p packages
	zip -r9 "packages/$@.ipa" Payload

# Self-hosted backend (server/). Keep this BELOW `all` — make builds the first
# target in the file, so a rule above it would hijack a bare `make` (which is
# what CI runs).
#   docker run -p 8080:8080 -e ADMIN_TOKEN=<secret> -v vexsign-repo:/data \
#     vexsign-server   # then add /repo/source.json as a source in the app
IMAGE ?= vexsign-server
deploy-server:
	@command -v docker >/dev/null 2>&1 || { \
		echo "docker is not installed; see server/README.md for the deploy steps"; exit 1; }
	docker build --platform linux/amd64 -t $(IMAGE) server
	@echo "Built $(IMAGE). Run it with:"
	@echo "  docker run -p 8080:8080 -e ADMIN_TOKEN=<secret> -e REPO_STORE_DIR=/data \\"
	@echo "    -v vexsign-repo:/data $(IMAGE)"
