import AppKit
import Foundation

@main struct WireTests {
  static var count = 0
  static func check(_ b: @autoclosure () -> Bool, _ name: String) {
    guard b() else { fatalError("FAIL: \(name)") }
    count += 1
  }
  static func rejects(_ plan: Plan, _ name: String) {
    do {
      try PlanSafety.validate(plan, active: [1, 2, 3])
      fatalError("FAIL: \(name)")
    } catch { count += 1 }
  }
  static func stackChecks() {
    func window(_ wid: UInt64, _ pid: Int32, _ frame: Rect) -> WindowInfo {
      WindowInfo(
        wid: wid, pid: pid, app: "a", bundle: "b", titleText: "t", onDisplay: 1,
        frame: frame, minimized: false, ownedHidden: false)
    }
    // Circle on a 1000x1000 screen: a centred master and two satellites, one
    // of another app; a panel nothing manages sits between them.
    let master = Rect(x: 150, y: 150, width: 700, height: 700)
    let east = Rect(x: 600, y: 300, width: 400, height: 400)
    let west = Rect(x: 0, y: 300, width: 400, height: 400)
    let panel = Rect(x: 500, y: 500, width: 100, height: 100)
    let windows = [window(1, 10, master), window(2, 10, east), window(3, 20, west)]
    let cg: [(Int32, Rect)] = [
      (20, west), (30, panel), (10, Rect(x: 152, y: 151, width: 700, height: 700)), (10, east),
    ]
    let stack = observedStack(cg, windows: windows)
    check(stack.map(\.wid) == [3, nil, 1, 2], "stack matches windows by PID and frame")
    let painted: [UInt64: Rect] = [1: master, 2: east, 3: west]
    check(occluders(of: 3, in: stack, painted: painted) == [], "the top window is not covered")
    check(
      occluders(of: 2, in: stack, painted: painted) == [west, panel, master],
      "the bottom window is covered by everything in front of it")
    check(occluders(of: 9, in: stack, painted: painted) == nil, "an unobserved window has no depth")
    let moved = Rect(x: 0, y: 0, width: 300, height: 300)
    check(
      occluders(of: 1, in: stack, painted: [1: master, 3: moved]) == [moved, panel],
      "a managed window covers where it is painted now")
    check(
      occluders(of: 1, in: stack, painted: [1: master]) == [panel],
      "a managed window that is not painted covers nothing")
    let fpids: [UInt64: Int32] = [1: 10, 2: 10, 3: 20, 4: 10, 5: 10]
    check(
      floatsToRaise(after: 1, floating: [3, 5, 4], pids: fpids) == [5, 4],
      "only same-app floats are raised, in plan order")
    check(
      floatsToRaise(after: 4, floating: [5, 4], pids: fpids).isEmpty,
      "a focused float raises nothing")
    check(
      floatsToRaise(after: 9, floating: [5], pids: fpids).isEmpty,
      "an unknown window raises nothing")
    let fr = Rect(x: 0, y: 0, width: 100, height: 100)
    let far = Rect(x: 500, y: 500, width: 10, height: 10)
    let fstack = [
      StackEntry(wid: 5, frame: fr), StackEntry(wid: 1, frame: fr),
      StackEntry(wid: 4, frame: fr), StackEntry(wid: 2, frame: far),
    ]
    check(
      floatsCovered(by: 1, floating: [5, 4, 2], pids: fpids, stack: fstack) == [4],
      "only a float below and overlapping the tile is covered")
    check(
      floatsCovered(by: 4, floating: [5, 1], pids: fpids, stack: fstack).isEmpty,
      "nothing to raise when the floats are already in front")
    check(
      floatsCovered(by: 7, floating: [5], pids: fpids, stack: fstack).isEmpty,
      "an unobserved window has no covered floats")
    // An NS-port window sits a titlebar off its AX frame; another window of
    // the same app matches exactly further back and must keep its match.
    let emacs = Rect(x: 0, y: 0, width: 500, height: 500)
    let other = Rect(x: 0, y: 28, width: 500, height: 472)
    let loose = observedStack(
      [(40, Rect(x: 0, y: 28, width: 500, height: 472)), (40, emacs)],
      windows: [window(5, 40, emacs), window(6, 40, other)])
    check(loose.map(\.wid) == [6, 5], "exact matches are claimed before loose ones")
    let titlebar = observedStack(
      [(40, Rect(x: 0, y: 40, width: 500, height: 460))], windows: [window(5, 40, emacs)])
    check(titlebar.map(\.wid) == [5], "a titlebar-offset frame still matches")
    let twins = observedStack(
      [(40, Rect(x: 0, y: 40, width: 500, height: 460))],
      windows: [window(5, 40, emacs), window(6, 40, Rect(x: 0, y: 0, width: 500, height: 510))])
    check(twins.map(\.wid) == [nil], "an ambiguous loose match stays unmanaged")
    // Overlay geometry: the bottom satellite's frame loses both covered parts.
    let top: CGFloat = 1000
    let overlay = BorderOverlay.appKitFrame(east, inset: 2, top: top)
    let holes = BorderOverlay.holes(
      in: overlay,
      cutting: [west, panel, master].map { BorderOverlay.appKitFrame($0, inset: 0, top: top) })
    check(holes.count == 2, "only overlapping windows cut holes")
    check(
      holes.last == NSRect(x: 0, y: 0, width: 253, height: 404),
      "the master's hole is in overlay coordinates")
    check(
      BorderOverlay.outset(east, by: 2) == Rect(x: 598, y: 298, width: 404, height: 404),
      "a covering window's own border is clipped out too")
  }
  static func bundledInstallChecks() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("xmonad-install-\(getpid())")
    defer { try? fm.removeItem(at: root) }
    let app = root.appendingPathComponent("XMonadMac.app")
    let kit = app.appendingPathComponent("Contents/Resources/build-kit")
    let helpers = app.appendingPathComponent("Contents/Helpers")
    try fm.createDirectory(
      at: kit.appendingPathComponent("example"), withIntermediateDirectories: true)
    try fm.createDirectory(at: helpers, withIntermediateDirectories: true)
    try "cabal".write(
      to: kit.appendingPathComponent("xmonad-macos.cabal"), atomically: true, encoding: .utf8)
    try "main".write(
      to: kit.appendingPathComponent("example/xmonad.hs"), atomically: true, encoding: .utf8)
    try "lib".write(
      to: helpers.appendingPathComponent("libgmp.10.dylib"), atomically: true, encoding: .utf8)
    let bundled = helpers.appendingPathComponent("xmonad-engine")
    try "v1".write(to: bundled, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundled.path)
    let home = root.appendingPathComponent("home")
    let support = home.appendingPathComponent("support")
    var install = BundledInstall(bundle: app, support: support, home: home, stamp: "1")
    check((try? install.run()) == .installed, "first launch installs the bundle")
    check((try? install.run()) == .current, "same bundle installs once")
    check(
      (try? String(contentsOf: install.engine, encoding: .utf8)) == "v1", "bundled engine installed"
    )
    check(
      fm.fileExists(atPath: support.appendingPathComponent("libgmp.10.dylib").path),
      "engine libraries installed beside it")
    check(
      (try? String(
        contentsOf: home.appendingPathComponent(".config/xmonad-mac/xmonad.hs"),
        encoding: .utf8)) == "main", "default config written")
    check(
      (try? fm.destinationOfSymbolicLink(
        atPath: home.appendingPathComponent(".local/bin/xmonad").path))
        == install.engine.path, "xmonad links to the engine")
    let cache = support.appendingPathComponent("build-kit/dist-newstyle")
    try fm.createDirectory(at: cache, withIntermediateDirectories: true)
    try "mine".write(to: install.engine, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: install.engine.path)
    install = BundledInstall(bundle: app, support: support, home: home, stamp: "2")
    check((try? install.run()) == .upgraded, "a newer bundle upgrades")
    check(
      (try? String(contentsOf: install.engine, encoding: .utf8)) == "mine",
      "an upgrade leaves the user's engine for the recompile")
    check(fm.fileExists(atPath: cache.path), "an upgrade keeps the kit's build cache")
  }
  static func recoveryJournalChecks() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("xmonad-journal-\(getpid())")
    defer { try? fm.removeItem(at: root) }
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("recovery.json")
    let entry = RecoveryEntry(
      token: "token-1", pid: 42, launch: 1_700_000_000, bundle: "com.example.app",
      identifier: "id", title: "secret title",
      frame: Rect(x: 1, y: 2, width: 300, height: 200))
    let missing = RecoveryJournal(url)
    check(missing.entries.isEmpty && !missing.needsAttention,
          "a missing journal starts empty without needing attention")
    try missing.add(entry)
    let loaded = RecoveryJournal(url)
    check(loaded.entries == [entry] && loaded.formatVersion == RecoveryJournal.currentVersion,
          "a versioned journal round trips")
    let mode = try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
    check(mode?.intValue == 0o600, "the journal is owner-readable only")
    let encoded = try JSONEncoder().encode(loaded.report())
    let reportText = String(data: encoded, encoding: .utf8) ?? ""
    check(!reportText.contains("secret title"),
          "the recovery report does not expose window titles")
    try loaded.remove(entry.token)
    check(loaded.entries.isEmpty, "removing the last entry empties the journal")
    check(RecoveryJournal(url).entries.isEmpty, "the empty journal persists")

    let legacyURL = root.appendingPathComponent("legacy.json")
    try JSONEncoder().encode([entry]).write(to: legacyURL)
    let migrated = RecoveryJournal(legacyURL)
    check(migrated.entries == [entry] && migrated.formatVersion == 1,
          "a legacy array journal is migrated")
    check(migrated.loadWarning != nil, "legacy migration is reported")
    check((try? JSONDecoder().decode(
      RecoveryEnvelope.self, from: Data(contentsOf: legacyURL)))?.version == 1,
      "the migrated file uses the versioned envelope")

    let corruptURL = root.appendingPathComponent("corrupt.json")
    let corruptBytes = Data("{not json".utf8)
    try corruptBytes.write(to: corruptURL)
    let corrupt = RecoveryJournal(corruptURL)
    check(corrupt.needsAttention && corrupt.entries.isEmpty,
          "a corrupt journal needs attention instead of being decoded")
    check(corrupt.quarantineURL.map { fm.fileExists(atPath: $0.path) } == true,
          "a corrupt journal is preserved in quarantine")
    check(corrupt.quarantineURL.flatMap { try? Data(contentsOf: $0) } == corruptBytes,
          "the quarantined bytes are unchanged")
    let quarantinesBefore = try fm.contentsOfDirectory(atPath: root.path)
      .filter { $0.hasPrefix("corrupt.corrupt-") }
    let reportOnly = RecoveryJournal(corruptURL, quarantine: false)
    check(reportOnly.needsAttention && reportOnly.quarantineURL != nil,
          "a read-only report still describes the corrupt journal")
    let quarantinesAfter = try fm.contentsOfDirectory(atPath: root.path)
      .filter { $0.hasPrefix("corrupt.corrupt-") }
    check(quarantinesBefore == quarantinesAfter,
          "a read-only report does not create another quarantine copy")
    do {
      try corrupt.add(entry)
      fatalError("a corrupt journal accepted a mutation")
    } catch { count += 1 }

    let futureURL = root.appendingPathComponent("future.json")
    try JSONEncoder().encode(
      RecoveryEnvelope(version: 99, entries: [entry])).write(to: futureURL)
    let future = RecoveryJournal(futureURL)
    check(future.needsAttention && future.formatVersion == 99,
          "an unknown journal version is refused, not guessed")
    check(fm.fileExists(atPath: futureURL.path),
          "an unknown journal version keeps the original file")
  }
  static func main() throws {
    visibilityChecks()
    appScanBackoffChecks()
    scanReadinessChecks()
    writeBackoffChecks()
    try recoveryJournalChecks()
    let primary = Rect(x: 0, y: 0, width: 1512, height: 982)
    check(Rect.quartz(appKit: primary, primaryTop: 982) == primary, "primary origin")
    check(
      Rect.quartz(appKit: Rect(x: -1920, y: 0, width: 1920, height: 1080), primaryTop: 982)
        == Rect(x: -1920, y: -98, width: 1920, height: 1080), "negative X and offset Y")
    check(
      Rect.quartz(appKit: Rect(x: 0, y: 982, width: 2560, height: 1440), primaryTop: 982).y
        == -1440,
      "display above primary uses negative Quartz Y")
    check(
      Rect.quartz(appKit: Rect(x: 0, y: -1080, width: 1920, height: 1080), primaryTop: 982).y
        == 982,
      "display below primary")
    let usable = Rect.quartz(appKit: Rect(x: 0, y: 70, width: 1512, height: 875), primaryTop: 982)
    check(
      usable == Rect(x: 0, y: 37, width: 1512, height: 875), "Dock and menu bar reserved in points")
    // WindowServer handed these back after a display wake; Int(_:) traps on
    // them, so a bad rectangle must be refused rather than converted.
    check(
      Rect(CGRect(x: -1920, y: -98, width: 1920, height: 1080))
        == Rect(x: -1920, y: -98, width: 1920, height: 1080),
      "on-screen CG rectangle")
    check(Rect(CGRect(x: Double.nan, y: 0, width: 100, height: 50)) == nil, "NaN origin refused")
    check(
      Rect(CGRect(x: 0, y: 0, width: Double.infinity, height: 50)) == nil, "infinite size refused")
    check(Rect(CGRect(x: 1e30, y: 0, width: 100, height: 50)) == nil, "origin past Int refused")
    check(Rect(CGRect(x: 0, y: 0, width: 0, height: 50)) == nil, "empty rectangle refused")
    // A park has to overlap the screen, or AppKit drags 40x32 of the
    // window's title bar back on it.
    check(
      parkOrigin(
        screens: [Rect(x: 0, y: 0, width: 3360, height: 1890)],
        window: Rect(x: 5, y: 35, width: 1670, height: 1850))
        == Rect(x: 3359, y: 1889, width: 1670, height: 1850), "park inside the bottom-right corner")
    check(
      parkOrigin(
        screens: [
          Rect(x: 0, y: 0, width: 1920, height: 1080),
          Rect(x: 1920, y: 0, width: 2560, height: 1440),
        ],
        window: Rect(x: 0, y: 0, width: 800, height: 600))
        == Rect(x: 4479, y: 1439, width: 800, height: 600), "park past the widest display")
    check(
      parkedOffDisplay(
        Rect(x: 3359, y: 1889, width: 1670, height: 1850),
        [DisplayInfo(display: 1, usable: Rect(x: 0, y: 30, width: 3360, height: 1860))]),
      "a parked window is off the workspace")
    let ds = [
      DisplayInfo(display: 1, usable: primary),
      DisplayInfo(display: 2, usable: Rect(x: -1920, y: 0, width: 1920, height: 1080)),
    ]
    check(
      bestDisplay(for: Rect(x: -1600, y: 100, width: 900, height: 700), in: ds) == 2, "left screen")
    check(
      bestDisplay(for: Rect(x: 100, y: 100, width: 900, height: 700), in: ds) == 1, "primary screen"
    )
    let json = """
      {"type":"plan","generation":7,"epoch":2,
       "frames":[{"wid":1,"frame":{"x":0,"y":24,"width":800,"height":900}}],
       "hide":[2],"focus":1,"action":7,"focusForMs":400,"workspace":"日本語","layout":"Tall",
       "checkpoint":{"savedVersion":1,"value":[null,true,2.5,"x"]}}
      """
    let message = try JSONDecoder().decode(EngineMessage.self, from: Data(json.utf8))
    guard case .plan(var plan) = message else { fatalError("decode plan") }
    try PlanSafety.validate(plan, active: [1, 2, 3])
    count += 1
    check(plan.workspace == "日本語", "UTF-8 protocol")
    check(plan.action == 7 && plan.focusForMs == 400, "action sequencing fields")
    check(plan.borders == nil, "a plan without borders still decodes")
    check(plan.status == nil, "a plan without a PP status still decodes")
    let moved = Rect(x: 640, y: 400, width: 500, height: 400)
    let displayed = [
      WindowInfo(
        wid: 1, pid: 1, app: "Settings", bundle: "com.apple.systempreferences",
        titleText: "Settings", onDisplay: 1, frame: Rect(x: 0, y: 24, width: 400, height: 400),
        minimized: false, ownedHidden: false),
      WindowInfo(
        wid: 2, pid: 1, app: "Terminal", bundle: "com.apple.Terminal",
        titleText: "shell", onDisplay: 1, frame: Rect(x: 0, y: 24, width: 800, height: 900),
        minimized: false, ownedHidden: false),
    ]
    let patched = patchingFrame(displayed, wid: 1, frame: moved)
    check(patched[0].frame == moved, "a dragged frame replaces the observation")
    check(patched[1].frame == displayed[1].frame, "other windows keep their frames")
    check(patched[0].wid == 1 && patched.count == displayed.count, "the set of windows is unchanged")
    let bjson = """
      {"type":"plan","generation":1,"epoch":1,
       "frames":[{"wid":1,"frame":{"x":0,"y":24,"width":800,"height":900}},
                 {"wid":3,"frame":{"x":0,"y":924,"width":800,"height":900}}],
       "hide":[],"focus":1,"workspace":"1","layout":"Tall","checkpoint":null,
       "borders":[{"wid":1,"width":0},{"wid":3,"width":4}]}
      """
    let bdata = Data(bjson.utf8)
    let msg = try JSONDecoder().decode(EngineMessage.self, from: bdata)
    guard case .plan(let named) = msg else { fatalError("decode borders") }
    check(named.borders?.count == 2, "per-window border widths decode")
    check(
      named.borders?.first?.wid == 1
        && named.borders?.first?.width == 0, "zero means no border at all")
    check(named.borders?.last?.width == 4, "the plan may narrow a border")
    try PlanSafety.validate(named, active: [1, 3])
    count += 1
    let ejson = """
      {"type":"plan","generation":1,"epoch":1,"frames":[],"hide":[],
       "workspace":"1","layout":"Tall","checkpoint":null,"borders":[],
       "status":"[1] : Tall"}
      """
    let edata = Data(ejson.utf8)
    let emsg = try JSONDecoder().decode(EngineMessage.self, from: edata)
    guard case .plan(let none) = emsg else { fatalError("empty borders") }
    check(none.borders?.isEmpty == true, "an empty border list is not nil")
    check(none.floating == nil, "a plan without floating decodes as nil")
    let fjson = """
      {"type":"plan","generation":1,"epoch":1,"frames":[],"hide":[],
       "workspace":"1","layout":"Tall","checkpoint":null,"floating":[4,2]}
      """
    guard case .plan(let fplan) = try JSONDecoder().decode(
      EngineMessage.self, from: Data(fjson.utf8))
    else { fatalError("decode floating") }
    check(fplan.floating == [4, 2], "the floating list decodes in order")
    check(none.status == "[1] : Tall", "a logHook's PP status decodes")
    let mjson = """
      {"type":"movePointer","bounds":{"x":200,"y":200,"width":1,"height":1},
       "focus":{"x":100,"y":100,"width":200,"height":200}}
      """
    let mmsg = try JSONDecoder().decode(EngineMessage.self, from: Data(mjson.utf8))
    guard case .movePointer(let mbounds, let mfocus) = mmsg else {
      fatalError("decode movePointer")
    }
    check(
      mbounds == Rect(x: 200, y: 200, width: 1, height: 1),
      "movePointer bounds decode")
    check(
      mfocus == Rect(x: 100, y: 100, width: 200, height: 200),
      "movePointer focus decode")
    for role in ["AXMenu", "AXMenuItem", "AXMenuBar", "AXMenuBarItem", "AXPopover", "AXSheet"] {
      check(pointerFocusIsTransientRole(role), "transient \(role) blocks hover focus")
    }
    for role in ["AXWindow", "AXButton", "AXTextField", "AXWebArea", ""] {
      check(!pointerFocusIsTransientRole(role), "ordinary \(role) is not a transient surface")
    }
    check(retainingWindowEligibility(previous: true, observed: nil),
          "failed AX eligibility read retains a managed window")
    check(!retainingWindowEligibility(previous: false, observed: nil),
          "failed AX eligibility read cannot admit a new window")
    check(!retainingWindowEligibility(previous: true, observed: false),
          "positive exclusion still removes eligibility")
    check(retainingWindowEligibility(previous: false, observed: true),
          "positive eligibility admits a window")
    var bad = plan
    bad.hide = [1]
    rejects(bad, "show/hide conflict")
    bad = plan
    bad.frames.append(bad.frames[0])
    rejects(bad, "duplicate frame")
    bad = plan
    bad.hide = [2, 2]
    rejects(bad, "duplicate hidden ID")
    bad = plan
    bad.focus = 3
    rejects(bad, "focus missing from frames")
    bad = plan
    bad.frames[0].frame.width = 0
    rejects(bad, "zero dimension")
    bad = plan
    bad.frames[0].frame.x = Int.max
    rejects(bad, "coordinate overflow")
    bad = plan
    bad.hide = [9]
    rejects(bad, "unknown window ID")
    bad = plan
    bad.borders = [BorderOverride(wid: 9, width: 1)]
    try PlanSafety.validate(bad, active: [1, 2, 3])
    count += 1
    bad = plan
    bad.borders = Array(repeating: BorderOverride(wid: 1, width: 0), count: 10_001)
    rejects(bad, "unreasonable border list")
    bad = plan
    bad.borders = [BorderOverride(wid: 1, width: -1)]
    rejects(bad, "negative border width")
    bad = plan
    bad.borders = [BorderOverride(wid: 1, width: 65)]
    rejects(bad, "border width above the cap")
    bad = plan
    bad.borders = [BorderOverride(wid: 1, width: 0)]
    try PlanSafety.validate(bad, active: [1, 2, 3])
    count += 1
    // Moving the last window off a smartBorders workspace empties it while
    // the layout still states that window's width, so the engine sends an
    // empty frame list with a border for a hidden window. That must plan.
    let emptied = """
      {"type":"plan","generation":9,"epoch":0,
       "frames":[],"hide":[1,2,3],"focus":null,"action":null,"focusForMs":400,
       "workspace":"2","layout":"ThreeColMid","screen":1,"checkpoint":null,
       "borders":[{"wid":1,"width":1}],"workspaces":[]}
      """
    let emptiedMessage = try JSONDecoder().decode(EngineMessage.self, from: Data(emptied.utf8))
    guard case .plan(let emptiedPlan) = emptiedMessage else {
      fatalError("decode emptied workspace")
    }
    try PlanSafety.validate(emptiedPlan, active: [1, 2, 3])
    count += 1
    bad = plan
    bad.frames[0].frame.height = -1
    rejects(bad, "negative dimension")
    plan.frames[0].frame.x = -1800
    try PlanSafety.validate(plan, active: [1, 2, 3])
    count += 1
    for key in [
      KeyBinding(mask: 68, sym: 106), KeyBinding(mask: 69, sym: 0xff0d),
      KeyBinding(mask: 0, sym: 0xffbe), KeyBinding(mask: 8, sym: 0x20),
    ] {
      try validateBinding(key)
      count += 1
    }
    for key in [
      KeyBinding(mask: 0, sym: 106), KeyBinding(mask: 16, sym: 106),
      KeyBinding(mask: 68, sym: 0x1008_ff11),
    ] {
      do {
        try validateBinding(key)
        fatalError("invalid key accepted")
      } catch { count += 1 }
    }
    check(keyCodeForSym[106] == 38, "J physical key")
    check(keyCodeForSym[0xffd1] == 90, "F20 mapping")
    check(
      symForKeyCode[38] == 106 && symForKeyCode[53] == 0xff1b, "grabbed keys map back to keysyms")
    check(keyCodeForSym.allSatisfy { symForKeyCode[$0.value] == $0.key }, "key codes are unique")
    let config = Data(
      ("{\"type\":\"configure\",\"protocol\":1,\"keys\":[{\"mask\":68,\"sym\":106}]"
        + ",\"mouseMask\":68,\"mouse\":[{\"mask\":68,\"button\":1,\"action\":\"move\"}"
        + ",{\"mask\":68,\"button\":3,\"action\":\"resize\"},{\"mask\":68,\"button\":2,\"action\":\"raise\"}]"
        + ",\"borderWidth\":2,\"borderColor\":\"#00ff00\",\"normalBorderColor\":\"#dddddd\""
        + ",\"focusFollowsMouse\":true}").utf8)
    if case .configure(let v, let keys, let mouse, let look) = try JSONDecoder().decode(
      EngineMessage.self, from: config)
    {
      check(v == 1 && keys.count == 1 && mouse.count == 3, "configure decoding")
      check(
        look.borderWidth == 2 && look.focusFollowsMouse && look.normalBorderColor == "#dddddd",
        "appearance decoding")
      check(
        mouse[0].action == .move && mouse[1].button == 3 && mouse[2].action == .raise,
        "mouse bindings")
      check(BorderOverlay.parse(look.borderColor)?.greenComponent == 1, "border colour")
      check(BorderOverlay.parse("nope") == nil, "bad border colour rejected")
    } else {
      fatalError("configuration")
    }
    let tiled = NSRect(x: 0, y: 0, width: 800, height: 900)
    let floated = NSRect(x: 200, y: 200, width: 400, height: 300)
    if let hole = BorderOverlay.hole(in: tiled, cutting: floated) {
      check(
        hole.origin.x == 199 && hole.origin.y == 199
          && hole.width == 402 && hole.height == 302, "focused float punches a hole")
    } else {
      check(false, "focused float must clip the tiled frame")
    }
    let edge = NSRect(x: 790, y: 0, width: 200, height: 50)
    if let hole = BorderOverlay.hole(in: tiled, cutting: edge) {
      check(hole.origin.x == 789 && hole.width == 11, "clip is the overlap only")
    } else {
      check(false, "overlapping edge must clip")
    }
    check(
      BorderOverlay.hole(in: tiled, cutting: NSRect(x: 900, y: 0, width: 10, height: 10)) == nil,
      "disjoint frames keep the unfocused border")
    stackChecks()
    try validateMouseBindings([MouseBind(mask: 68, button: 1, action: .move)])
    count += 1
    do {
      try validateMouseBindings([])
      fatalError("empty mouse bindings accepted")
    } catch { count += 1 }
    do {
      try validatePointerMask(128)
      fatalError("invalid pointer modifier accepted")
    } catch { count += 1 }
    do {
      try validatePointerMask(0)
      fatalError("unmodified pointer grab accepted")
    } catch { count += 1 }
    let value = try JSONDecoder().decode(
      JSONValue.self, from: Data("{\"a\":[true,false,null,1.5,\"日本語\"]}".utf8))
    _ = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    count += 1
    let wi = WindowInfo(
      wid: 42, pid: 123, app: "Terminal", bundle: "com.apple.Terminal",
      titleText: "α\nβ", onDisplay: 1, frame: primary, minimized: false, ownedHidden: false)
    let snap = Snapshot(
      generation: 8, epoch: 1, screens: ds, windows: [wi], focused: 42, restore: nil)
    let encoded = try JSONEncoder().encode(snap)
    let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    check(object["type"] as? String == "snapshot", "snapshot event type")
    let window = (object["windows"] as! [[String: Any]])[0]
    check(window["titleText"] as? String == "α\nβ", "title escaping")
    check(window["ownedHidden"] as? Bool == false, "ownership wire name")
    check(window["subrole"] as? String == "AXStandardWindow", "default subrole")
    check(window["accessory"] as? Bool == false, "default accessory flag")
    let accessoryInfo = WindowInfo(
      wid: 43, pid: 123, app: "Box", bundle: "com.box.desktop", titleText: "Search",
      onDisplay: 1, frame: primary, minimized: false, ownedHidden: false,
      accessory: true)
    let accessoryObject = try JSONSerialization.jsonObject(
      with: try JSONEncoder().encode(accessoryInfo)) as! [String: Any]
    check(accessoryObject["accessory"] as? Bool == true, "accessory flag round trips")
    check(
      isManagedPopupSubrole("AXDialog") && isManagedPopupSubrole("AXSystemDialog")
        && isManagedPopupSubrole("AXFloatingWindow")
        && isManagedPopupSubrole("AXSystemFloatingWindow"),
      "popup subroles")
    check(
      !isManagedPopupSubrole("AXStandardWindow") && !isManagedPopupSubrole("AXSheet")
        && !isManagedPopupSubrole("AXUnknown"), "sheets stay unmanaged")
    check(
      reportsAsWindowRole("AXWindow") && reportsAsWindowRole("AXTextField")
        && reportsAsWindowRole("AXTextArea"), "Emacs frames report as windows")
    check(
      !reportsAsWindowRole("AXSheet") && !reportsAsWindowRole("AXUnknown"),
      "sheets are not window roles")
    check(
      windowRoleIsEligible(
        role: "AXWindow", subrole: "AXStandardWindow", fullScreen: false,
        positionSettable: true, sizeSettable: true),
      "standard window tiles without AXMinimized")
    check(
      windowRoleIsEligible(
        role: "AXWindow", subrole: "", fullScreen: false,
        positionSettable: true, sizeSettable: true),
      "empty subrole is a standard window")
    check(
      windowRoleIsEligible(
        role: "AXTextField", subrole: "AXStandardWindow", fullScreen: false,
        positionSettable: true, sizeSettable: true),
      "NS Emacs AXTextField frames are eligible")
    check(
      !windowRoleIsEligible(
        role: "AXWindow", subrole: "AXSheet", fullScreen: false,
        positionSettable: true, sizeSettable: true),
      "sheets stay ineligible")
    check(
      !windowRoleIsEligible(
        role: "AXWindow", subrole: "AXUnknown", fullScreen: false,
        positionSettable: true, sizeSettable: true),
      "unknown subroles stay ineligible")
    check(
      !windowRoleIsEligible(
        role: "AXWindow", subrole: "AXStandardWindow", fullScreen: false,
        positionSettable: true, sizeSettable: false),
      "a fixed-size window is not tiled")
    check(
      windowRoleIsEligible(
        role: "AXWindow", subrole: "AXStandardWindow", fullScreen: false,
        positionSettable: true, sizeSettable: false, accessory: true),
      "a fixed-size accessory window is eligible to float")
    check(
      accessoryAppIsManaged(
        bundle: "com.box.desktop", hasOnScreenWindow: true, known: false),
      "a non-Apple accessory app with a window is managed")
    check(
      accessoryAppIsManaged(
        bundle: "com.box.desktop", hasOnScreenWindow: false, known: true),
      "a known accessory window survives the scan that no longer lists it")
    check(
      !accessoryAppIsManaged(
        bundle: "com.box.desktop", hasOnScreenWindow: false, known: false),
      "an idle accessory app is not scanned")
    check(
      !accessoryAppIsManaged(
        bundle: "com.apple.controlcenter", hasOnScreenWindow: true, known: true),
      "Apple accessory agents stay unmanaged")
    check(
      !accessoryAppIsManaged(bundle: "", hasOnScreenWindow: true, known: true),
      "a bundle-less accessory agent stays unmanaged")
    let axFrame = Rect(x: 0, y: 24, width: 800, height: 600)
    let cgFrame = Rect(x: 0, y: 0, width: 800, height: 624)
    check(cgMatchesAXFrame(axFrame, cgFrame), "titlebar offset still matches CG")
    check(
      !cgMatchesAXFrame(axFrame, Rect(x: 900, y: 0, width: 800, height: 624)),
      "a neighbour CG window is not this frame")
    check(
      cgWindowIsApplicationLayer(0) && cgWindowIsApplicationLayer(3)
        && cgWindowIsApplicationLayer(8) && cgWindowIsApplicationLayer(19), "application layers")
    check(
      !cgWindowIsApplicationLayer(-1) && !cgWindowIsApplicationLayer(20)
        && !cgWindowIsApplicationLayer(24), "dock and menu layers excluded")
    check(
      bundleOmitsOnScreenCGWindows("com.google.Chrome")
        && bundleOmitsOnScreenCGWindows("com.google.Chrome.beta")
        && bundleOmitsOnScreenCGWindows("com.google.Chrome.canary"),
      "Chrome withholds on-screen CGWindow metadata")
    check(
      !bundleOmitsOnScreenCGWindows("com.apple.Safari")
        && !bundleOmitsOnScreenCGWindows("com.mitchellh.ghostty"),
      "AppKit apps still require CGWindow correlation")
    let screen = [DisplayInfo(display: 1, usable: Rect(x: 0, y: 0, width: 1800, height: 1169))]
    let parked = Rect(x: 1864, y: 1233, width: 782, height: 1120)
    let finder = Rect(x: 1013, y: 44, width: 782, height: 1120)
    check(
      parkedOffDisplay(parked, screen) && !parkedOffDisplay(finder, screen),
      "corner clamp is parked")
    check(
      cgShowsOriginal(pid: 1, original: finder, windows: [(1, finder)], displays: screen),
      "CG still at the original on-display frame")
    check(
      !cgShowsOriginal(pid: 1, original: finder, windows: [(1, parked)], displays: screen),
      "CG at the parking clamp is not the original")
    check(parksByMinimizing("com.apple.finder"), "Finder hides by minimizing")
    check(
      !parksByMinimizing("com.apple.Safari") && !parksByMinimizing("com.google.Chrome"),
      "other apps still park first")
    check(tracesFocusBorder(wi, displays: screen), "visible window is traced")
    var restoring = wi
    restoring.ownedHidden = true
    check(!tracesFocusBorder(restoring, displays: screen), "owned hide is not traced as focus")
    check(
      tracesFocusBorder(restoring, displays: screen, pinned: true),
      "pinned restore still traces an on-screen window")
    restoring.frame = parked
    check(
      !tracesFocusBorder(restoring, displays: screen, pinned: true), "parked window is not traced")
    var mini = wi
    mini.minimized = true
    check(!tracesFocusBorder(mini, displays: screen), "minimized window is not traced")
    // Finder has no NSRunningApplication launch date, and a hide without a
    // process instance is refused. Every live process has a start time.
    let started = processStartTime(getpid())
    check(started > 0 && started <= Date().timeIntervalSince1970, "process start time is readable")
    check(processStartTime(getpid()) == started, "process start time is stable")
    check(processStartTime(-1) == 0, "no start time for a process that cannot exist")
    check(resizeFloor(nil) == (80, 60) && resizeFloor((24, 24)) == (24, 24), "resize floor")
    let oldp = WindowPrint(
      wid: 1, pid: 9, launch: 1, bundle: "b", identifier: "id", title: "t", frame: primary)
    let newp = WindowPrint(
      wid: 99, pid: 9, launch: 1, bundle: "b", identifier: "id", title: "t", frame: primary)
    check(
      matchWindowPrints(old: [oldp], new: [newp])[1] == 99, "fingerprint remaps a unique identifier"
    )
    let titled = WindowPrint(
      wid: 2, pid: 8, launch: 1, bundle: "b", identifier: "", title: "same", frame: primary)
    let titledNew = WindowPrint(
      wid: 50, pid: 8, launch: 1, bundle: "b", identifier: "", title: "same", frame: primary)
    check(
      matchWindowPrints(old: [titled], new: [titledNew])[2] == 50,
      "fingerprint remaps unique title and frame")
    var ck = JSONValue.object([
      "savedVersion": .number(1), "savedEpoch": .number(7),
      "savedWindows": .array([.number(1)]), "savedFocus": .number(1),
      "savedFloats": .array([
        .array([.number(1), .number(0), .number(0), .number(0.5), .number(0.5)])
      ]),
    ])
    ck = remapCheckpoint(ck, map: [1: 99], epoch: 3)
    if case .object(let o) = ck, case .number(let ep) = o["savedEpoch"],
      case .array(let wins) = o["savedWindows"], case .number(let w) = wins.first,
      case .number(let f) = o["savedFocus"]
    {
      check(ep == 3 && w == 99 && f == 99, "checkpoint wids, focus and epoch rewrite")
    } else {
      check(false, "checkpoint rewrite shape")
    }
    let orphaned = remapCheckpoint(
      JSONValue.object(["savedFocus": .number(7)]), map: [:], epoch: 1)
    if case .object(let o) = orphaned, let f = o["savedFocus"], case .null = f {
      check(true, "a checkpoint focus no fingerprint matched is dropped, not left stale")
    } else {
      check(false, "unmatched checkpoint focus is dropped")
    }
    // Geometry stress: round trips hold for logical-coordinate rectangles.
    for x in stride(from: -6000, through: 6000, by: 1200) {
      for y in stride(from: -3000, through: 3000, by: 600) {
        let r = Rect(x: x, y: y, width: 1920, height: 1080)
        check(
          Rect.quartz(appKit: Rect.quartz(appKit: r, primaryTop: 982), primaryTop: 982) == r,
          "coordinate involution")
      }
    }
    try bundledInstallChecks()
    print("PASS: \(count) portable Swift checks")
  }
  static func visibilityChecks() {
    check(cgOnScreenEvidence(querySucceeded: false, visible: 0, peers: 1,
      omitsMetadata: false) == nil, "failed CG query remains unknown")
    check(cgOnScreenEvidence(querySucceeded: true, visible: 0, peers: 1,
      omitsMetadata: false) == false, "valid empty CG query is negative evidence")
    check(cgOnScreenEvidence(querySucceeded: false, visible: 0, peers: 1,
      omitsMetadata: true) == nil, "Chrome exception does not mask failed query")
    check(cgOnScreenEvidence(querySucceeded: true, visible: 1, peers: 2,
      omitsMetadata: false) == false, "same-frame peers remain ambiguous")
    check(cgOnScreenEvidence(querySucceeded: true, visible: 0, peers: 2,
      omitsMetadata: true) == false, "metadata exception cannot admit same-frame peers")
    var screen = VisibilityGrace()
    var hidden = VisibilityGrace()
    hidden.observe(true, at: 0)
    func decide(_ now: Double, known: Bool = true, owned: Bool = false,
                minimized: Bool = false, isHidden: Bool? = false,
                visible: Bool? = false, ready: Bool = true,
                ambiguous: Bool = false, unresponsive: Bool = false) -> VisibilityDecision {
      windowVisibilityDecision(known: known, owned: owned, orphaned: false,
        minimized: minimized, hidden: isHidden, onScreen: visible, readsReady: ready,
        hiddenGrace: hidden, screenGrace: screen, now: now, ambiguous: ambiguous,
        unresponsive: unresponsive)
    }
    for i in 0...12 {
      let now = Double(i) * 0.08
      screen.observe(false, at: now)
      check(decide(now).retained, "rapid negative scans retain policy state")
      check(!decide(now).actionable, "negative grace never authorizes mutations")
    }
    screen.observe(false, at: 1.6)
    check(!decide(1.6).retained, "sustained mismatch excludes after elapsed grace")
    screen.observe(true, at: 1.7)
    check(decide(1.7, visible: true).actionable, "positive visibility resets grace")
    screen.observe(false, at: 1.8)
    screen.observe(false, at: 1.9)
    let elapsed = screen.negativeSeconds
    let reads = screen.negativeReads
    screen.observe(nil, at: 2.5)
    check(screen.negativeReads == reads && screen.negativeSeconds == elapsed,
      "failed query does not advance negative counters")
    check(decide(2.5, visible: nil).retained && !decide(2.5, visible: nil).actionable,
      "failed CG query retains known policy without mutations")
    check(!decide(2.5, known: false, visible: nil).retained,
      "failed CG query cannot newly admit a window")
    check(!decide(2.5, known: false, owned: true, visible: nil).retained,
      "owned record still needs query evidence for first admission")
    screen.observe(false, at: 2.6)
    check(screen.negativeSeconds == elapsed, "negative read after failure excludes failed interval")
    screen.observe(nil, at: 3.9)
    check(!decide(3.9, visible: nil).retained, "persistent query failure has bounded retention")
    screen.observe(true, at: 4)
    hidden.observe(false, at: 4)
    hidden.observe(false, at: 4.08)
    check(decide(4.08, isHidden: true, visible: true).retained,
      "hidden flicker retains policy state")
    check(!decide(4.08, isHidden: true, visible: true).actionable,
      "hidden flicker suppresses mutation immediately")
    hidden.observe(true, at: 4.16)
    check(decide(4.16, visible: true).actionable, "application shown resets hidden grace")
    hidden.observe(false, at: 5)
    hidden.observe(false, at: 6.6)
    check(!decide(6.6, isHidden: true, visible: true).retained,
      "sustained hidden application excluded")
    hidden.observe(true, at: 7)
    check(!decide(7, minimized: true, visible: true).retained,
      "user minimized window excluded without grace")
    check(decide(7, owned: true, minimized: true, visible: false).retained,
      "WM owned minimization retains workspace")
    check(!decide(7, owned: true, visible: nil).actionable,
      "owned window cannot mutate on failed CG query")
    check(decide(7, ambiguous: true).retained && !decide(7, ambiguous: true).actionable,
      "known ambiguous window retained but never actionable")
    check(!decide(7, owned: true, ambiguous: true).actionable,
      "ownership does not override same-frame ambiguity")
    check(!decide(7, known: false, ambiguous: true).retained,
      "new ambiguous window never admitted")
    check(!decide(7, known: false, owned: true, ambiguous: true).retained,
      "owned new record does not override ambiguity admission gate")
    check(!decide(7, visible: true, ready: false).actionable,
      "failed critical AX reads suppress native mutations")
    check(decide(100, visible: true, ready: false).retained
      && !decide(100, visible: true, ready: false).actionable,
      "positive CG evidence retains known policy through prolonged AX failure only")
    check(!decide(100, known: false, visible: true, ready: false).retained,
      "positive CG evidence cannot admit a new window with unknown AX reads")
    check(!decide(100, known: false, isHidden: nil, visible: true).retained,
      "unknown application visibility cannot admit a new window")
    check(decide(100, owned: true, minimized: true, visible: false).actionable,
      "owned late minimize can retry restore without an on-screen CG match")
    check(!decide(100, owned: true, minimized: true, visible: false,
      ambiguous: true).actionable,
      "owned late minimize never overrides genuine peer ambiguity")
    screen.observe(false, at: 101)
    check(decide(101, visible: false, unresponsive: true).retained
      && !decide(101, visible: false, unresponsive: true).actionable,
      "an unresponsive app keeps known policy state but cannot mutate")
    check(!decide(101, known: false, visible: false, unresponsive: true).retained,
      "an unresponsive app cannot newly admit a window")
    check(!decide(101, isHidden: true, visible: true, unresponsive: true).retained,
      "a hidden app still leaves management while unresponsive")
    check(!decide(101, minimized: true, visible: true, unresponsive: true).retained,
      "a user-minimized window still leaves management while unresponsive")
    check(decide(101, owned: true, minimized: true, visible: false,
      unresponsive: true).retained
      && !decide(101, owned: true, minimized: true, visible: false,
        unresponsive: true).actionable,
      "an owned hide survives an unresponsive app without a retry")
    rapidVisibilityRecoveryChecks()
  }
  static func rapidVisibilityRecoveryChecks() {
    // Model only the engine's delete/re-admit boundary: retained snapshot IDs
    // preserve this policy order. This is not a Haskell StackSet integration test.
    let original: [UInt64] = [3, 1, 2]
    var policyOrder = original
    var active = Set(original)
    var grace = Dictionary(uniqueKeysWithValues: original.map { ($0, VisibilityGrace()) })
    var shown = VisibilityGrace()
    shown.observe(true, at: 0)
    let observations: [(Double, Bool, Int)] = [
      (0, true, 1), (0.08, false, 0), (0.16, true, 0),
      (0.24, true, 0), (0.32, false, 0), (0.40, true, 1),
    ]
    for (now, succeeded, visible) in observations {
      let evidence = cgOnScreenEvidence(querySucceeded: succeeded, visible: visible,
        peers: 1, omitsMetadata: false)
      var snapshot: [UInt64] = []
      for id in [UInt64(1), 2, 3] {
        grace[id]!.observe(evidence, at: now)
        let decision = windowVisibilityDecision(known: active.contains(id), owned: false,
          orphaned: false, minimized: false, hidden: false, onScreen: evidence,
          readsReady: true, hiddenGrace: shown, screenGrace: grace[id]!, now: now)
        if decision.retained { snapshot.append(id) }
        check(decision.actionable == (evidence == true),
          "rapid recovery actionability requires positive current evidence")
      }
      let next = Set(snapshot)
      policyOrder = policyOrder.filter { next.contains($0) }
        + snapshot.filter { !policyOrder.contains($0) }
      active = next
      check(policyOrder == original, "rapid failed/empty CG scans preserve policy order model")
      if now == 0.32 {
        check(grace[1]!.negativeReads == 2,
          "failed CG recovery scan does not become a third negative read")
      }
    }
    check(grace[1]!.negativeReads == 0 && grace[1]!.uncertainSince == nil,
      "positive recovery clears counters and deadline")
  }
  static func appScanBackoffChecks() {
    func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
    var backoff = AppScanBackoff()
    check(backoff.shouldScan(owned: false, now: at(0)),
          "a healthy app is scanned immediately")
    backoff.noteFailure(at: at(0))
    check(backoff.shouldScan(owned: false, now: at(0.1)),
          "one failed scan retries on the next scan")
    backoff.noteFailure(at: at(0.1))
    check(!backoff.shouldScan(owned: false, now: at(0.2)),
          "two consecutive failures enter a short cooldown")
    check(backoff.shouldScan(owned: true, now: at(0.2)),
          "an owned app is scanned through a cooldown")
    check(backoff.shouldScan(owned: false, now: at(2.1)),
          "the first cooldown expires after two seconds")
    var long = AppScanBackoff()
    for i in 0..<8 { long.noteFailure(at: at(Double(i))) }
    check(long.failures == 8, "scan failures accumulate")
    check(!long.shouldScan(owned: false, now: at(7.5)),
          "a repeated failure stays in cooldown")
    check(long.shouldScan(owned: false, now: at(40)),
          "the cooldown widens but never becomes permanent")
    long.noteSuccess()
    check(long.failures == 0 && long.shouldScan(owned: false, now: at(40)),
          "a successful scan resets the breaker")
  }
  static func scanReadinessChecks() {
    // scanReadiness lives in native/Accessibility.swift, which the portable
    // suite does not link (it needs AppKit/ApplicationServices). Mirror the
    // pure predicate here so its truth table is pinned against regressions.
    func scanReadiness(
      recordedLaunch: Double, observedLaunch: Double,
      frameReadable: Bool, eligibilityKnown: Bool
    ) -> Bool {
      guard frameReadable, eligibilityKnown else { return false }
      if recordedLaunch > 0 && observedLaunch > 0 {
        return abs(recordedLaunch - observedLaunch) < 0.01
      }
      return recordedLaunch == 0 && observedLaunch == 0
    }
    // A launch read that failed (0) must not silently disable tiling.
    check(scanReadiness(recordedLaunch: 0, observedLaunch: 0,
      frameReadable: true, eligibilityKnown: true),
      "unknown launch with readable frame and eligibility is ready")
    check(scanReadiness(recordedLaunch: 1_700_000_000.25, observedLaunch: 1_700_000_000.25,
      frameReadable: true, eligibilityKnown: true),
      "known matching launch is ready")
    check(scanReadiness(recordedLaunch: 1_700_000_000.25, observedLaunch: 1_700_000_000.255,
      frameReadable: true, eligibilityKnown: true),
      "known launch inside tolerance is ready")
    // PID reuse: two known instances that disagree must never be actionable.
    check(!scanReadiness(recordedLaunch: 1_700_000_000.25, observedLaunch: 1_700_000_999.25,
      frameReadable: true, eligibilityKnown: true),
      "known mismatching launch is not ready")
    check(!scanReadiness(recordedLaunch: 1_700_000_000.25, observedLaunch: 1_700_000_000.27,
      frameReadable: true, eligibilityKnown: true),
      "known launch past tolerance is not ready")
    // Failed reads of the other critical attributes still suppress mutations.
    check(!scanReadiness(recordedLaunch: 0, observedLaunch: 0,
      frameReadable: false, eligibilityKnown: true),
      "unknown frame is not ready")
    check(!scanReadiness(recordedLaunch: 0, observedLaunch: 0,
      frameReadable: true, eligibilityKnown: false),
      "unknown eligibility is not ready")
    check(!scanReadiness(recordedLaunch: 1_700_000_000.25, observedLaunch: 1_700_000_000.25,
      frameReadable: false, eligibilityKnown: true),
      "matching launch does not override an unread frame")
    // One side unknown and the other known is not a confirmed instance.
    check(!scanReadiness(recordedLaunch: 0, observedLaunch: 1_700_000_000.25,
      frameReadable: true, eligibilityKnown: true),
      "a zero record does not match a later nonzero launch")
    check(!scanReadiness(recordedLaunch: 1_700_000_000.25, observedLaunch: 0,
      frameReadable: true, eligibilityKnown: true),
      "a known record does not match an unread launch")
  }
  // An app that clamps a window (a minimum size) never reaches the requested
  // frame, so an identical plan must keep writing but farther apart, and must
  // never go permanently quiet. Real input always writes at once.
  static func writeBackoffChecks() {
    func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
    let target = Rect(x: 0, y: 40, width: 900, height: 1100)
    let clamped = Rect(x: 0, y: 40, width: 700, height: 900)
    let moved = Rect(x: 20, y: 60, width: 900, height: 1100)
    var backoff = WriteBackoff()
    check(backoff.shouldAttempt(target: target, observed: clamped, now: at(0)),
          "backoff writes a new target immediately")
    backoff.note(target: target, observed: clamped, at: at(0))
    check(backoff.attempts == 1, "backoff counts the first attempt")
    check(!backoff.shouldAttempt(target: target, observed: clamped, now: at(1)),
          "backoff defers an unchanged target before the first delay")
    check(!backoff.shouldAttempt(target: target, observed: clamped, now: at(1.99)),
          "backoff keeps deferring inside the first delay")
    // 2s, then 4s, then 8s, then 16s, then the 30s cap.
    let due = [2.0, 6.0, 14.0, 30.0, 60.0, 90.0]
    for (index, when) in due.enumerated() {
      check(backoff.shouldAttempt(target: target, observed: clamped, now: at(when)),
            "backoff attempt \(index + 2) is due at \(when)s")
      backoff.note(target: target, observed: clamped, at: at(when))
      check(!backoff.shouldAttempt(target: target, observed: clamped, now: at(when + 0.5)),
            "backoff waits again after attempt \(index + 2)")
    }
    check(backoff.attempts == due.count + 1, "backoff counts every attempt")
    check(!backoff.shouldAttempt(target: target, observed: clamped, now: at(119)),
          "backoff never widens past the cap")
    check(backoff.shouldAttempt(target: target, observed: clamped, now: at(120)),
          "backoff keeps attempting at the cap interval")
    // A fresh target is real input: attempt now even mid-backoff.
    check(backoff.shouldAttempt(target: moved, observed: clamped, now: at(120.1)),
          "a changed target resets the backoff to immediate")
    backoff.note(target: moved, observed: clamped, at: at(120.1))
    // A changed observed frame is real input too.
    check(backoff.shouldAttempt(target: moved, observed: target, now: at(120.2)),
          "a changed observed frame resets the backoff to immediate")
    backoff.note(target: moved, observed: target, at: at(120.2))
    check(!backoff.shouldAttempt(target: moved, observed: target, now: at(121)),
          "backoff still defers an unchanged pair")
    check(backoff.shouldAttempt(target: target, observed: target, now: at(121)),
          "a real move interleaved mid-backoff always attempts")
    backoff.note(target: target, observed: target, at: at(121))
    // reset() clears the schedule for the next real placement.
    check(!backoff.shouldAttempt(target: target, observed: target, now: at(122)),
          "backoff is engaged before reset")
    backoff.reset()
    check(backoff.shouldAttempt(target: target, observed: target, now: at(122)),
          "reset restores an immediate attempt")
    backoff.note(target: target, observed: target, at: at(122))
    check(!backoff.shouldAttempt(target: target, observed: target, now: at(123)),
          "reset restarts the first delay")
    check(backoff.shouldAttempt(target: target, observed: target, now: at(124)),
          "the restarted schedule is due after its own delay")
  }
}
