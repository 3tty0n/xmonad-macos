import Foundation

// Protocol and safety logic have no AppKit dependency and are tested on Linux.
// Transient AX surfaces must not redirect hover focus to their owning window.
func pointerFocusIsTransientRole(_ role: String) -> Bool {
  ["AXMenu", "AXMenuItem", "AXMenuBar", "AXMenuBarItem", "AXPopover", "AXSheet"].contains(role)
}

struct Rect: Codable, Equatable {
  var x: Int, y: Int, width: Int, height: Int
  func near(_ other: Rect, tolerance: Int = 2) -> Bool {
    abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
      && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
  }
  var valid: Bool {
    abs(Double(x)) < 1_000_000 && abs(Double(y)) < 1_000_000 && width > 0 && height > 0
      && width < 100_000 && height < 100_000
  }
  static func quartz(appKit r: Rect, primaryTop: Int) -> Rect {
    Rect(x: r.x, y: primaryTop - r.y - r.height, width: r.width, height: r.height)
  }
  func intersectionArea(_ other: Rect) -> Double {
    let w = max(0, min(x + width, other.x + other.width) - max(x, other.x))
    let h = max(0, min(y + height, other.y + other.height) - max(y, other.y))
    return Double(w) * Double(h)
  }
}
extension Rect {
  // WindowServer geometry is not always trustworthy: waking a display can
  // hand back a rectangle that is non-finite or beyond Int, and Int(_:)
  // traps on those, which took the whole helper down. Anything that is not
  // a usable rectangle is refused instead.
  init?(_ r: CGRect) {
    guard let x = Int(exactly: r.minX.rounded()), let y = Int(exactly: r.minY.rounded()),
      let width = Int(exactly: r.width.rounded()),
      let height = Int(exactly: r.height.rounded())
    else { return nil }
    let rect = Rect(x: x, y: y, width: width, height: height)
    guard rect.valid else { return nil }
    self = rect
  }
}
struct DisplayInfo: Codable, Equatable {
  var display: Int
  var usable: Rect
}
struct WindowInfo: Codable, Equatable {
  var wid: UInt64, pid: Int32
  var app: String, bundle: String, titleText: String
  var onDisplay: Int, frame: Rect
  var minimized: Bool, ownedHidden: Bool
  // AX subrole. Standard windows are AXStandardWindow; dialogs and
  // floating panels use the popup subroles below. Missing in old tests.
  var subrole: String = "AXStandardWindow"
  // The window belongs to an accessory (LSUIElement) application. Such a
  // window has no Dock icon or app-switcher entry, so policy floats it and
  // brings a newly shown one forward itself.
  var accessory: Bool = false
}
// Dialogs and floating panels the helper will manage as windows. Sheets and
// unknown subroles stay unmanaged: a sheet is tied to its parent.
func isManagedPopupSubrole(_ subrole: String) -> Bool {
  switch subrole {
  case "AXDialog", "AXSystemDialog", "AXFloatingWindow", "AXSystemFloatingWindow":
    return true
  default:
    return false
  }
}
// AXWindows lists real frames. GNU NS Emacs reports those frames as
// AXTextField; emacs-mac is usually AXWindow. Either is a window if it
// appears in that list.
func reportsAsWindowRole(_ role: String) -> Bool {
  role == "AXWindow" || role == "AXTextField" || role == "AXTextArea"
}
// Preserve admission across a timeout; a new window still needs a positive read.
func retainingWindowEligibility(previous: Bool, observed: Bool?) -> Bool {
  observed ?? previous
}
// nil is a failed query, not a successfully observed empty window list.
func cgOnScreenEvidence(querySucceeded: Bool, visible: Int, peers: Int,
                        omitsMetadata: Bool) -> Bool? {
  guard querySucceeded else { return nil }
  return (visible > 0 && visible >= peers) || (visible == 0 && omitsMetadata && peers <= 1)
}
// Monotonic seconds, supplied by the caller (and fake clocks in tests).
// Negative evidence accrues only between successful negative observations.
// A visibility-query failure freezes that counter; a separate uncertainty
// deadline bounds the visibility episode for unowned, non-orphaned windows.
struct VisibilityGrace {
  private(set) var negativeSeconds = 0.0
  private(set) var negativeReads = 0
  private(set) var uncertainSince: Double?
  private var previousAt: Double?
  private var previousNegative = false
  mutating func observe(_ positive: Bool?, at now: Double) {
    if positive == true {
      negativeSeconds = 0
      negativeReads = 0
      uncertainSince = nil
    } else {
      if uncertainSince == nil { uncertainSince = now }
      if positive == false {
        negativeReads += 1
        if previousNegative, let previousAt = previousAt {
          negativeSeconds += max(0, now - previousAt)
        }
      }
    }
    previousAt = now
    previousNegative = positive == false
  }
  func retainsKnown(at now: Double, negativeLimit: Double = 1.5,
                    uncertaintyLimit: Double = 2.0) -> Bool {
    negativeSeconds < negativeLimit
      && uncertainSince.map { max(0, now - $0) < uncertaintyLimit } != false
  }
}
// An application is allowed to refuse a geometry write: a window with a
// minimum size clamps to that size, so the requested target is never reached.
// Re-issuing the same size-position-size triple on a fixed interval then
// wastes AX work and contends with the application's own UI for an outcome
// that will not change. Identical, unmoved requests therefore back off — the
// first write is immediate, then 2s, 4s, 8s and so on up to a cap — and reset
// to immediate the moment any real input arrives. Like VisibilityGrace this is
// deliberately pure and clock-injected so the policy is unit-tested off the
// serial AX queue with a fake clock.
struct WriteBackoff {
  private(set) var target: Rect?
  private(set) var observed: Rect?
  // Writes issued for the current (target, observed) pair. 1 is the pair's
  // first attempt, which is also the one allowed to log.
  private(set) var attempts = 0
  private var nextAttemptAt = Date.distantPast
  static let firstDelay: TimeInterval = 2
  static let maxDelay: TimeInterval = 30
  // True when a write is due now: immediately for a target or observed frame
  // not seen before, otherwise once the growing delay since the previous
  // attempt for the same pair has elapsed. The pair is remembered so a later
  // query for the same, unchanged state is deferred.
  mutating func shouldAttempt(target t: Rect, observed o: Rect, now: Date) -> Bool {
    guard self.target == t, self.observed == o else {
      reset()
      target = t
      observed = o
      nextAttemptAt = now
      return true
    }
    return now >= nextAttemptAt
  }
  // Record an attempt for the pair and schedule the next one further out.
  mutating func note(target t: Rect, observed o: Rect, at now: Date) {
    if self.target != t || self.observed != o {
      reset()
      target = t
      observed = o
    }
    attempts += 1
    let delay = min(Self.maxDelay, Self.firstDelay * pow(2, Double(attempts - 1)))
    nextAttemptAt = now.addingTimeInterval(delay)
  }
  // Forget the pair so the next write for this window is immediate again:
  // a restore or release, a changed display arrangement, or a new epoch.
  mutating func reset() {
    target = nil
    observed = nil
    attempts = 0
    nextAttemptAt = Date.distantPast
  }
}
struct VisibilityDecision {
  var retained: Bool
  var actionable: Bool
  var reason: String
}
// AX read readiness gates mutations, not policy retention. A known window
// positively shown by CG in a shown app may retain its policy identity during
// an arbitrarily long AX timeout, but is never actionable during that timeout.
// Owned hides retain their identity without CG presence: absence is expected
// after parking/minimizing. Neither ownership nor retention permits ambiguous
// PID/frame mutations, or mutations after failed CG/app/critical AX reads.
func windowVisibilityDecision(known: Bool, owned: Bool, orphaned: Bool,
                              minimized: Bool, hidden: Bool?, onScreen: Bool?,
                              readsReady: Bool, hiddenGrace: VisibilityGrace,
                              screenGrace: VisibilityGrace, now: Double,
                              ambiguous: Bool = false,
                              unresponsive: Bool = false) -> VisibilityDecision {
  if minimized && !owned {
    return VisibilityDecision(retained: false, actionable: false, reason: "user-minimized")
  }
  // An app that keeps timing out is not evidence that its windows closed.
  // Keep a known window in the snapshot with its last observed state, but
  // never make it actionable while AX cannot confirm the world. A hidden app
  // and a user-minimized window still leave management.
  if unresponsive && known {
    let retained = hidden != true && (!minimized || owned)
    return VisibilityDecision(
      retained: retained, actionable: false,
      reason: retained ? "ax-unresponsive" : "app-hidden")
  }
  let hiddenOK = hidden == false
  let visibleOK = onScreen == true
  let retainedHidden = hiddenOK || (known && hiddenGrace.retainsKnown(at: now))
  let retainedScreen = visibleOK || (known && screenGrace.retainsKnown(at: now))
  let retained = retainedHidden && (owned || orphaned || retainedScreen)
    && (known || (onScreen != nil && readsReady))
    && (known || !ambiguous)
  let actionable = retained && hiddenOK && readsReady && onScreen != nil
    && (owned || visibleOK) && !orphaned && !ambiguous
  let reason = !hiddenOK ? (hidden == nil ? "app-query-unknown" : "app-hidden")
    : onScreen == nil ? "cg-query-failed"
    : ambiguous ? "same-pid-frame-ambiguity"
    : !visibleOK && !owned ? "cg-mismatch" : !readsReady ? "ax-query-unknown" : "visible"
  return VisibilityDecision(retained: retained, actionable: actionable, reason: reason)
}
// A per-application scan circuit breaker. The first slow/failed read retries on
// the next scan; a second consecutive failure backs off for 2s, then doubles up
// to 30s. Owned windows are always attempted because they carry recovery
// state. This is deliberately separate from WriteBackoff: a scan failure must
// not suppress a later real placement.
struct AppScanBackoff {
  private(set) var failures = 0
  private(set) var retryAt = Date.distantPast
  mutating func noteFailure(at now: Date) {
    failures += 1
    if failures < 2 {
      retryAt = .distantPast
    } else {
      let delay = min(30.0, 2.0 * pow(2.0, Double(failures - 2)))
      retryAt = now.addingTimeInterval(delay)
    }
  }
  mutating func noteSuccess() {
    failures = 0
    retryAt = .distantPast
  }
  func shouldScan(owned: Bool, now: Date) -> Bool {
    owned || now >= retryAt
  }
}
struct ScanMetrics: Equatable {
  var durationMs = 0
  var appsScanned = 0
  var appsDeferred = 0
  var appsCoolingDown = 0
  var appsTimedOut = 0
}

