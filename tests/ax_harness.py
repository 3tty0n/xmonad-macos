#!/usr/bin/env python3
"""Desktop AX integration checks for the XMonadMac helper.

This drives the test-only AXFixture app and compares what the fixture's AppKit
windows actually are with the helper's diagnostic snapshot. It never edits
window titles or frames of other applications, but it does create and close
fixture windows, so it requires --allow-desktop.

Usage:
  python3 tests/ax_harness.py --allow-desktop [--fixture PATH]

Requires a running, configured XMonadMac and Accessibility permission for it.
"""
import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SUPPORT = Path.home() / "Library" / "Application Support" / "XMonadMac"
SNAPSHOT = SUPPORT / "diagnostic-snapshot.json"
STATUS = SUPPORT / "status.json"


def fail(message, detail=None):
    if detail is not None:
        message += "\n" + json.dumps(detail, indent=2, ensure_ascii=False)
    raise AssertionError(message)


def check(condition, message, detail=None):
    if not condition:
        fail(message, detail)


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path}: {error}")


def run_xmonad(*args, timeout=10):
    xmonad = os.environ.get("XMONAD") or shutil.which("xmonad")
    if not xmonad:
        fail("xmonad is not on PATH")
    try:
        return subprocess.run(
            [xmonad, *args], text=True, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        fail(f"xmonad {' '.join(args)} timed out")


def dump_snapshot(timeout=4.0):
    """Ask the helper for a fresh diagnostic snapshot and return it."""
    before = SNAPSHOT.stat().st_mtime_ns if SNAPSHOT.exists() else 0
    result = run_xmonad("dump")
    check(result.returncode == 0,
          "xmonad dump failed; is XMonadMac running?",
          {"stderr": result.stderr, "stdout": result.stdout})
    deadline = time.time() + timeout
    while time.time() < deadline:
        if SNAPSHOT.exists() and SNAPSHOT.stat().st_mtime_ns > before:
            snapshot = read_json(SNAPSHOT)
            check(snapshot.get("type") == "snapshot",
                  "diagnostic snapshot is malformed", snapshot)
            return snapshot
        time.sleep(0.05)
    fail("helper did not write a new diagnostic snapshot")


def wait_for(predicate, description, timeout=8.0):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = dump_snapshot()
        if predicate(last):
            return last
        time.sleep(0.2)
    fail(f"timed out waiting for {description}", last)


def windows_of(snapshot, pid):
    return [w for w in snapshot.get("windows", []) if w.get("pid") == pid]


def title_of(window):
    return window.get("titleText", "")


def by_title(snapshot, pid, title):
    for window in windows_of(snapshot, pid):
        if title_of(window) == title:
            return window
    return None


def frame_close(actual, expected, tolerance=16):
    if not actual or not expected:
        return False
    return all(
        abs(actual.get(key, 0) - expected.get(key, 0)) <= tolerance
        for key in ("x", "y", "width", "height"))


class Fixture:
    def __init__(self, fixture, state, *args):
        self.state_path = Path(state)
        self.process = subprocess.Popen(
            [fixture, "--state", str(self.state_path), *args],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, bufsize=1)

    def state(self):
        return read_json(self.state_path)

    def send(self, command):
        if self.process.poll() is not None:
            stderr = self.process.stderr.read() if self.process.stderr else ""
            fail(f"fixture exited before '{command}'",
                 {"returncode": self.process.returncode, "stderr": stderr})
        self.process.stdin.write(command + "\n")
        self.process.stdin.flush()

    def wait_windows(self, count, timeout=8.0):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            if self.state_path.exists():
                last = self.state()
                if len(last.get("windows", [])) == count:
                    return last
            time.sleep(0.05)
        fail(f"fixture did not report {count} windows", last)

    def quit(self):
        if self.process.poll() is None:
            try:
                self.send("quit")
                self.process.wait(timeout=5)
            except (BrokenPipeError, subprocess.TimeoutExpired):
                self.process.send_signal(signal.SIGKILL)
                self.process.wait(timeout=5)


def launch(fixture, state, *args):
    instance = Fixture(fixture, state, *args)
    try:
        instance.wait_windows(int(args[args.index("--windows") + 1])
                              if "--windows" in args else 3)
    except Exception:
        instance.quit()
        raise
    return instance


def test_regular(fixture, directory):
    prefix = "AXFixture-primary"
    state = directory / "primary.json"
    app = launch(fixture, state, "--windows", "3", "--title-prefix", prefix)
    try:
        pid = app.state()["pid"]
        snapshot = wait_for(
            lambda s: len(windows_of(s, pid)) == 3,
            "three regular fixture windows")
        titles = sorted(title_of(w) for w in windows_of(snapshot, pid))
        check(titles == [f"{prefix} 1", f"{prefix} 2", f"{prefix} 3"],
              "the helper lost or renamed a regular window", titles)

        app.send("focus 2")
        snapshot = wait_for(
            lambda s: (by_title(s, pid, f"{prefix} 2") or {}).get("wid")
            == s.get("focused"),
            "focus to follow the fixture's key window")
        check(not by_title(snapshot, pid, f"{prefix} 2").get("minimized", True),
              "the focused fixture window is minimized")

        app.send("close 3")
        snapshot = wait_for(
            lambda s: by_title(s, pid, f"{prefix} 3") is None,
            "a closed fixture window to leave the snapshot")
        check(len(windows_of(snapshot, pid)) == 2,
              "closing one fixture window removed another", snapshot)

        app.send("minimize 1")
        wait_for(
            lambda s: by_title(s, pid, f"{prefix} 1") is None,
            "a user-minimized fixture window to leave the snapshot")
        time.sleep(1.5)
        snapshot = dump_snapshot()
        check(by_title(snapshot, pid, f"{prefix} 1") is None,
              "the helper restored a user-minimized window", snapshot)
        app.send("unminimize 1")
        wait_for(
            lambda s: (by_title(s, pid, f"{prefix} 1") or {}).get("minimized") is False,
            "the fixture to unminimize its window")

        app.send("new")
        app.wait_windows(3)
        added = [w for w in app.state()["windows"] if w["id"] == 4][0]
        wait_for(
            lambda s: by_title(s, pid, added["title"]) is not None,
            "a window created after the initial scan")
        app.send("delay-minimize 4 500")
        wait_for(
            lambda s: by_title(s, pid, added["title"]) is None,
            "a delayed minimize to leave the snapshot")
        check([w for w in app.state()["windows"] if w["id"] == 4][0]["minimized"],
              "the fixture did not minimize its delayed window")
        app.send("unminimize 4")
        wait_for(
            lambda s: by_title(s, pid, added["title"]) is not None,
            "the delayed-minimized window to return")

        # A window that disappears from the snapshot only after a real close
        # is the ownership/identity case that silently moves windows.
        app.send("close 2")
        wait_for(
            lambda s: by_title(s, pid, f"{prefix} 2") is None,
            "the second closed fixture window to leave")
    finally:
        app.quit()


def test_duplicate_titles(fixture, directory):
    prefix = "AXFixture-duplicates"
    state = directory / "duplicates.json"
    app = launch(fixture, state, "--windows", "2", "--duplicate-titles",
                 "--title-prefix", prefix)
    try:
        pid = app.state()["pid"]
        snapshot = wait_for(
            lambda s: len(windows_of(s, pid)) == 2,
            "two duplicate-title fixture windows")
        windows = windows_of(snapshot, pid)
        check(len(windows) == 2 and all(title_of(w) == f"{prefix} duplicate"
                                        for w in windows),
              "duplicate titles collapsed into one window", windows)
    finally:
        app.quit()


def test_native_tabs(fixture, directory):
    prefix = "AXFixture-tabs"
    state = directory / "tabs.json"
    app = launch(fixture, state, "--windows", "1", "--title-prefix", prefix)
    try:
        pid = app.state()["pid"]
        wait_for(lambda s: len(windows_of(s, pid)) == 1,
                 "the initial tabbed fixture window")
        app.send("tab 1")
        app.wait_windows(2)
        # A native tab group exposes both windows to AX at the same frame.
        # Policy must manage the one container, not drop both as ambiguous.
        time.sleep(1.5)
        snapshot = dump_snapshot()
        windows = windows_of(snapshot, pid)
        check(len(windows) == 1,
              "native tab siblings must not be managed as separate windows",
              windows)
        check(windows[0].get("minimized") is False,
              "the active tab was left minimized", windows[0])
    finally:
        app.quit()


def test_hung_app_does_not_starve(fixture, directory):
    prefix = "AXFixture-hung"
    state = directory / "hung.json"
    app = launch(fixture, state, "--windows", "1", "--title-prefix", prefix)
    try:
        pid = app.state()["pid"]
        wait_for(lambda s: len(windows_of(s, pid)) == 1,
                 "the unresponsive fixture window")
        app.send("hang 3000")
        # The hung app must not stop another app from being admitted.
        primary = launch(fixture, directory / "primary-2.json",
                         "--windows", "1", "--title-prefix", "AXFixture-responsive")
        try:
            responsive_pid = primary.state()["pid"]
            wait_for(
                lambda s: len(windows_of(s, responsive_pid)) == 1,
                "a responsive app while another app is hung", timeout=5.0)
            # The hung app's own window is retained from its last observation;
            # it must not be mistaken for a closed window.
            wait_for(
                lambda s: len(windows_of(s, pid)) == 1,
                "the hung app's known window to remain in the snapshot", timeout=5.0)
        finally:
            primary.quit()
    finally:
        app.quit()


def test_accessory_fixed(fixture, directory):
    prefix = "AXFixture-accessory"
    state = directory / "accessory.json"
    app = launch(fixture, state, "--windows", "1", "--fixed", "--accessory",
                 "--title-prefix", prefix)
    try:
        pid = app.state()["pid"]
        snapshot = wait_for(
            lambda s: any(w.get("accessory") is True for w in windows_of(s, pid)),
            "a fixed-size accessory fixture window with the accessory flag")
        window = windows_of(snapshot, pid)[0]
        check(window.get("accessory") is True,
              "the accessory flag did not reach policy", window)
        check(window.get("minimized") is False,
              "the accessory window is minimized", window)
        expected = app.state()["windows"][0]["topLeftFrame"]
        check(frame_close(window.get("frame"), expected),
              "the floating accessory window was moved unexpectedly",
              {"observed": window.get("frame"), "expected": expected})
    finally:
        app.quit()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", default=str(
        Path(__file__).resolve().parent.parent / "build/AXFixture.app/Contents/MacOS/AXFixture"))
    parser.add_argument("--allow-desktop", action="store_true",
                        help="allow creating and closing fixture windows on the desktop")
    args = parser.parse_args()
    if not args.allow_desktop:
        raise SystemExit(
            "Refusing to create desktop windows without --allow-desktop.")
    check(Path(args.fixture).is_file(), f"fixture not found: {args.fixture}")
    status = read_json(STATUS)
    check(status.get("running"), "XMonadMac is not running", status)
    check(status.get("configured"), "XMonadMac is not configured", status)
    # Stale fixtures from an interrupted run would inflate the member count.
    subprocess.run(["pkill", "-x", "AXFixture"], capture_output=True)
    time.sleep(0.3)
    directory = Path(tempfile.mkdtemp(prefix="xmonad-ax-"))
    try:
        test_regular(args.fixture, directory)
        test_duplicate_titles(args.fixture, directory)
        test_native_tabs(args.fixture, directory)
        test_hung_app_does_not_starve(args.fixture, directory)
        test_accessory_fixed(args.fixture, directory)
        print("PASS: native AX fixture (membership/focus/close/minimize/"
              "duplicate titles/native tabs/hung app/accessory fixed-size float)")
    finally:
        subprocess.run(["pkill", "-x", "AXFixture"], capture_output=True)
        shutil.rmtree(directory, ignore_errors=True)


if __name__ == "__main__":
    try:
        main()
    except AssertionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
