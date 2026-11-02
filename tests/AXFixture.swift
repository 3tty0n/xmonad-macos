// A controllable AppKit app for native AX integration tests.
//
// This is deliberately a test fixture, not part of the installed helper. It
// creates ordinary windows, fixed-size windows, duplicate titles, delayed
// minimize behavior and an intentionally unresponsive main thread. Commands
// arrive on stdin; the current window state is written to --state as JSON so a
// test driver can compare actual AppKit geometry with the helper's snapshot
// without needing its own Accessibility permission.
import AppKit
import Foundation

struct FixtureRect: Codable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double
}

struct FixtureWindowState: Codable {
  var id: Int
  var title: String
  var frame: FixtureRect
  // AppKit reports a bottom-left origin; the helper and AX report top-left.
  var topLeftFrame: FixtureRect
  var minimized: Bool
  var visible: Bool
  var key: Bool
  var fixed: Bool
}

struct FixtureState: Codable {
  var pid: Int32
  var accessory: Bool
  var hung: Bool
  var updated: Double
  var windows: [FixtureWindowState]
}

final class FixtureApp: NSObject, NSApplicationDelegate {
  private let statePath: String
  private let titlePrefix: String
  private let duplicateTitles: Bool
  private let accessory: Bool
  private let fixed: Bool
  private let initialWindows: Int
  private let minSize: NSSize?
  private let maxSize: NSSize?
  private var windows: [Int: NSWindow] = [:]
  private var nextID = 1
  private var hung = false
  private var stateTimer: Timer?
  private let controlQueue = DispatchQueue(label: "org.xmonad.AXFixture.control")
  private var controlBuffer = Data()

