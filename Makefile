APP_NAME := Nudge Lamp.app
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
	-pkill -x NudgeLamp; while pgrep -x NudgeLamp >/dev/null; do sleep 0.2; done
	open "build/$(APP_NAME)"

# Launched through `open` so macOS reports the app's own permissions, not the terminal's.
doctor: app
	open -n -W --stdout "$$(tty)" "build/$(APP_NAME)" --args --doctor

# Builds a universal app, zips it and publishes it as a GitHub release for install.sh.
release:
	UNIVERSAL=1 ./scripts/build-app.sh
	rm -f build/NudgeLamp.zip
	ditto -c -k --norsrc --noextattr --noacl --keepParent "build/$(APP_NAME)" build/NudgeLamp.zip
	gh release create "v$(VERSION)" build/NudgeLamp.zip \
		--title "Nudge Lamp $(VERSION)" \
		--notes "Install or update with: curl -fsSL https://raw.githubusercontent.com/yoshimoriryu/nudge-lamp/main/install.sh | bash"

clean:
	rm -rf .build build
