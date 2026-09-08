# Thin front end over scripts/. Each target is one script; the scripts stay the
# implementation so CI and the installed build kit keep working unchanged.
CONFIG ?= config/xmonad.hs

.PHONY: help bootstrap build engine native icon install reload recompile run \
        dry-run test test-portable check doctor recover autostart-on \
        autostart-off status clean

help:
	@echo "make bootstrap      install toolchain, build, install"
	@echo "make build          build engine + native app (CONFIG=$(CONFIG))"
	@echo "make engine         build the Haskell engine only"
	@echo "make native         build and sign XMonadMac.app only"
	@echo "make icon           regenerate app and menu bar icons from SVG"
	@echo "make install        install app, engine, and xmonadctl"
	@echo "make reload         recompile the config and reload a running app"
	@echo "make run            launch XMonadMac"
	@echo "make dry-run        launch read-only (no windows moved)"
	@echo "make check          test + test-portable"
	@echo "make doctor         diagnostics for an installed app"
	@echo "make autostart-on   start at login (autostart-off to undo)"
	@echo "make clean          remove build/ and dist-newstyle/"

bootstrap: ; ./scripts/bootstrap.sh $(CONFIG)
build: ; ./scripts/build.sh $(CONFIG)
engine: ; ./scripts/build-engine.sh $(CONFIG)
native: ; ./scripts/build-native.sh
icon: ; ./scripts/make-icon.sh
install: ; ./scripts/install.sh
reload recompile: ; ./scripts/reload.sh $(CONFIG)
run: ; ./scripts/run.sh
dry-run: ; ./scripts/run.sh --dry-run
test: ; ./scripts/test.sh
test-portable: ; ./scripts/test-portable.sh
check: test-portable test
doctor: ; ./scripts/doctor.sh
recover: ; ./scripts/recover.sh
autostart-on: ; ./scripts/autostart.sh on
autostart-off: ; ./scripts/autostart.sh off
status: ; @cat "$$HOME/Library/Application Support/XMonadMac/status.json"
clean: ; rm -rf build dist-newstyle