  init(statePath: String, titlePrefix: String, duplicateTitles: Bool,
       accessory: Bool, fixed: Bool, initialWindows: Int,
       minSize: NSSize?, maxSize: NSSize?) {
    self.statePath = statePath
    self.titlePrefix = titlePrefix
    self.duplicateTitles = duplicateTitles
    self.accessory = accessory
    self.fixed = fixed
    self.initialWindows = initialWindows
    self.minSize = minSize
    self.maxSize = maxSize
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(accessory ? .accessory : .regular)
    for _ in 0..<initialWindows { _ = makeWindow(fixed: fixed) }
    if let first = windows.keys.sorted().first { focusWindow(first) }
    NSApp.activate(ignoringOtherApps: true)
    stateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
      [weak self] _ in self?.writeState()
    }
    startReadingCommands()
    writeState()
  }

  private func parseSize(_ value: String) -> NSSize? {
    let parts = value.lowercased().split(separator: "x")
    guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]),
      w >= 40, h >= 40
    else { return nil }
    return NSSize(width: w, height: h)
  }

  private func makeWindow(fixed: Bool) -> Int {
    let id = nextID
    nextID += 1
    let size = fixed ? NSSize(width: 420, height: 260) : NSSize(width: 640, height: 420)
    let offset = CGFloat((id - 1) % 6) * 36
    let frame = NSRect(
      x: 90 + offset, y: 90 + offset, width: size.width, height: size.height)
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = duplicateTitles ? "\(titlePrefix) duplicate" : "\(titlePrefix) \(id)"
    window.identifier = NSUserInterfaceItemIdentifier("fixture-\(id)")
    if fixed {
      window.minSize = size
      window.maxSize = size
    } else {
      if let minSize = minSize {
        window.minSize = minSize
        window.maxSize = NSSize(
          width: max(maxSize?.width ?? 100_000, minSize.width),
          height: max(maxSize?.height ?? 100_000, minSize.height))
      }
      if let maxSize = maxSize {
        window.maxSize = maxSize
      }
    }
    let label = NSTextField(labelWithString: "AXFixture \(id)")
    label.alignment = .center
    label.frame = NSRect(x: 0, y: 0, width: size.width, height: 24)
    label.autoresizingMask = [.width, .minYMargin]
    window.contentView?.addSubview(label)
    windows[id] = window
    window.makeKeyAndOrderFront(nil)
    writeState()
    return id
  }

  private func focusWindow(_ id: Int) {
    guard let window = windows[id] else { return }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private func addTab(to id: Int) {
    guard let parent = windows[id] else { return }
    let childID = makeWindow(fixed: false)
    guard let child = windows[childID] else { return }
    child.tabbingMode = .preferred
    parent.addTabbedWindow(child, ordered: .above)
    parent.makeKeyAndOrderFront(nil)
    writeState()
  }

  private func closeWindow(_ id: Int) {
    guard let window = windows.removeValue(forKey: id) else { return }
    window.orderOut(nil)
    window.close()
    writeState()
  }

  private func minimizeWindow(_ id: Int) {
    windows[id]?.miniaturize(nil)
    writeState()
  }

  private func unminimizeWindow(_ id: Int) {
    windows[id]?.deminiaturize(nil)
    writeState()
  }

  private func delayedMinimize(_ id: Int, after milliseconds: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(0, milliseconds))) {
      [weak self] in self?.minimizeWindow(id)
    }
  }

  private func moveWindow(_ id: Int, _ parts: [Substring]) {
    guard parts.count == 4, let x = Double(parts[0]), let y = Double(parts[1]),
      let w = Double(parts[2]), let h = Double(parts[3]), let window = windows[id]
    else { return }
    window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    writeState()
  }

  private func hang(_ milliseconds: Int) {
    hung = true
    writeState()
    Thread.sleep(forTimeInterval: Double(max(0, milliseconds)) / 1000)
    hung = false
    writeState()
  }

  private func writeState() {
    guard let primary = NSScreen.screens.first else { return }
    let primaryHeight = primary.frame.height
    let states = windows.keys.sorted().compactMap { id -> FixtureWindowState? in
      guard let window = windows[id] else { return nil }
      let f = window.frame
      let topLeft = FixtureRect(
        x: Double(f.origin.x),
        y: Double(primaryHeight - (f.origin.y + f.height)),
        width: Double(f.width), height: Double(f.height))
      return FixtureWindowState(
        id: id,
        title: window.title,
        frame: FixtureRect(
          x: Double(f.origin.x), y: Double(f.origin.y),
          width: Double(f.width), height: Double(f.height)),
        topLeftFrame: topLeft,
        minimized: window.isMiniaturized,
        visible: window.isVisible,
        key: window.isKeyWindow,
        fixed: window.minSize == window.maxSize)
    }
    let state = FixtureState(
      pid: ProcessInfo.processInfo.processIdentifier,
      accessory: accessory, hung: hung,
      updated: Date().timeIntervalSince1970, windows: states)
    do {
      let data = try JSONEncoder().encode(state)
      let url = URL(fileURLWithPath: statePath)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch {
      FileHandle.standardError.write(Data("AXFixture state: \(error)\n".utf8))
    }
  }

  private func startReadingCommands() {
    let handle = FileHandle.standardInput
    handle.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard let self = self, !data.isEmpty else { return }
      self.controlQueue.async {
        self.controlBuffer.append(data)
        while let nl = self.controlBuffer.firstIndex(of: 10) {
          let line = self.controlBuffer.prefix(upTo: nl)
          self.controlBuffer.removeSubrange(self.controlBuffer.startIndex...nl)
          guard let text = String(data: line, encoding: .utf8) else { continue }
          DispatchQueue.main.async { self.handleCommand(text) }
        }
      }
    }
  }

  private func handleCommand(_ line: String) {
    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
    guard let command = parts.first else { return }
    switch command {
    case "new":
      _ = makeWindow(fixed: parts.dropFirst().first == "fixed")
    case "new-fixed":
      _ = makeWindow(fixed: true)
    case "tab":
      if let id = parts.dropFirst().first.flatMap({ Int($0) }) { addTab(to: id) }
    case "close":
      if let id = parts.dropFirst().first.flatMap({ Int($0) }) { closeWindow(id) }
    case "minimize":
      if let id = parts.dropFirst().first.flatMap({ Int($0) }) { minimizeWindow(id) }
    case "delay-minimize":
      let rest = Array(parts.dropFirst())
      if rest.count >= 2, let id = Int(rest[0]), let ms = Int(rest[1]) {
        delayedMinimize(id, after: ms)
      }
    case "unminimize":
      if let id = parts.dropFirst().first.flatMap({ Int($0) }) { unminimizeWindow(id) }
    case "focus":
      if let id = parts.dropFirst().first.flatMap({ Int($0) }) { focusWindow(id) }
    case "move":
      let rest = Array(parts.dropFirst())
      if let id = rest.first.flatMap({ Int($0) }) { moveWindow(id, Array(rest.dropFirst())) }
    case "hang":
      let ms = parts.dropFirst().first.flatMap({ Int($0) }) ?? 2000
      hang(ms)
    case "state":
      writeState()
    case "quit":
      writeState()
      NSApp.terminate(nil)
    default:
      FileHandle.standardError.write(Data("AXFixture: unknown command \(line)\n".utf8))
    }
  }
}

// Command line: --state PATH [--windows N] [--title-prefix T] [--fixed]
// [--duplicate-titles] [--accessory] [--min-size WxH] [--max-size WxH]
func argument(_ name: String, _ fallback: String? = nil) -> String? {
  let args = CommandLine.arguments
  guard let i = args.firstIndex(of: name), i + 1 < args.count else { return fallback }
  return args[i + 1]
}

let statePath = argument("--state") ?? "/tmp/ax-fixture-state.json"
let titlePrefix = argument("--title-prefix") ?? "AXFixture"
let windowCount = Int(argument("--windows") ?? "3") ?? 3
let delegate = FixtureApp(
  statePath: statePath,
  titlePrefix: titlePrefix,
  duplicateTitles: CommandLine.arguments.contains("--duplicate-titles"),
  accessory: CommandLine.arguments.contains("--accessory"),
  fixed: CommandLine.arguments.contains("--fixed"),
  initialWindows: max(0, windowCount),
  minSize: argument("--min-size").flatMap { value -> NSSize? in
    let p = value.lowercased().split(separator: "x")
    guard p.count == 2, let w = Double(p[0]), let h = Double(p[1]) else { return nil }
    return NSSize(width: w, height: h)
  },
  maxSize: argument("--max-size").flatMap { value -> NSSize? in
    let p = value.lowercased().split(separator: "x")
    guard p.count == 2, let w = Double(p[0]), let h = Double(p[1]) else { return nil }
    return NSSize(width: w, height: h)
  })
let app = NSApplication.shared
app.delegate = delegate
app.run()
