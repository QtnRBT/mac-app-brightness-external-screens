.PHONY: build app run install clean

build:
	swift build

app:
	./scripts/build-app.sh

run: app
	open build/ScreenBrightness.app

install: app
	rm -rf /Applications/ScreenBrightness.app
	cp -R build/ScreenBrightness.app /Applications/
	open /Applications/ScreenBrightness.app

clean:
	rm -rf .build build
