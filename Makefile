.PHONY: run stop restart logs status build test clean release install

APP_NAME := UsageTracker
PID_FILE := .usagetracker.pid
LOG_FILE := .usagetracker.log

build:
	swift build

test:
	swift test

run: build
	@if [ -f $(PID_FILE) ] && kill -0 $$(cat $(PID_FILE)) 2>/dev/null; then \
		echo "$(APP_NAME) is already running (PID $$(cat $(PID_FILE)))"; \
	else \
		.build/debug/$(APP_NAME) >> $(LOG_FILE) 2>&1 & \
		echo $$! > $(PID_FILE); \
		echo "$(APP_NAME) started (PID $$!)"; \
		echo "Logs: make logs"; \
	fi

stop:
	@if [ -f $(PID_FILE) ] && kill -0 $$(cat $(PID_FILE)) 2>/dev/null; then \
		kill $$(cat $(PID_FILE)); \
		rm -f $(PID_FILE); \
		echo "$(APP_NAME) stopped"; \
	else \
		rm -f $(PID_FILE); \
		echo "$(APP_NAME) is not running"; \
	fi

restart: stop run

logs:
	@touch $(LOG_FILE)
	@tail -f $(LOG_FILE)

status:
	@if [ -f $(PID_FILE) ] && kill -0 $$(cat $(PID_FILE)) 2>/dev/null; then \
		echo "$(APP_NAME) is running (PID $$(cat $(PID_FILE)))"; \
	else \
		rm -f $(PID_FILE); \
		echo "$(APP_NAME) is not running"; \
	fi

clean:
	swift package clean
	rm -f $(PID_FILE) $(LOG_FILE)

release:
	./scripts/release.sh

# Build a signed .app and install it to /Applications for local use on this Mac
# (no notarization needed for a locally-built app). Use `release` for a DMG.
install:
	swift build -c release
	./scripts/install_local.sh