// Tiling admission. Minimized need not be settable: emacs-mac undecorated
// frames often have no AXMinimized. Empty subrole is a standard window that
// has not filled the attribute in yet.
// An accessory app is scanned only while it owns an on-screen window, or while
// policy still knows one of its windows (a panel that just closed). Apple's
// accessory agents are system UI, not tiling clients, and a bundle-less agent
// has no stable identity to match a window against.
func accessoryAppIsManaged(bundle: String, hasOnScreenWindow: Bool, known: Bool) -> Bool {
  guard !bundle.isEmpty, !bundle.hasPrefix("com.apple.") else { return false }
  return hasOnScreenWindow || known
}
func windowRoleIsEligible(
  role: String, subrole: String, fullScreen: Bool,
  positionSettable: Bool, sizeSettable: Bool, accessory: Bool = false
) -> Bool {
  guard reportsAsWindowRole(role), !fullScreen, positionSettable else { return false }
  if isManagedPopupSubrole(subrole) { return true }
  let standard =
    subrole == "AXStandardWindow" || subrole.isEmpty
    || role == "AXTextField" || role == "AXTextArea"
  // An accessory app's panel (Box Drive's search window, a utility's
  // settings) is often fixed-size but still a real window. It cannot tile,
  // but policy can float it and move it, so a readable position is enough.
  return standard && (sizeSettable || accessory)
}
// AX and CG disagree by a titlebar on emacs-mac and similar NS ports.
func cgMatchesAXFrame(_ ax: Rect, _ cg: Rect, originSlop: Int = 24) -> Bool {
  if ax.near(cg, tolerance: originSlop) { return true }
  let area = ax.intersectionArea(cg)
  let smaller = Double(min(ax.width * ax.height, cg.width * cg.height))
  return smaller > 0 && area >= 0.72 * smaller
}
// Normal (0), floating (3), modal panel (8) and utility (19). Dock is 20
// and the menu bar is 24; those are not application windows.
func cgWindowIsApplicationLayer(_ layer: Int) -> Bool {
  (0...19).contains(layer)
}
// Chrome withholds on-screen CGWindow metadata unless Screen Recording is
// granted. PID+frame correlation would then drop every window. AX already
// omits that app's windows on inactive Spaces, so trusting AX is safe here.
func bundleOmitsOnScreenCGWindows(_ bundle: String) -> Bool {
  bundle.hasPrefix("com.google.Chrome")
}
// AppKit keeps a window whose whole frame is off the screen partly on it, and
// what it puts back is the window's top-left 40x32: the left end of the title
// bar, standing in the workspace like a window that never left. A frame that
// still overlaps the screen by a point is left where it was asked to go, so a
// park aims one point inside the bottom-right corner of the display
// arrangement and leaves a single point of the window's corner instead. Screen
// bounds, not the usable rect: with a Dock on the right or bottom, the usable
// corner is on the display and the window would park that far inside it.
func parkOrigin(screens: [Rect], window: Rect) -> Rect {
  let right = screens.map { $0.x + $0.width }.max() ?? window.x
  let bottom = screens.map { $0.y + $0.height }.max() ?? window.y
  return Rect(x: right - 1, y: bottom - 1, width: window.width, height: window.height)
}
// An app that clamps its own frame back leaves more than that point, and a hide
// that could not move the window at all leaves all of it. Under a 64-point
// square is off the workspace; over it the helper minimizes instead.
func parkedOffDisplay(_ rect: Rect, _ displays: [DisplayInfo]) -> Bool {
  displays.map { $0.usable.intersectionArea(rect) }.reduce(0, +) <= 4096
}
// A mod-drag moves one window without a new observation. Patch its frame so
// the overlay repaints from the frame the window is actually at.
func patchingFrame(_ windows: [WindowInfo], wid: UInt64, frame: Rect) -> [WindowInfo] {
  windows.map { window in
    guard window.wid == wid else { return window }
    var updated = window
    updated.frame = frame
    return updated
  }
}
// The overlay follows a window that is already on a display. A restore keeps
// ownedHidden true until a later scan agrees; only a pinned focus request may
// trace through that interval. An owned-hidden window that is still painted
// is the outgoing workspace, not the focused one.
func tracesFocusBorder(_ window: WindowInfo, displays: [DisplayInfo], pinned: Bool = false) -> Bool
{
  !window.minimized && !parkedOffDisplay(window.frame, displays) && (pinned || !window.ownedHidden)
}
func cgHasWindow(pid: Int32, near rect: Rect, in windows: [(Int32, Rect)], tolerance: Int = 8)
  -> Bool
{
  windows.contains { $0.0 == pid && $0.1.near(rect, tolerance: tolerance) }
}
// One on-screen window in the window server's front-to-back order: the managed
// window it was matched to by PID and frame, or nil for anything else.
struct StackEntry: Equatable {
  var wid: UInt64?
  var frame: Rect
}
// Exact frame matches are claimed first so a loose (titlebar-offset) match
// cannot take a window that another entry shows exactly. A loose match must
// be the only candidate; an ambiguous entry stays unmanaged.
func observedStack(_ cg: [(Int32, Rect)], windows: [WindowInfo]) -> [StackEntry] {
  var owner = [UInt64?](repeating: nil, count: cg.count)
  var claimed = Set<UInt64>()
  for (i, entry) in cg.enumerated() {
    if let w = windows.first(where: {
      $0.pid == entry.0 && !claimed.contains($0.wid) && $0.frame.near(entry.1, tolerance: 8)
    }) {
      owner[i] = w.wid
      claimed.insert(w.wid)
    }
  }
  for (i, entry) in cg.enumerated() where owner[i] == nil {
    let loose = windows.filter {
      $0.pid == entry.0 && !claimed.contains($0.wid) && cgMatchesAXFrame($0.frame, entry.1)
    }
    if loose.count == 1 {
      owner[i] = loose[0].wid
      claimed.insert(loose[0].wid)
    }
  }
  return zip(owner, cg).map { StackEntry(wid: $0, frame: $1.1) }
}
// What covers a window: everything in front of it in the observed stack. A
// managed window counts at the rectangle it is painted at now, which a plan
// may have moved since the observation; one not painted (hidden, parked) is
// skipped. Nil when the window itself was not observed, so its depth is
// unknown.
func occluders(of wid: UInt64, in stack: [StackEntry], painted: [UInt64: Rect]) -> [Rect]? {
  guard let depth = stack.firstIndex(where: { $0.wid == wid }) else { return nil }
  return stack[..<depth].compactMap { entry in
    guard let other = entry.wid else { return entry.frame }
    return painted[other]
  }
}
// Floating windows of the focused window's own app to raise after it, in
// plan order (last is top). Another app's windows cannot be ordered without
// activating it, and a focused float needs no help staying above tiles.
func floatsToRaise(after wid: UInt64, floating: [UInt64], pids: [UInt64: Int32]) -> [UInt64] {
  guard let pid = pids[wid], !floating.contains(wid) else { return [] }
  return floating.filter { pids[$0] == pid }
}
// The subset of those that the observed stack shows behind the tiled window
// and overlapping it. Once raised they are in front, so a repeat scan finds
// nothing to do.
func floatsCovered(by wid: UInt64, floating: [UInt64], pids: [UInt64: Int32],
  stack: [StackEntry]) -> [UInt64]
{
  guard let depth = stack.firstIndex(where: { $0.wid == wid }) else { return [] }
  let frame = stack[depth].frame
  let covered = Set(
    stack[(depth + 1)...].compactMap { entry -> UInt64? in
      guard let id = entry.wid, entry.frame.intersectionArea(frame) > 0 else { return nil }
      return id
    })
  return floatsToRaise(after: wid, floating: floating, pids: pids).filter(covered.contains)
}
func cgShowsOriginal(pid: Int32, original: Rect, windows: [(Int32, Rect)], displays: [DisplayInfo])
  -> Bool
{
  !parkedOffDisplay(original, displays) && cgHasWindow(pid: pid, near: original, in: windows)
}
// Finder ignores a position-only park (the set succeeds, the frame does not
// change) and size-position-size clamps a large visible panel into the
// corner. Minimizing is the public hide that actually leaves the screen.
func parksByMinimizing(_ bundle: String) -> Bool {
  bundle == "com.apple.finder"
}
// A hide is journaled with the process instance it belongs to, so PID reuse
// cannot make a later process look like the owner of a minimized window.
// NSRunningApplication.launchDate is nil for the session's own launchd
// children - Finder among them - and without an instance the hide was
// refused, which is why Finder stayed on every workspace. The BSD start
// time is public and identifies the instance just as well.
func processStartTime(_ pid: Int32) -> Double {
  var info = kinfo_proc()
  var size = MemoryLayout<kinfo_proc>.stride
  var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
  guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return 0 }
  let started = info.kp_proc.p_starttime
  return Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
}
struct Snapshot: Encodable {
  let type = "snapshot"
  var generation: Int, epoch: Int, screens: [DisplayInfo], windows: [WindowInfo]
  var focused: UInt64?
  var restore: JSONValue?
}
struct KeyBinding: Codable, Hashable {
  var mask: Int
  var sym: Int
}
struct Placement: Codable {
  var wid: UInt64
  var frame: Rect
}
// A border width the plan asks for by name. Zero means the window is drawn
// with no border at all; a window the plan does not name keeps the configured
// width.
struct BorderOverride: Codable {
  var wid: UInt64
  var width: Int
}
struct WorkspaceInfo: Codable, Equatable {
  var tag: String, windows: Int, current: Bool, visible: Bool
}
struct Plan: Decodable {
  var generation: Int, epoch: Int, frames: [Placement], hide: [UInt64]
  var focus: UInt64?, workspace: String, layout: String, checkpoint: JSONValue
  // Additive and optional: a signed helper that predates this field draws
  // the configured width for every window.
  var borders: [BorderOverride]?
  var workspaces: [WorkspaceInfo]?
  // Placed floating windows, bottom to top. Absent from older engines, which
  // leaves floats where the system put them.
  var floating: [UInt64]?
  // Menu bar text rendered by a logHook's PP; nil keeps workspaceRow.
  var status: String?
  var screen: Int?
  var action: Int?
  var focusForMs: Int?
}
// xmobar-style row: every workspace that holds windows, plus the current one.
// "[2]" is current, a bare tag has windows, so an empty desktop stays quiet.
func workspaceRow(_ all: [WorkspaceInfo]) -> String {
  let shown = all.filter { $0.windows > 0 || $0.current || $0.visible }
  return shown.map { w in
    w.current ? "[\(w.tag)]" : (w.visible ? "(\(w.tag))" : w.tag)
  }.joined(separator: " ")
}
enum JSONValue: Codable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let b = try? c.decode(Bool.self) {
      self = .bool(b)
    } else if let n = try? c.decode(Double.self) {
      self = .number(n)
    } else if let s = try? c.decode(String.self) {
      self = .string(s)
    } else if let a = try? c.decode([JSONValue].self) {
      self = .array(a)
    } else {
      self = .object(try c.decode([String: JSONValue].self))
    }
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let b): try c.encode(b)
    case .number(let n): try c.encode(n)
    case .string(let s): try c.encode(s)
    case .array(let a): try c.encode(a)
    case .object(let o): try c.encode(o)
    }
  }
}
enum WireError: Error, CustomStringConvertible {
  case invalid(String)
  var description: String {
    if case .invalid(let s) = self { return s }
    return "invalid"
  }
}
// Appearance and pointer policy, decided by the config and applied by the helper.
struct Appearance {
  var borderWidth = 0
  var borderColor = "#ff0000"
  var normalBorderColor = "#dddddd"
  var focusFollowsMouse = false
  var mouse: [MouseBind] = []
}
enum PointerMode: String, Codable { case move, resize, raise }
struct MouseBind: Codable, Equatable {
  var mask: Int, button: Int, action: PointerMode
}
enum EngineMessage: Decodable {
  case configure(Int, [KeyBinding], [MouseBind], Appearance)
  case plan(Plan)
  case command(String, UInt64?)
  case pong
  case movePointer(Rect, Rect)
  private enum CodingKeys: String, CodingKey {
    case type, `protocol`, keys, mouseMask, mouse, name, wid
    case borderWidth, borderColor, normalBorderColor, focusFollowsMouse
    case mask, button, action, bounds, focus
  }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    switch try c.decode(String.self, forKey: .type) {
    case "configure":
      let mouse = try EngineMessage.decodeMouse(c)
      let look = Appearance(
        borderWidth: try c.decodeIfPresent(Int.self, forKey: .borderWidth) ?? 0,
        borderColor: try c.decodeIfPresent(String.self, forKey: .borderColor) ?? "#ff0000",
        normalBorderColor: try c.decodeIfPresent(String.self, forKey: .normalBorderColor)
          ?? "#dddddd",
        focusFollowsMouse: try c.decodeIfPresent(Bool.self, forKey: .focusFollowsMouse) ?? false,
        mouse: mouse)
      self = .configure(
        try c.decode(Int.self, forKey: .protocol),
        try c.decode([KeyBinding].self, forKey: .keys),
        mouse, look)
    case "plan": self = .plan(try Plan(from: decoder))
    case "command":
      self = .command(
        try c.decode(String.self, forKey: .name),
        try c.decodeIfPresent(UInt64.self, forKey: .wid))
    case "movePointer":
      self = .movePointer(
        try c.decode(Rect.self, forKey: .bounds),
        try c.decode(Rect.self, forKey: .focus))
    case "pong": self = .pong
    default: throw WireError.invalid("Unknown engine message")
    }
  }
  private static func decodeMouse(_ c: KeyedDecodingContainer<CodingKeys>) throws -> [MouseBind] {
    if let mouse = try c.decodeIfPresent([MouseBind].self, forKey: .mouse), !mouse.isEmpty {
      return mouse
    }
    let mask = try c.decodeIfPresent(Int.self, forKey: .mouseMask) ?? 0
    return [
      MouseBind(mask: mask, button: 1, action: .move),
      MouseBind(mask: mask, button: 3, action: .resize),
    ]
  }
}
struct PlanSafety {
  static func validate(_ p: Plan, active: Set<UInt64>) throws {
    let shown = p.frames.map(\.wid)
    guard shown.count <= 10_000, p.hide.count <= 10_000 else {
      throw WireError.invalid("Unreasonable plan size")
    }
    guard Set(shown).count == shown.count, Set(p.hide).count == p.hide.count else {
      throw WireError.invalid("Duplicate window IDs in plan")
    }
    guard Set(shown).isDisjoint(with: Set(p.hide)) else {
      throw WireError.invalid("A window cannot be shown and hidden simultaneously")
    }
    guard Set(shown + p.hide).isSubset(of: active) else {
      throw WireError.invalid("Plan refers to windows outside the current snapshot")
    }
    guard p.frames.allSatisfy({ $0.frame.valid }) else {
      throw WireError.invalid("Invalid rectangle in plan")
    }
    if let focus = p.focus, !shown.contains(focus) {
      throw WireError.invalid("Focus target is hidden")
    }
    // A width may name a window this plan does not place. A layout keeps
    // its hidden set across passes, so when a workspace empties it states
    // the previous width again for a window that is now elsewhere; the
    // helper only reads a width for a window it draws, so the entry is
    // harmless. Rejecting it paused the session every time the last window
    // left a smartBorders workspace.
    if let borders = p.borders {
      guard borders.count <= 10_000 else {
        throw WireError.invalid("Unreasonable border list")
      }
      guard borders.allSatisfy({ (0...64).contains($0.width) }) else {
        throw WireError.invalid("Border width outside 0...64")
      }
    }
  }
}
func bestDisplay(for rect: Rect, in displays: [DisplayInfo]) -> Int {
  guard let first = displays.first else { return 0 }
  var best = first
  var area = -1.0
  var distance = Double.greatestFiniteMagnitude
  for d in displays {
    let a = rect.intersectionArea(d.usable)
    let dx =
      Double(rect.x) + Double(rect.width) / 2 - Double(d.usable.x) - Double(d.usable.width) / 2
    let dy =
      Double(rect.y) + Double(rect.height) / 2 - Double(d.usable.y) - Double(d.usable.height) / 2
    let dist = dx * dx + dy * dy
    if a > area || (a == area && dist < distance) {
      best = d
      area = a
      distance = dist
    }
  }
  return best.display
}

