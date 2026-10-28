NAME := Ksign
PLATFORM := iphoneos
SCHEMES := Ksign
TMP := $(TMPDIR)/$(NAME)
STAGE := $(TMP)/stage
APP := $(TMP)/Build/Products/Release-$(PLATFORM)

.PHONY: all clean $(SCHEMES)

all: $(SCHEMES)

clean:
	rm -rf "$(TMP)"
	rm -rf packages
	rm -rf Payload

deps:
	rm -rf deps || true
	mkdir -p deps
	# backloop.dev 已改为只提供 pack.json（旧的 .crt/.key 直链 404，
	# 以前会静默把 404 HTML 打进包里，导致本地 TLS 用废证书 → Safari 报“非私人连接”）
	curl -fsSL https://backloop.dev/pack.json -o deps/pack.json
	jq -er '.cert' deps/pack.json > deps/server.crt
	jq -er '.ca' deps/pack.json >> deps/server.crt
	jq -er '.key1 + .key2' deps/pack.json > deps/server.pem
	jq -er '.info.domains.commonName' deps/pack.json > deps/commonName.txt
	rm -f deps/pack.json
	@echo "--- bundled TLS material:" && head -1 deps/server.crt && grep -c BEGIN deps/server.crt && head -1 deps/server.pem && cat deps/commonName.txt

$(SCHEMES): deps
	xcodebuild \
	    -project Ksign.xcodeproj \
	    -scheme "$@" \
	    -configuration Release \
	    -arch arm64 \
	    -sdk $(PLATFORM) \
	    -derivedDataPath $(TMP) \
	    -skipPackagePluginValidation \
	    CODE_SIGNING_ALLOWED=NO \
	    ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=NO

	rm -rf Payload
	rm -rf "$(STAGE)/"
	mkdir -p "$(STAGE)/Payload"

	mv "$(APP)/$@.app" "$(STAGE)/Payload/$@.app"

	chmod -R 0755 "$(STAGE)/Payload/$@.app"
	codesign --force --sign - --timestamp=none "$(STAGE)/Payload/$@.app"

	cp deps/* "$(STAGE)/Payload/$@.app/" || true

	rm -rf "$(STAGE)/Payload/$@.app/_CodeSignature"
	ln -sf "$(STAGE)/Payload" Payload
	
	mkdir -p packages
	zip -r9 "packages/$@.ipa" Payload