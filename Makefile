-include .env.local

BUILD_DIR := build
ZIP_PATH  := $(BUILD_DIR)/demo.zip

# Where the SDK repo lives, so `make vendor` can pull its latest build.
# Forward slashes only - recipes run in a POSIX shell, which eats backslashes.
SDK_REPO  ?= D:/Projects/Practice_Folders/roku_player_practice

.PHONY: build deploy vendor clean

build:
	@mkdir -p $(BUILD_DIR)
	@rm -f $(ZIP_PATH)
	@zip -r -q $(ZIP_PATH) manifest source components vendor
	@echo "Built $(ZIP_PATH)"

# No curl -f here. The device explains a rejected install in the response
# body, and -f throws that body away, leaving only a bare status code.
deploy: build
	@test -n "$(ROKU_HOST)" || { echo "ROKU_HOST is not set - create .env.local"; exit 1; }
	@test -n "$(ROKU_PASSWORD)" || { echo "ROKU_PASSWORD is not set - create .env.local"; exit 1; }
	@echo "Deploying demo to $(ROKU_HOST)"
	@out=$$(curl -s -S --digest -u rokudev:$(ROKU_PASSWORD) \
		-F "mysubmit=Install" \
		-F "archive=@$(ZIP_PATH)" \
		-w '[http %{http_code}]' \
		http://$(ROKU_HOST)/plugin_install); \
	if echo "$$out" | grep -q "Install Success"; then \
		echo "Deployed to $(ROKU_HOST)"; \
	else \
		echo "Deploy FAILED - device said:"; \
		echo "$$out" | sed -e 's/<[^>]*>//g' | grep -viE '^[[:space:]]*$$' | head -12; \
		exit 1; \
	fi

# Pull the freshly built SDK zip into vendor/, replacing any older version.
#
# The SDK keeps every released zip in its build/, so copy only the newest one.
# Copying the whole glob would leave older versions sitting in vendor/, where a
# stale filename in CONFIG() would still resolve - silently loading the wrong
# SDK instead of failing.
vendor:
	@zip=$$(ls $(SDK_REPO)/build/rbp-lib-*.zip 2>/dev/null | sort -V | tail -1); \
	test -n "$$zip" || { echo "No rbp-lib zip in $(SDK_REPO)/build - run 'make lib' there first"; exit 1; }; \
	mkdir -p vendor; \
	rm -f vendor/rbp-lib-*.zip; \
	cp "$$zip" vendor/; \
	name=$$(basename "$$zip"); \
	echo "Vendored $$name"; \
	grep -qF "pkg:/vendor/$$name" components/DemoScene.brs \
		|| echo "WARNING: CONFIG() does not reference $$name - update localUri/httpUri in components/DemoScene.brs"

clean:
	@rm -rf $(BUILD_DIR)