// Keysyms are translated to physical ANSI/JIS letter-key positions, not text.
// This avoids Option-generated characters and preserves modifier-release behavior.
let keyCodeForSym: [Int: UInt16] = {
  let pairs: [(Character, UInt16)] = [
    ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7),
    ("c", 8), ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15),
    ("y", 16), ("t", 17), ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22),
    ("5", 23), ("=", 24), ("9", 25), ("7", 26), ("-", 27), ("8", 28), ("0", 29),
    ("]", 30), ("o", 31), ("u", 32), ("[", 33), ("i", 34), ("p", 35), ("l", 37),
    ("j", 38), ("'", 39), ("k", 40), (";", 41), ("\\", 42), (",", 43), ("/", 44),
    ("n", 45), ("m", 46), (".", 47), (" ", 49), ("`", 50),
  ]
  var map = Dictionary(uniqueKeysWithValues: pairs.map { (Int($0.0.asciiValue!), $0.1) })
  for (s, k) in [
    (0xff0d, 36), (0xff09, 48), (0xff08, 51), (0xff1b, 53),
    (0xffff, 117), (0xff51, 123), (0xff52, 126), (0xff53, 124), (0xff54, 125),
    (0xff50, 115), (0xff57, 119), (0xff55, 116), (0xff56, 121),
  ] {
    map[s] = UInt16(k)
  }
  let fs: [UInt16] = [
    122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
  ]
  for (i, k) in fs.enumerated() { map[0xffbe + i] = k }
  return map
}()
let symForKeyCode = Dictionary(uniqueKeysWithValues: keyCodeForSym.map { ($0.value, $0.key) })
func validateModifierMask(_ mask: Int) throws {
  guard mask >= 0, mask & ~(1 | 4 | 8 | 64) == 0 else {
    throw WireError.invalid("Unsupported modifier mask=\(mask)")
  }
}
func validatePointerMask(_ mask: Int) throws {
  try validateModifierMask(mask)
  guard mask != 0 else { throw WireError.invalid("Pointer modifier mask must not be zero") }
}
func validateMouseBindings(_ binds: [MouseBind]) throws {
  guard !binds.isEmpty else { throw WireError.invalid("No mouse bindings") }
  var seen = Set<String>()
  for b in binds {
    try validatePointerMask(b.mask)
    guard (1...32).contains(b.button) else {
      throw WireError.invalid("Unsupported mouse button \(b.button)")
    }
    let key = "\(b.mask):\(b.button)"
    guard seen.insert(key).inserted else {
      throw WireError.invalid("Duplicate mouse binding \(key)")
    }
  }
}
func validateBinding(_ key: KeyBinding) throws {
  try validateModifierMask(key.mask)
  guard keyCodeForSym[key.sym] != nil else {
    throw WireError.invalid("Unsupported key binding mask=\(key.mask) sym=\(key.sym)")
  }
  guard key.mask != 0 || key.sym >= 0xff00 else {
    throw WireError.invalid("Unmodified printable global shortcuts are disabled")
  }
}
struct WindowPrint: Codable, Equatable {
  var wid: UInt64, pid: Int32, launch: Double, bundle: String
  var identifier: String, title: String, frame: Rect
}
func matchWindowPrints(old: [WindowPrint], new: [WindowPrint]) -> [UInt64: UInt64] {
  var map: [UInt64: UInt64] = [:]
  var taken = Set<UInt64>()
  func unique(_ pred: (WindowPrint, WindowPrint) -> Bool) {
    for o in old where map[o.wid] == nil {
      let hits = new.filter { pred(o, $0) && !taken.contains($0.wid) }
      if hits.count == 1, let n = hits.first {
        map[o.wid] = n.wid
        taken.insert(n.wid)
      }
    }
  }
  unique { !$0.identifier.isEmpty && $0.bundle == $1.bundle && $0.identifier == $1.identifier }
  unique { $0.bundle == $1.bundle && $0.title == $1.title && $0.frame.near($1.frame, tolerance: 8) }
  return map
}
func remapCheckpoint(_ value: JSONValue, map: [UInt64: UInt64], epoch: Int) -> JSONValue {
  func mapId(_ v: JSONValue) -> JSONValue {
    if case .number(let n) = v, let w = map[UInt64(n)] { return .number(Double(w)) }
    return .null
  }
  func mapIds(_ v: JSONValue) -> JSONValue {
    guard case .array(let a) = v else { return v }
    return .array(
      a.compactMap {
        if case .number(let n) = $0, let w = map[UInt64(n)] { return JSONValue.number(Double(w)) }
        return nil
      })
  }
  func walk(_ v: JSONValue) -> JSONValue {
    switch v {
    case .object(let o):
      var n = o
      if let w = o["savedWindows"] { n["savedWindows"] = mapIds(w) }
      if let f = o["savedFocus"] { n["savedFocus"] = mapId(f) }
      if let fl = o["savedFloats"], case .array(let rows) = fl {
        n["savedFloats"] = .array(
          rows.compactMap { row -> JSONValue? in
            guard case .array(let cols) = row, let first = cols.first,
              case .number(let n0) = first, let w = map[UInt64(n0)]
            else { return nil }
            var c = cols
            c[0] = .number(Double(w))
            return .array(c)
          })
      }
      if o["savedEpoch"] != nil { n["savedEpoch"] = .number(Double(epoch)) }
      if let ws = o["savedWorkspaces"] { n["savedWorkspaces"] = walk(ws) }
      return .object(n)
    case .array(let a): return .array(a.map(walk))
    default: return v
    }
  }
  return walk(value)
}
struct SessionFile: Codable {
  var checkpoint: JSONValue
  var prints: [WindowPrint]
}
func resizeFloor(_ minSize: (Int, Int)?) -> (Int, Int) {
  (max(1, minSize?.0 ?? 80), max(1, minSize?.1 ?? 60))
}
