APP_NAME := Agent Lamp.app
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)

.PHONY: app test install uninstall run doctor release clean

app:
	./scripts/build-app.sh

test:
	swift test

install:
	./install.sh --from-source

uninstall:
	./install.sh --uninstall

run: app
	-pkill -x AgentLamp; while pgrep -x AgentLamp >/dev/null; do sleep 0.2; done
	open "build/$(APP_NAME)"

# Launched through `open` so macOS reports the app's own permissions, not the terminal's.
doctor: app
	open -n -W --stdout "$$(tty)" "build/$(APP_NAME)" --args --doctor

# Builds a universal app, zips it and publishes it as a GitHub release for install.sh.
release:
	UNIVERSAL=1 ./scripts/build-app.sh
	rm -f build/AgentLamp.zip
	ditto -c -k --keepParent "build/$(APP_NAME)" build/AgentLamp.zip
	gh release create "v$(VERSION)" build/AgentLamp.zip \
		--title "Agent Lamp $(VERSION)" \
		--notes "Install or update with: curl -fsSL https://raw.githubusercontent.com/yoshimoriryu/agent-lamp/main/install.sh | bash"

clean:
	rm -rf .build build
