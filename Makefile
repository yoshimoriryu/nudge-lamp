APP_NAME := Agent Lamp.app
INSTALL_DIR := $(HOME)/Applications

.PHONY: app test install uninstall run clean

app:
	./scripts/build-app.sh

test:
	swift test

install: app
	mkdir -p "$(INSTALL_DIR)"
	-pkill -x AgentLamp
	rm -rf "$(INSTALL_DIR)/$(APP_NAME)"
	cp -R "build/$(APP_NAME)" "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP_NAME)"

uninstall:
	-pkill -x AgentLamp
	rm -rf "$(INSTALL_DIR)/$(APP_NAME)"

run: app
	-pkill -x AgentLamp
	open "build/$(APP_NAME)"

clean:
	rm -rf .build build
