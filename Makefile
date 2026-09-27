# Building lives here. Everything you do to a running XMonadMac lives in the
# `xmonad` command that `make install` puts on your PATH.
#
# CONFIG is left empty so build-engine.sh resolves the config the same way the
# running engine does: ~/.xmonad/xmonad.hs, then ~/.config/xmonad-mac/xmonad.hs,
# then the shipped example/xmonad.hs. Override with `make build CONFIG=<path>`.
CONFIG ?=

.PHONY: help bootstrap build install package run dry-run check icon clean

help:
	@echo "make bootstrap   install the toolchain, build, and install"
	@echo "make build       build the engine and the native app (config: ~/.xmonad/xmonad.hs or example/xmonad.hs; CONFIG=<path> overrides)"
	@echo "make install     install the app, the engine, and the xmonad command"
	@echo "make package     build the release XMonadMac.app and its zip"
	@echo "make run         launch XMonadMac (xmonad start)"
	@echo "make check       Swift, Haskell, integration and packaging tests"
	@echo "make clean       remove build/ and dist-newstyle/"
	@echo ""
	@echo "Once installed, use xmonad for everything else:"
	@echo "  xmonad start [--dry-run]  launch the app"
	@echo "  xmonad --recompile        compile xmonad.hs into a new engine"
	@echo "  xmonad --restart          run the compiled config"
	@echo "  xmonad status | doctor | log | recover | pause | quit"
	@echo "  xmonad autostart on       start at login"

bootstrap: ; ./scripts/bootstrap.sh $(CONFIG)
build: ; ./scripts/build.sh $(CONFIG)
install: ; ./scripts/install.sh
package: ; ./scripts/package.sh
run: ; "$(HOME)/.local/bin/xmonad" start
dry-run: ; "$(HOME)/.local/bin/xmonad" start --dry-run
check: ; ./scripts/test-portable.sh && ./scripts/test.sh
icon: ; ./scripts/make-icon.sh
clean: ; rm -rf build dist-newstyle
