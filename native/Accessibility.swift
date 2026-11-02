#if os(macOS)
import Foundation
import AppKit
import ApplicationServices
import Darwin

func logMessage(_ s: String) {
  let text = "[\(ISO8601DateFormatter().string(from:Date()))] \(s)\n"
  FileHandle.standardError.write(Data(text.utf8))
}
func axCopy(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
  var raw: CFTypeRef?
  guard AXUIElementCopyAttributeValue(e, name as CFString, &raw) == .success else { return nil }
  return raw
}
func axElement(_ e: AXUIElement, _ name: String) -> AXUIElement? {
  guard let raw = axCopy(e, name), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
  return unsafeBitCast(raw, to: AXUIElement.self)
}
func axBoolean(_ e: AXUIElement, _ name: String) -> Bool? { axCopy(e, name) as? Bool }
// Unsupported is normal for some dialogs; transport failure is never false.
func axMinimizedRead(_ e: AXUIElement) -> Bool? {
  var raw: CFTypeRef?
  let error = AXUIElementCopyAttributeValue(e, kAXMinimizedAttribute as CFString, &raw)
  if error == .attributeUnsupported { return false }
  return error == .success ? raw as? Bool : nil
}
func axBool(_ e: AXUIElement, _ name: String) -> Bool { axBoolean(e, name) ?? false }
func axString(_ e: AXUIElement, _ name: String) -> String { (axCopy(e, name) as? String) ?? "" }
func axSettable(_ e: AXUIElement, _ name: String) -> Bool {
  axSettableRead(e, name) ?? false
}
func axSettableRead(_ e: AXUIElement, _ name: String) -> Bool? {
  var value: DarwinBoolean = false
  guard AXUIElementIsAttributeSettable(e, name as CFString, &value) == .success else { return nil }
  return value.boolValue
}
func axFrame(_ e: AXUIElement) -> Rect? {
  guard let p = axCopy(e, kAXPositionAttribute), let s = axCopy(e, kAXSizeAttribute),
    CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID()
  else { return nil }
  var point = CGPoint.zero
  var size = CGSize.zero
  guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
    AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size)
  else { return nil }
  // The same admission rule the window server's rectangles get, so a
  // non-finite or degenerate AX frame is refused here rather than rounded
  // into a zero-sized rectangle.
  return Rect(CGRect(x: point.x, y: point.y, width: size.width, height: size.height))
}
func axMinSize(_ e: AXUIElement) -> (Int, Int)? {
  for name in ["AXMinSize", "AXMinimumSize"] {
    guard let raw = axCopy(e, name), CFGetTypeID(raw) == AXValueGetTypeID() else { continue }
    var size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgSize, &size),
      size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1,
      size.width < 100_000, size.height < 100_000
    else { continue }
    return (Int(size.width.rounded()), Int(size.height.rounded()))
  }
  return nil
}
func windowEligible(_ e: AXUIElement, subrole: String, accessory: Bool = false) -> Bool {
  windowEligibility(e, subrole: subrole, accessory: accessory) ?? false
}
// Unknown AX capability is not evidence that an admitted window disappeared.
// Unsupported fullscreen attributes are normal; transport failures are not.
func windowEligibility(_ e: AXUIElement, subrole: String, accessory: Bool = false) -> Bool? {
  guard let role = axCopy(e, kAXRoleAttribute) as? String else { return nil }
  var raw: CFTypeRef?
  let error = AXUIElementCopyAttributeValue(e, "AXFullScreen" as CFString, &raw)
  let fullScreen: Bool
  if error == .attributeUnsupported { fullScreen = false }
  else if error == .success, let value = raw as? Bool { fullScreen = value }
  else { return nil }
  guard let position = axSettableRead(e, kAXPositionAttribute) else { return nil }
  if isManagedPopupSubrole(subrole) {
    return windowRoleIsEligible(role: role, subrole: subrole, fullScreen: fullScreen,
                               positionSettable: position, sizeSettable: false,
                               accessory: accessory)
  }
  guard let size = axSettableRead(e, kAXSizeAttribute) else { return nil }
  return windowRoleIsEligible(role: role, subrole: subrole, fullScreen: fullScreen,
                             positionSettable: position, sizeSettable: size,
                             accessory: accessory)
}
// A window is actionable only when its current geometry and eligibility were
// actually read. The launch values are the process instance behind the PID:
// a known pair that disagrees is PID reuse, so it must not inherit the old
// window. sysctl can fail and leave the launch at 0, and refusing every such
// window would silently stop tiling it, so an unknown launch on both sides is
// still actionable; only two known values can contradict each other. One
// known and one zero is not a match: the instance cannot be confirmed.
func scanReadiness(recordedLaunch: Double, observedLaunch: Double,
                   frameReadable: Bool, eligibilityKnown: Bool) -> Bool {
  guard frameReadable, eligibilityKnown else { return false }
  if recordedLaunch > 0 && observedLaunch > 0 {
    return abs(recordedLaunch - observedLaunch) < 0.01
  }
  return recordedLaunch == 0 && observedLaunch == 0
}
func axListedAsWindow(_ e: AXUIElement) -> Bool {
  reportsAsWindowRole(axString(e, kAXRoleAttribute)) && axFrame(e) != nil
}
// A native tab group exposes a single AXTabGroup child on the visible
// container window. Every tab is also an AXWindow at the container's frame,
// so this is the public signal that separates the real window from its tab
// siblings.
func axHasTabGroupChild(_ e: AXUIElement) -> Bool {
  guard let children = axCopy(e, kAXChildrenAttribute) as? [AXUIElement] else {
    return false
  }
  return children.contains { axString($0, kAXRoleAttribute) == "AXTabGroup" }
}
// System-wide AXFocusedWindow can name a text area inside the frame (Emacs).
func axWindowRoot(_ e: AXUIElement) -> AXUIElement {
  if axString(e, kAXRoleAttribute) == kAXWindowRole { return e }
  if let w = axElement(e, kAXWindowAttribute) { return w }
  var current = e
  for _ in 0..<8 {
    guard let parent = axElement(current, kAXParentAttribute) else { break }
    if axString(parent, kAXRoleAttribute) == kAXWindowRole { return parent }
    current = parent
  }
  return e
}
func axSameWindow(_ a: AXUIElement, _ b: AXUIElement) -> Bool {
  if CFEqual(a, b) { return true }
  let ra = axWindowRoot(a)
  let rb = axWindowRoot(b)
  return CFEqual(ra, rb) || CFEqual(a, rb) || CFEqual(ra, b)
}
// System-wide AXFocusedApplication is empty for Chromium even while the
// browser is frontmost. The workspace PID plus that app's AXFocusedWindow
// is the public fallback.
func focusedAXWindow() -> AXUIElement? {
  let system = AXUIElementCreateSystemWide()
  if let app = axElement(system, kAXFocusedApplicationAttribute),
    let window = axElement(app, kAXFocusedWindowAttribute)
  {
    return axWindowRoot(window)
  }
  guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
    pid != getpid()
  else { return nil }
  let app = AXUIElementCreateApplication(pid)
  AXUIElementSetMessagingTimeout(app, 0.15)
  return axElement(app, kAXFocusedWindowAttribute).map(axWindowRoot)
}
// Chromium animates or drops AX geometry writes while this is on. Toggle it
// only around a write, then restore, so VoiceOver is not left disabled.
func withImmediateAXGeometry<T>(_ pid: pid_t, _ body: () -> T) -> T {
  let app = AXUIElementCreateApplication(pid)
  let enhanced = axBoolean(app, "AXEnhancedUserInterface") == true
  if enhanced {
    AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
  }
  defer {
    if enhanced {
      AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }
  }
  return body()
}
// The window server's on-screen application windows, front to back. Public
// metadata only: PID and bounds, no window numbers.
func cgVisibleFrames() -> [(pid_t, Rect)]? {
  guard
    let list = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID) as? [[String: Any]]
  else { return nil }
  return list.compactMap { d in
    guard let layer = (d[kCGWindowLayer as String] as? NSNumber)?.intValue,
      cgWindowIsApplicationLayer(layer),
      let pid = (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
      let bounds = d[kCGWindowBounds as String] as? [String: Any],
      let r = CGRect(dictionaryRepresentation: bounds as CFDictionary),
      let frame = Rect(r)
    else { return nil }
    return (pid, frame)
  }
}
// Accessory apps normally own no windows, so they are not scanned. One that
// currently owns an on-screen application window is a real UI surface: Box
// Drive's integration panel is a fixed-size standard window of an LSUIElement
// app. Only PIDs with such a window are reported, so idle helpers cost nothing.
func onScreenApplicationPIDs() -> Set<pid_t> {
  guard
    let list = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID) as? [[String: Any]]
  else { return [] }
  let me = ProcessInfo.processInfo.processIdentifier
  return Set(
    list.compactMap { d -> pid_t? in
      guard let layer = (d[kCGWindowLayer as String] as? NSNumber)?.intValue,
        cgWindowIsApplicationLayer(layer),
        let pid = (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
        pid != me
      else { return nil }
      return pid
    })
}
struct AppDescriptor {
  var pid: pid_t, name: String, bundle: String, launch: Double, hidden: Bool
  // LSUIElement application. Its windows are floated and a newly shown one
  // is brought forward by policy, because the app has no ordinary activation
  // path of its own.
  var accessory: Bool = false
}
final class AXRecord {
  let wid: UInt64
  var descriptor: AppDescriptor
  var element: AXUIElement
  var frame: Rect, title: String, identifier: String
  // A native tab that is not the visible container. macOS exposes every tab
  // as an AXWindow at the same frame; only the window carrying the AXTabGroup
  // child is the container. Tab siblings are managed by the app, not us.
  var tabSibling = false
  // When the element was first found destroyed. Display wake destroys every
  // element and the replacements take several seconds to appear, so the
  // record, with its last known state, stands in for the window meanwhile.
  var orphanedAt: Date?
  // Whether a wake had just recycled the elements when this one died. Decided
  // once, when the element is first found destroyed: a window closed with
  // cmd-W is gone for good and must not wait for a replacement.
  var awaitsReplacement = false
  var token: String?
  var hideRequestedAt = Date.distantPast
  var wantsHidden = false
  // The restore is re-asserted until AX agrees or this settles: a minimize
  // still in flight must not be read as "already back".
  var restoreRequestedAt = Date.distantPast
  // Last AX-observed minimized state, like `frame`, kept so a failed read
  // does not drop the window from a snapshot.
  var lastMinimized: Bool?
  var screenGrace = VisibilityGrace()
  var hiddenGrace = VisibilityGrace()
  var visibilityReason = "unobserved"
  var hasEnteredSnapshot = false
  // Consecutive scans this window's application was missing from the
  // running-application list, or reported as hidden.
  var appAbsent = 0
  var eligible = false
  var subrole = ""
  var absent = 0
  // Adaptive retry policy for a target the application refuses to reach; see
  // WriteBackoff. Replaces a fixed throttle so an impossible size does not
  // keep re-issuing the same write for as long as plans keep arriving.
  var backoff = WriteBackoff()
  var minSize: (Int, Int)?
  init(_ wid: UInt64, _ e: AXUIElement, _ app: AppDescriptor, _ frame: Rect) {
    self.wid = wid
    element = e
    descriptor = app
    self.frame = frame
    title = axString(e, kAXTitleAttribute)
    identifier = axString(e, kAXIdentifierAttribute)
    subrole = axString(e, kAXSubroleAttribute)
  }
  var recovery: RecoveryEntry {
    RecoveryEntry(
      token: UUID().uuidString, pid: descriptor.pid, launch: descriptor.launch,
      bundle: descriptor.bundle, identifier: identifier, title: title, frame: frame)
  }
}
final class NotificationRelay {
  var changed: (() -> Void)?
  func notify() { DispatchQueue.main.async { [weak self] in self?.changed?() } }
}
struct ScanResult {
  var windows: [WindowInfo], focused: UInt64?, nativeFullScreen: Bool
  var stack: [StackEntry] = []
  var metrics = ScanMetrics()
}
struct PointerDragSession {
  var wid: UInt64, mode: PointerMode, start: CGPoint, initial: Rect
}
struct AXSelfTestReport: Codable {
  var accessibilityTrusted: Bool
  var focusedWindowFound: Bool
  var standardWindow: Bool
  var positionSettable: Bool
  var sizeSettable: Bool
  var minimizedSettable: Bool
  var frameReadable: Bool
  var sameFrameWriteSucceeded: Bool
  var readBackMatched: Bool
  var onScreenCorrelation: Bool
  var nativeFullScreen: Bool
  var pid: Int32?
  var title: String?
  var frame: Rect?
  var errors: [String]
  var passed: Bool {
    accessibilityTrusted && focusedWindowFound && standardWindow && positionSettable && sizeSettable
      && minimizedSettable && frameReadable && sameFrameWriteSucceeded && readBackMatched
      && onScreenCorrelation && !nativeFullScreen
  }
}

// All methods except the notification callback run on one serial AX queue.
// AppKit, the event tap and the engine reader never wait synchronously on AX.
final class AXStore {
  let journal: RecoveryJournal
  let relay: NotificationRelay
  private var records: [UInt64: AXRecord] = [:]
  private var observers: [pid_t: AXObserver] = [:]
  private var nextID: UInt64 = 1
  private var active: Set<UInt64> = []
  // Policy retention is not permission to mutate a window on an uncertain Space.
  private var actionable: Set<UInt64> = []
  private var latestGeneration = -1
  private var activeEpoch = 0
  private var lastAmbiguityWarning = Date.distantPast
  private var displays: [DisplayInfo] = []
  // How long a destroyed element may wait for its replacement. Measured on
  // display wake: replacements arrive about five seconds after the old
  // elements die, so this is generous rather than tight. It applies only
  // after a wake, which is the one event that recycles elements: a window
  // closed with cmd-W is gone at once, and waiting on it would leave a hole
  // in the layout for the whole grace.
  private let orphanGrace: TimeInterval = 30
  private var wokeAt = Date.distantPast
  private var pointerDrag: PointerDragSession?
  // The display the pointer was last sent to; -1 until the first plan, so
  // starting up never moves it.
  private var pointerScreen = -1
  private var axFail: [pid_t: Int] = [:]
  private var scanBackoff: [pid_t: AppScanBackoff] = [:]
  private var lastScannedAt: [pid_t: Date] = [:]
  private var lastScanMetricsLog = Date.distantPast
  private var actionFirstSeen: [Int: Date] = [:]
  private var actionFrom: [Int: UInt64] = [:]
  private var pendingAck: (Int, UInt64?, Bool)?
  private var floatOrder: [UInt64] = []
  private var lastScanFocus: UInt64?
  init(journal: RecoveryJournal, relay: NotificationRelay) {
    self.journal = journal
    self.relay = relay
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.2)
  }
  private func observe(_ app: AppDescriptor, _ root: AXUIElement) {
    guard observers[app.pid] == nil else { return }
    var raw: AXObserver?
    guard
      AXObserverCreate(
        app.pid,
        { _, _, _, context in
          guard let context = context else { return }
          Unmanaged<NotificationRelay>.fromOpaque(context).takeUnretainedValue().notify()
        }, &raw) == .success, let observer = raw
    else { return }
    let context = Unmanaged.passUnretained(relay).toOpaque()
    for name in [
      kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
      kAXApplicationHiddenNotification, kAXApplicationShownNotification,
    ] {
      AXObserverAddNotification(observer, root, name as CFString, context)
    }
    observers[app.pid] = observer
    DispatchQueue.main.async {
      CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
  }
  private func observeWindow(_ r: AXRecord) {
    guard let observer = observers[r.descriptor.pid] else { return }
    let context = Unmanaged.passUnretained(relay).toOpaque()
    for name in [
      kAXUIElementDestroyedNotification, kAXMovedNotification, kAXResizedNotification,
      kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
      kAXTitleChangedNotification,
    ] {
      AXObserverAddNotification(observer, r.element, name as CFString, context)
    }
  }
  // ESRCH means no such process; anything else means it is still there, or
  // that we may not ask, and either way the window is not proven gone.
  private func processIsGone(_ pid: pid_t) -> Bool {
    kill(pid, 0) == -1 && errno == ESRCH
  }
  func displaysWoke() { wokeAt = Date() }
  // The grace runs from the later of the element's death and the last wake:
  // displays that sleep again immediately, as they do when a wake is only the
  // machine stirring, must not spend it, because the replacement elements
  // arrive after the next wake rather than while the displays are off.
  private func awaitingReplacement(_ r: AXRecord) -> Bool {
    guard r.awaitsReplacement, let at = r.orphanedAt else { return false }
    return Date().timeIntervalSince(max(at, wokeAt)) <= orphanGrace
  }
  private func releaseOwnership(_ r: AXRecord) {
    guard let token = r.token else { return }
    do {
      try journal.remove(token)
      r.token = nil
      // Ownership ended: the next placement is real input, not a retry.
      r.backoff.reset()
    } catch { logMessage("Cannot update recovery journal: \(error)") }
  }
  // NSWorkspace may report a just-launched app as regular for one scan before
  // setActivationPolicy(.accessory) propagates. Keep the recorded launch time
  // (process identity) but refresh the descriptive fields so an accessory
  // window is not stuck as a regular one for its whole lifetime.
  private func refreshDescriptor(_ r: AXRecord, from app: AppDescriptor) {
    r.descriptor.name = app.name
    r.descriptor.bundle = app.bundle
    r.descriptor.hidden = app.hidden
    r.descriptor.accessory = app.accessory
  }
  // A stale record adopts a replacement element only when the match is
  // unique: by AXIdentifier when the element has one, otherwise by title
  // plus either a nearby old frame or ownership (a token means we may have
  // moved the window ourselves, so its frame is not a reliable anchor).
  // Two stale records matching the same element is never guessed at.
  private func adoptStale(_ stale: [AXRecord], _ adopted: Set<UInt64>, _ e: AXUIElement)
    -> AXRecord?
  {
    let candidates = stale.filter { !adopted.contains($0.wid) }
    let ident = axString(e, kAXIdentifierAttribute)
    let matches: [AXRecord]
    if !ident.isEmpty {
      matches = candidates.filter { $0.identifier == ident }
    } else {
      let title = axString(e, kAXTitleAttribute)
      let frame = axFrame(e)
      matches = candidates.filter { r in
        guard r.title == title else { return false }
        let framesNear = frame.map { r.frame.near($0, tolerance: 8) } ?? false
        return framesNear || r.token != nil
      }
    }
    return matches.count == 1 ? matches.first : nil
  }
  func scan(apps: [AppDescriptor], displays: [DisplayInfo], generation: Int, epoch: Int)
    -> ScanResult
  {
    let scanStarted = Date()
    var metrics = ScanMetrics()
    let previousEpoch = activeEpoch
    latestGeneration = generation
    activeEpoch = epoch
    // A changed display arrangement moves every window's real frame; a
    // backoff computed for the old arrangement must not defer the new one.
    if displays != self.displays || previousEpoch != epoch {
      for r in records.values { r.backoff.reset() }
      scanBackoff.removeAll()
      lastScannedAt.removeAll()
    }
    self.displays = displays
    let livePIDs = Set(apps.map(\.pid))
    // Drop state for processes that are no longer listed, but keep a failed
    // app's breaker across a transient NSWorkspace omission.
    scanBackoff = scanBackoff.filter { livePIDs.contains($0.key) }
    lastScannedAt = lastScannedAt.filter { livePIDs.contains($0.key) }
    // An application missing from one scan is not proof that it exited:
    // coming back from display sleep, NSWorkspace briefly reports an
    // incomplete list. Forgetting a window here is expensive, because the
    // engine then treats it as new and adopts it onto the workspace in
    // view, so wait for a second scan and ask the kernel as well.
    for (id, r) in Array(records) {
      let listed = apps.contains {
        $0.pid == r.descriptor.pid
          && abs($0.launch - r.descriptor.launch) < 0.01
      }
      if listed {
        r.appAbsent = 0
        continue
      }
      r.appAbsent += 1
      if r.appAbsent >= 2, processIsGone(r.descriptor.pid) {
        releaseOwnership(r)
        records.removeValue(forKey: id)
      }
    }
    for pid in Array(observers.keys) where !livePIDs.contains(pid) {
      if let ob = observers.removeValue(forKey: pid) {
        DispatchQueue.main.async {
          CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(ob), .commonModes)
        }
      }
    }
    var seen: Set<UInt64> = []
    var succeeded: Set<pid_t> = []
    var hiddenPIDs: Set<pid_t> = []
    var readsReady: Set<UInt64> = []
    var coolingPIDs: Set<pid_t> = []
    var deferredPIDs: Set<pid_t> = []
    var unresponsivePIDs: Set<pid_t> = []
    let budgetEnd = Date().addingTimeInterval(0.45)
    let ownedPIDs = Set(records.values.compactMap { $0.token == nil ? nil : $0.descriptor.pid })
    let orderNow = Date()
    let ordered = apps.sorted { a, b in
      let ao = ownedPIDs.contains(a.pid)
      let bo = ownedPIDs.contains(b.pid)
      if ao != bo { return ao && !bo }
      let af = axFail[a.pid] ?? 0
      let bf = axFail[b.pid] ?? 0
      if af != bf { return af < bf }
      let at = lastScannedAt[a.pid] ?? Date.distantPast
      let bt = lastScannedAt[b.pid] ?? Date.distantPast
      if at != bt { return at < bt }
      return a.pid < b.pid
    }
    for app in ordered {
      if app.hidden { hiddenPIDs.insert(app.pid) }
      let owned = ownedPIDs.contains(app.pid)
      let breaker = scanBackoff[app.pid] ?? AppScanBackoff()
      guard breaker.shouldScan(owned: owned, now: orderNow) else {
        coolingPIDs.insert(app.pid)
        unresponsivePIDs.insert(app.pid)
        continue
      }
      let remain = budgetEnd.timeIntervalSinceNow
      if remain <= 0, !owned {
        deferredPIDs.insert(app.pid)
        unresponsivePIDs.insert(app.pid)
        continue
      }
      let fails = axFail[app.pid] ?? 0
      let timeout = Float(fails >= 2 ? 0.04 : min(0.15, max(0.03, remain > 0 ? remain : 0.04)))
      let root = AXUIElementCreateApplication(app.pid)
      AXUIElementSetMessagingTimeout(root, timeout)
      observe(app, root)
      let started = Date()
      lastScannedAt[app.pid] = started
      metrics.appsScanned += 1
      guard let windows = axCopy(root, kAXWindowsAttribute) as? [AXUIElement] else {
        axFail[app.pid] = fails + 1
        var next = breaker
        next.noteFailure(at: Date())
        scanBackoff[app.pid] = next
        unresponsivePIDs.insert(app.pid)
        metrics.appsTimedOut += 1
        continue
      }
      if Date().timeIntervalSince(started) > Double(timeout) * 0.8 {
        axFail[app.pid] = fails + 1
        var next = breaker
        next.noteFailure(at: Date())
        scanBackoff[app.pid] = next
        metrics.appsTimedOut += 1
      } else {
        axFail[app.pid] = 0
        var next = breaker
        next.noteSuccess()
        scanBackoff[app.pid] = next
      }
      succeeded.insert(app.pid)
      // Native tab groups expose every tab as an AXWindow at the container's
      // frame. Only the window with an AXTabGroup child is the visible
      // container; marking the others keeps a two-tab Ghostty window from
      // looking like two same-frame peers and being dropped as ambiguous.
      for r in records.values where r.descriptor.pid == app.pid {
        r.tabSibling = false
      }
      var tabSiblings: [AXUIElement] = []
      if windows.count > 1 {
        let candidates = windows.map {
          TabCandidate(frame: axFrame($0), hasTabGroup: axHasTabGroupChild($0))
        }
        tabSiblings = tabSiblingIndices(candidates).sorted().map { windows[$0] }
      }
      for r in records.values where r.descriptor.pid == app.pid {
        if tabSiblings.contains(where: { CFEqual($0, r.element) }) {
          r.tabSibling = true
        }
      }
      // Display sleep/wake makes macOS destroy every AXUIElement and hand
      // out fresh ones for the same windows. A record whose element none
      // of this scan's windows matches is a candidate to re-identify by
      // AXIdentifier, or by title+frame, onto a replacement element below.
      let stale = records.values.filter { r in
        r.descriptor.pid == app.pid && !windows.contains { CFEqual($0, r.element) }
      }
      var adopted: Set<UInt64> = []
      for e in windows {
        if tabSiblings.contains(where: { CFEqual($0, e) }) { continue }
        let r: AXRecord
        if let old = records.values.first(where: {
          $0.descriptor.pid == app.pid && CFEqual($0.element, e)
        }) {
          // Keep the last good geometry: a busy app fails this read
          // during its own animations, and losing the record would
          // hand the window back to the engine as a new one.
          r = old
          refreshDescriptor(r, from: app)
          if let frame = axFrame(e) { r.frame = frame }
          r.title = axString(e, kAXTitleAttribute)
          if let ms = axMinSize(e) { r.minSize = ms }
        } else if let match = adoptStale(stale, adopted, e) {
          r = match
          adopted.insert(r.wid)
          refreshDescriptor(r, from: app)
          r.element = e
          AXUIElementSetMessagingTimeout(e, timeout)
          observeWindow(r)
          if let frame = axFrame(e) { r.frame = frame }
          r.title = axString(e, kAXTitleAttribute)
          if let ms = axMinSize(e) { r.minSize = ms }
          r.absent = 0
          r.orphanedAt = nil
          r.awaitsReplacement = false
          r.appAbsent = 0
          logMessage("Window \(r.wid) re-identified after its element was recycled")
        } else {
          // The desktop is an AXScrollArea in Finder's window list.
          // Recording it would inflate same-PID/same-frame peers and
          // drop the real Finder window from every snapshot.
          guard axListedAsWindow(e),
            let frame = axFrame(e)
          else { continue }
          r = AXRecord(nextID, e, app, frame)
          nextID += 1
          records[r.wid] = r
          r.minSize = axMinSize(e)
          AXUIElementSetMessagingTimeout(e, timeout)
          observeWindow(r)
        }
        seen.insert(r.wid)
        r.absent = 0
        r.orphanedAt = nil
        r.awaitsReplacement = false
        // Freeze eligibility while we own the window. It is hidden for
        // a non-visible workspace, and a minimized window reports
        // AXSubrole as AXDialog; recomputing would drop a standard
        // window that no longer looks settable, and the engine would
        // forget which workspace owns it.
        if r.token == nil {
          if let subrole = axCopy(e, kAXSubroleAttribute) as? String { r.subrole = subrole }
        }
        let eligibilityRead = windowEligibility(
          e, subrole: r.subrole, accessory: app.accessory)
        if r.token == nil {
          r.eligible = retainingWindowEligibility(previous: r.eligible,
            observed: eligibilityRead)
        }
        if scanReadiness(recordedLaunch: r.descriptor.launch, observedLaunch: app.launch,
          frameReadable: axFrame(e) != nil, eligibilityKnown: eligibilityRead != nil) {
          readsReady.insert(r.wid)
        }
      }
    }
    // A window this scan did not enumerate. Only an element the window
    // server has actually destroyed, or a dead process, proves it is gone:
    // a busy application returns an incomplete window list, and an
    // incomplete list is exactly what waking a display produces. Guessing
    // here costs the window its workspace, because the engine then treats
    // it as new and adopts it onto the workspace in view. A destroyed
    // element gets three scans for its replacement to be adopted above,
    // because display wake recycles every element at once and the
    // replacement may not appear in the very first scan after wake.
    for (id, r) in Array(records) where !seen.contains(id) {
      guard succeeded.contains(r.descriptor.pid) else { continue }
      r.absent += 1
      guard r.absent >= 2 else { continue }
      var value: CFTypeRef?
      let error = AXUIElementCopyAttributeValue(r.element, kAXRoleAttribute as CFString, &value)
      if error == .invalidUIElement {
        if r.orphanedAt == nil {
          r.orphanedAt = Date()
          r.awaitsReplacement = Date().timeIntervalSince(wokeAt) < orphanGrace
        }
        guard !awaitingReplacement(r) else { continue }
        logMessage("Window \(id) removed: its element was destroyed")
        releaseOwnership(r)
        records.removeValue(forKey: id)
      } else if processIsGone(r.descriptor.pid) {
        logMessage("Window \(id) removed: process \(r.descriptor.pid) exited")
        releaseOwnership(r)
        records.removeValue(forKey: id)
      }
    }
    let cgQuery = cgVisibleFrames()
    let cg = cgQuery ?? []
    let now = ProcessInfo.processInfo.systemUptime
    let all = Array(records.values)
    var minimizedReads: [UInt64: Bool] = [:]
    for r in all {
      // Asking an app that just timed out for each window's minimized state
      // re-opens the same stall. Use the last observation; an unresponsive
      // app's windows are retained but never actionable.
      guard succeeded.contains(r.descriptor.pid), !r.tabSibling else { continue }
      if let observed = axMinimizedRead(r.element) {
        minimizedReads[r.wid] = observed
        r.lastMinimized = observed
      }
    }
    let onScreenEligible = all.filter {
      $0.eligible && !$0.tabSibling && $0.lastMinimized != true
    }
    let byPid = Dictionary(grouping: onScreenEligible, by: { $0.descriptor.pid })
    var peerCount: [UInt64: Int] = [:]
    for group in byPid.values {
      for r in group { peerCount[r.wid] = group.filter { $0.frame.near(r.frame) }.count }
    }
    let cgByPid = Dictionary(grouping: cg, by: { $0.0 })
    var result: [WindowInfo] = []
    actionable = []
    var ambiguous = 0
    for r in all.sorted(by: { $0.wid < $1.wid }) {
      guard r.eligible, !r.tabSibling else { continue }
      // Cmd-H takes an application's windows out of management, but one
      // observation is not enough: on wake macOS reports applications
      // hidden that are not, and dropping them here costs the workspace.
      let listed = apps.contains {
        $0.pid == r.descriptor.pid && abs($0.launch - r.descriptor.launch) < 0.01
      }
      let hidden: Bool? = listed ? hiddenPIDs.contains(r.descriptor.pid) : nil
      r.hiddenGrace.observe(hidden.map { !$0 }, at: now)
      // A busy app can fail this read for one scan, typically during its
      // own minimize animation. Dropping the window from the snapshot
      // would make the engine treat it as closed and re-insert it on the
      // workspace in view, so fall back to the last observed state.
      // Dialogs often have no AXMinimized attribute at all; treat that as
      // not minimized rather than skipping the window every scan.
      let observedMini = minimizedReads[r.wid]
      guard let mini = r.lastMinimized else {
        r.visibilityReason = "ax-minimized-unknown"
        continue
      }
      let own = r.token != nil
      // On-screen association uses public PID + bounds only. Ambiguous
      // same-PID/same-frame windows across native Spaces are NOT touched.
      let peers = peerCount[r.wid] ?? 0
      let visible = (cgByPid[r.descriptor.pid] ?? []).filter { cgMatchesAXFrame(r.frame, $0.1) }
        .count
      // visible==0 is normally another Space. Chrome withholds CGWindow
      // metadata instead, and AX already hides its other-Space windows.
      let onScreen = cgOnScreenEvidence(querySucceeded: cgQuery != nil,
        visible: visible, peers: peers,
        omitsMetadata: bundleOmitsOnScreenCGWindows(r.descriptor.bundle))
      r.screenGrace.observe(onScreen, at: now)
      // The on-screen match decides which windows may be *admitted*: an
      // ambiguous one across native Spaces is never touched. Retaining a
      // window already in the snapshot is a different question, and a
      // window animating out of the Dock, or mid-move, is missing from
      // the window-server list for a scan or two. Dropping it there makes
      // the engine treat it as closed and re-insert it on the workspace in
      // view, which silently migrates windows on every workspace switch.
      let known = active.contains(r.wid)
      // An orphaned record keeps reporting its last state until its
      // replacement element is adopted or the grace runs out. Dropping
      // it from the snapshot would make the engine forget its workspace.
      let orphaned = awaitingReplacement(r)
      let decision = windowVisibilityDecision(known: known, owned: own, orphaned: orphaned,
        minimized: mini, hidden: hidden, onScreen: onScreen,
        readsReady: readsReady.contains(r.wid) && observedMini != nil,
        hiddenGrace: r.hiddenGrace, screenGrace: r.screenGrace, now: now,
        ambiguous: peers > 1 && visible < peers,
        unresponsive: unresponsivePIDs.contains(r.descriptor.pid))
      r.visibilityReason = decision.reason
      guard decision.retained else {
        if !mini && visible > 0 { ambiguous += 1 }
        continue
      }
      if decision.actionable { actionable.insert(r.wid) }
      // Keep WM-owned minimized windows; user-minimized windows are excluded.
      result.append(
        WindowInfo(
          wid: r.wid, pid: r.descriptor.pid, app: r.descriptor.name,
          bundle: r.descriptor.bundle, titleText: r.title,
          onDisplay: bestDisplay(for: r.frame, in: displays),
          frame: r.frame, minimized: mini, ownedHidden: own,
          subrole: r.subrole.isEmpty ? "AXStandardWindow" : r.subrole,
          accessory: r.descriptor.accessory))
    }
    if ambiguous > 0 && Date().timeIntervalSince(lastAmbiguityWarning) > 30 {
      logMessage(
        "Skipped \(ambiguous) ambiguous on-screen windows (same PID/frame). Use one native Space per display."
      )
      lastAmbiguityWarning = Date()
    }
    // Losing a known window is how a send-to-workspace turns into a window
    // stuck in the Dock: the engine treats it as closed. Leave a trace.
    let next = Set(result.map(\.wid))
    for id in active.subtracting(next) {
      guard let r = records[id] else {
        logMessage("Window \(id) left the snapshot: closed")
        continue
      }
      logMessage("Window \(id) left snapshot gen=\(generation) reason=\(r.eligible ? r.visibilityReason : "ineligible") "
        + "cg=\(cgQuery == nil ? "failed" : "ok") cgFrames=\(cg.count) "
        + "hiddenReads=\(r.hiddenGrace.negativeReads) hiddenMs=\(Int(r.hiddenGrace.negativeSeconds * 1000)) "
        + "cgReads=\(r.screenGrace.negativeReads) cgMs=\(Int(r.screenGrace.negativeSeconds * 1000)) "
        + "owned=\(r.token != nil) minimized=\(r.lastMinimized.map(String.init) ?? "unknown")")
    }
    for id in next.subtracting(active) {
      guard let r = records[id] else { continue }
      logMessage("Window \(id) \(r.hasEnteredSnapshot ? "reentered" : "entered") snapshot gen=\(generation) "
        + "reason=\(r.visibilityReason) cg=\(cgQuery == nil ? "failed" : "ok") cgFrames=\(cg.count) "
        + "hiddenReads=\(r.hiddenGrace.negativeReads) hiddenMs=\(Int(r.hiddenGrace.negativeSeconds * 1000)) "
        + "cgReads=\(r.screenGrace.negativeReads) cgMs=\(Int(r.screenGrace.negativeSeconds * 1000)) "
        + "actionable=\(actionable.contains(id))")
      r.hasEnteredSnapshot = true
    }
    active = next
    // Reconcile ownership only after this scan establishes safe mutation evidence.
    for r in records.values where actionable.contains(r.wid) && r.token != nil {
      guard let currentMini = axMinimizedRead(r.element) else { continue }
      if !r.wantsHidden, Date().timeIntervalSince(r.restoreRequestedAt) > 0.12 {
        if currentMini {
          r.restoreRequestedAt = Date()
          AXUIElementSetAttributeValue(r.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        } else if onAnyDisplay(r.frame) { releaseOwnership(r) }
      } else if r.wantsHidden, Date().timeIntervalSince(r.hideRequestedAt) > 0.5,
        r.lastMinimized != true {
        let origin = journal.entries.first(where: { $0.token == r.token })?.frame
        let stuck = origin.map {
          cgShowsOriginal(pid: r.descriptor.pid, original: $0, windows: cg, displays: displays)
        } ?? false
        if onAnyDisplay(r.frame) || stuck || parksByMinimizing(r.descriptor.bundle) {
          hide(r, cgStuckAtOrigin: stuck)
        }
      }
    }
    var focused: UInt64?
    var fullScreen = false
    if let window = focusedAXWindow() {
      fullScreen = axBool(window, "AXFullScreen")
      focused =
        all.first(where: {
          active.contains($0.wid) && $0.lastMinimized != true && axSameWindow($0.element, window)
        })?.wid
    }
    // The helper's own border panels sit at application levels too.
    let me = ProcessInfo.processInfo.processIdentifier
    let stack = observedStack(cg.filter { $0.0 != me }, windows: result)
    if !fullScreen { raiseCoveredFloats(focused: focused, stack: stack) }
    metrics.appsDeferred = deferredPIDs.count
    metrics.appsCoolingDown = coolingPIDs.count
    metrics.durationMs = Int(Date().timeIntervalSince(scanStarted) * 1000)
    if (metrics.durationMs > 450 || metrics.appsTimedOut > 0
      || !coolingPIDs.isEmpty), Date().timeIntervalSince(lastScanMetricsLog) > 10
    {
      lastScanMetricsLog = Date()
      logMessage(
        "Scan budget gen=\(generation) ms=\(metrics.durationMs) apps=\(metrics.appsScanned) "
          + "deferred=\(metrics.appsDeferred) cooling=\(metrics.appsCoolingDown) "
          + "timeouts=\(metrics.appsTimedOut)")
    }
    return ScanResult(
      windows: result, focused: focused, nativeFullScreen: fullScreen, stack: stack,
      metrics: metrics)
  }
  private func windowAt(_ point: CGPoint) -> AXRecord? {
    let system = AXUIElementCreateSystemWide()
    var hit: AXUIElement?
    guard
      AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
      let first = hit
    else { return nil }
    // A menu can name its owning window through AXWindow. Do not walk through
    // that transient surface and accidentally focus/raise the owner behind it.
    if pointerFocusIsTransientRole(axString(first, kAXRoleAttribute)) { return nil }
    var candidates: [AXUIElement] = [first]
    if let w = axElement(first, kAXWindowAttribute) { candidates.append(w) }
    var current = first
    for _ in 0..<8 {
      guard let parent = axElement(current, kAXParentAttribute) else { break }
      if pointerFocusIsTransientRole(axString(parent, kAXRoleAttribute)) { return nil }
      candidates.append(parent)
      current = parent
    }
    for e in candidates {
      if let r = records.values.first(where: {
        actionable.contains($0.wid) && $0.eligible && CFEqual($0.element, e)
      }) {
        return r
      }
      // Do not traverse an unmanaged popup window to its managed owner.
      if axString(e, kAXRoleAttribute) == kAXWindowRole { return nil }
    }
    return nil
  }
  func beginPointerDrag(at point: CGPoint, mode: PointerMode) -> UInt64? {
    guard mode != .raise, pointerDrag == nil, let r = windowAt(point),
       axMinimizedRead(r.element) == false,
      let frame = axFrame(r.element)
    else { return nil }
    if let ms = axMinSize(r.element) { r.minSize = ms }
    pointerDrag = PointerDragSession(wid: r.wid, mode: mode, start: point, initial: frame)
    return r.wid
  }
  @discardableResult
  func updatePointerDrag(to point: CGPoint) -> (UInt64, Rect)? {
    guard let drag = pointerDrag, actionable.contains(drag.wid), let r = records[drag.wid] else {
      pointerDrag = nil
      return nil
    }
    let dx = Int((point.x - drag.start.x).rounded())
    let dy = Int((point.y - drag.start.y).rounded())
    let target: Rect
    switch drag.mode {
    case .move:
      target = Rect(
        x: drag.initial.x + dx, y: drag.initial.y + dy,
        width: drag.initial.width, height: drag.initial.height)
    case .resize:
      let floor = resizeFloor(r.minSize)
      target = Rect(
        x: drag.initial.x, y: drag.initial.y,
        width: max(floor.0, drag.initial.width + dx), height: max(floor.1, drag.initial.height + dy)
      )
    case .raise:
      return nil
    }
    move(r, target)
    if let observed = axFrame(r.element) { r.frame = observed }
    relay.notify()
    return (r.wid, r.frame)
  }
  @discardableResult
  func endPointerDrag(at point: CGPoint) -> (UInt64, Rect)? {
    guard let drag = pointerDrag else { return nil }
    let moved = updatePointerDrag(to: point)
    pointerDrag = nil
    relay.notify()
    return moved ?? records[drag.wid].map { (drag.wid, $0.frame) }
  }
  func cancelPointerDrag() { pointerDrag = nil }
  func fingerprints() -> [WindowPrint] {
    records.values.map {
      WindowPrint(
        wid: $0.wid, pid: $0.descriptor.pid, launch: $0.descriptor.launch,
        bundle: $0.descriptor.bundle, identifier: $0.identifier, title: $0.title, frame: $0.frame)
    }
  }
  // The record for the window AX now calls focused, when it is one of ours.
  // axSameWindow, not CFEqual: it walks a text area up to the window that
  // holds it, which is what emacs-mac reports as focused.
  private func focusedRecord() -> AXRecord? {
    guard let window = focusedAXWindow() else { return nil }
    return records.values.first { axSameWindow($0.element, window) }
  }
  func observedFocus() -> UInt64? { focusedRecord()?.wid }

  // Menus may leave AXFocusedWindow pointing at their owner. Inspect the
  // focused UI element as well before retrying a window-focus request.
  private func transientOwnsFocus() -> Bool {
    guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.15)
    if let element = axElement(app, kAXFocusedUIElementAttribute) {
      var current = element
      for _ in 0..<8 {
        if pointerFocusIsTransientRole(axString(current, kAXRoleAttribute)) { return true }
        guard let parent = axElement(current, kAXParentAttribute) else { break }
        current = parent
      }
    }
    // A focused, unmanaged window (e.g. an extension popup) is user takeover,
    // not evidence that the previous managed window needs raising again.
    if let window = focusedAXWindow() {
      return !records.values.contains { active.contains($0.wid) && axSameWindow($0.element, window) }
    }
    return false
  }

  // A window on another workspace is parked against the bottom-right corner
  // of the display arrangement, keeping its size. Unlike AXMinimized this
  // involves no Dock, no animation and no app that may refuse, and the window
  // is brought back by the ordinary placement that follows.
  private func parkingSpot(for r: AXRecord) -> Rect {
    parkOrigin(
      screens: displays.compactMap { Rect(CGDisplayBounds(CGDirectDisplayID($0.display))) },
      window: r.frame)
  }
  private func onAnyDisplay(_ rect: Rect) -> Bool { !parkedOffDisplay(rect, displays) }
  private func show(_ r: AXRecord) {
    guard r.token != nil else { return }  // Never restore a user's hiding.
    guard let mini = axMinimizedRead(r.element) else { return }
    r.wantsHidden = false
    r.restoreRequestedAt = Date()
    // A window we had to minimize because parking was refused.
    if mini {
      let error = AXUIElementSetAttributeValue(
        r.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
      if error != .success { logMessage("Restore failed for window \(r.wid): \(error.rawValue)") }
    }
    // Placement puts it back on screen; ownership ends when a scan agrees.
  }
  private func hide(_ r: AXRecord, cgStuckAtOrigin: Bool = false) {
    let minimizeOnly = parksByMinimizing(r.descriptor.bundle)
    guard let axMini = axMinimizedRead(r.element) else { return }
    if axMini, !cgStuckAtOrigin {
      if r.token == nil { logMessage("Hide skipped for window \(r.wid): user-minimized") }
      return
    }
    // Already parked: the clamped position never equals the requested one,
    // so compare visibility rather than coordinates or we rewrite it on
    // every scan. Finder never parks; a corner sliver of any other app is
    // a successful hide. Do not require an AX frame to minimize Finder.
    if !minimizeOnly {
      guard let actual = axFrame(r.element) else { return }
      if r.token != nil, !onAnyDisplay(actual), !cgStuckAtOrigin {
        r.wantsHidden = true
        return
      }
    }
    guard r.descriptor.launch > 0 else {
      logMessage(
        "Hide skipped for window \(r.wid): \(r.descriptor.name) has no "
          + "readable process start time, so the hide cannot be journaled")
      return
    }
    if r.token == nil {
      let entry = r.recovery
      do {
        try journal.add(entry)
        r.token = entry.token
      } catch {
        logMessage("Refusing to hide without a durable recovery record: \(error)")
        return
      }
    }
    r.wantsHidden = true
    r.hideRequestedAt = Date()
    if !minimizeOnly {
      let spot = parkingSpot(for: r)
      var point = CGPoint(x: spot.x, y: spot.y)
      if let pv = AXValueCreate(.cgPoint, &point) {
        withImmediateAXGeometry(r.descriptor.pid) { () -> Void in
          AXUIElementSetAttributeValue(r.element, kAXPositionAttribute as CFString, pv)
        }
      }
      if let observed = axFrame(r.element) { r.frame = observed }
      guard onAnyDisplay(r.frame) || cgStuckAtOrigin else { return }
    }
    let error = AXUIElementSetAttributeValue(
      r.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    if error != .success {
      logMessage("Window \(r.wid) refuses to be parked or minimized")
    }
  }
  private func move(_ r: AXRecord, _ target: Rect) {
    guard axMinimizedRead(r.element) == false, let actual = axFrame(r.element)
    else { return }
    // Already where the plan asks: nothing to write, and a later divergence
    // must not inherit a backoff computed for a frame it has since left.
    if actual.near(target) {
      r.backoff.reset()
      return
    }
    let now = Date()
    // A clamped window never reaches the target, so an identical, unmoved
    // request waits longer each time instead of re-writing every scan. A
    // changed target or observed frame is real input and attempts at once.
    guard r.backoff.shouldAttempt(target: target, observed: actual, now: now) else { return }
    r.backoff.note(target: target, observed: actual, at: now)
    var size = CGSize(width: target.width, height: target.height)
    var point = CGPoint(x: target.x, y: target.y)
    guard let sv = AXValueCreate(.cgSize, &size), let pv = AXValueCreate(.cgPoint, &point) else {
      return
    }
    // Size-position-size handles many cross-display AppKit constraint cases.
    let (e1, e2, e3, observed) = withImmediateAXGeometry(r.descriptor.pid) {
      () -> (AXError, AXError, AXError, Rect?) in
      let e1 = AXUIElementSetAttributeValue(r.element, kAXSizeAttribute as CFString, sv)
      let e2 = AXUIElementSetAttributeValue(r.element, kAXPositionAttribute as CFString, pv)
      let e3 = AXUIElementSetAttributeValue(r.element, kAXSizeAttribute as CFString, sv)
      return (e1, e2, e3, axFrame(r.element))
    }
    // The log shares the backoff: the first write for a target/frame pair
    // reports the constraint, and an unchanged stuck window stays quiet until
    // the next due attempt rather than spamming once per scan.
    if r.backoff.attempts == 1, let observed = observed, !observed.near(target, tolerance: 4) {
      logMessage(
        "Window \(r.wid) constrained requested=\(target) actual=\(observed), AX=\(e1.rawValue)/\(e2.rawValue)/\(e3.rawValue)"
      )
    }
  }
  @discardableResult
  func apply(_ p: Plan) throws -> Bool {
    guard p.epoch == activeEpoch, p.generation == latestGeneration else {
      if !p.hide.isEmpty {
        logMessage(
          "Dropped plan gen=\(p.generation)/\(latestGeneration) "
            + "epoch=\(p.epoch)/\(activeEpoch) hide=\(p.hide)")
      }
      return false
    }
    try PlanSafety.validate(p, active: active)
    floatOrder = p.floating ?? []
    // Restore and place destinations before hiding sources. Only deliberate
    // policy focus requests may activate an app; ordinary scans never do.
    let dragging = pointerDrag?.wid
    for placement in p.frames {
      guard placement.wid != dragging, actionable.contains(placement.wid),
        let r = records[placement.wid] else { continue }
      show(r)
      move(r, placement.frame)
    }
    for id in p.hide {
      guard id != dragging else {
        logMessage("Hide skipped for window \(id): drag")
        continue
      }
      guard actionable.contains(id) else { continue }
      guard let r = records[id] else {
        logMessage("Hide skipped for window \(id): no record")
        continue
      }
      hide(r)
    }
    pendingAck = nil
    if let action = p.action {
      let shown = Set(p.frames.map(\.wid))
      let current = focusedRecord()?.wid
      if actionFirstSeen[action] == nil {
        actionFirstSeen[action] = Date()
        if let current = current { actionFrom[action] = current }
      }
      let first = actionFirstSeen[action] ?? Date()
      let limit = Double(max(1, p.focusForMs ?? 400)) / 1000
      let expired = Date().timeIntervalSince(first) >= limit
      let from = actionFrom[action]
      if let id = p.focus, actionable.contains(id), let r = records[id],
        axMinimizedRead(r.element) == false
      {
        // M-j/k leaves the previous window on screen. AX still naming it
        // is the request in flight, not the user taking over.
        let userTook = transientOwnsFocus() ||
          current.map { w in
            w != id && shown.contains(w) && from.map { $0 != w } == true
          } == true
        if !expired && !userTook {
          if let app = NSRunningApplication(processIdentifier: r.descriptor.pid) {
            // Deliberate hotkey focus only; never activateAllWindows.
            app.activate(options: [.activateIgnoringOtherApps])
          }
          let app = AXUIElementCreateApplication(r.descriptor.pid)
          AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, r.element)
          AXUIElementSetAttributeValue(r.element, kAXMainAttribute as CFString, kCFBooleanTrue)
          AXUIElementPerformAction(r.element, kAXRaiseAction as CFString)
          raiseFloats(
            floatsToRaise(after: id, floating: floatOrder, pids: floatPids()), keeping: r)
        }
        let observed = observedFocus() ?? current
        if observed == id || userTook {
          pendingAck = (action, observed, false)
          actionFirstSeen.removeValue(forKey: action)
          actionFrom.removeValue(forKey: action)
        }
      } else if expired {
        pendingAck = (action, current, true)
        actionFirstSeen.removeValue(forKey: action)
        actionFrom.removeValue(forKey: action)
      }
      actionFirstSeen = actionFirstSeen.filter { $0.key > action - 16 }
      actionFrom = actionFrom.filter { $0.key > action - 16 }
    }
    if let screen = p.screen { followScreen(screen) }
    return true
  }
  private func floatPids() -> [UInt64: Int32] {
    records.mapValues { $0.descriptor.pid }
  }
  // AXRaise on a sibling orders it within the app without activating it. It
  // may still move the app's main or focused window, so focus is put back
  // afterwards, without a raise that would cover the floats again.
  private func raiseFloats(_ ids: [UInt64], keeping r: AXRecord) {
    let floats = ids.compactMap { actionable.contains($0) ? records[$0] : nil }
    guard !floats.isEmpty else { return }
    for f in floats { AXUIElementPerformAction(f.element, kAXRaiseAction as CFString) }
    if let now = focusedAXWindow(), axSameWindow(r.element, now) { return }
    let app = AXUIElementCreateApplication(r.descriptor.pid)
    AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, r.element)
    AXUIElementSetAttributeValue(r.element, kAXMainAttribute as CFString, kCFBooleanTrue)
  }
  // The user clicked a tiled window: bring its app's covered floats back in
  // front, once, judged from the observed stack.
  private func raiseCoveredFloats(focused: UInt64?, stack: [StackEntry]) {
    defer { lastScanFocus = focused }
    guard let id = focused, id != lastScanFocus, pointerDrag == nil, !floatOrder.isEmpty,
      let r = records[id], actionable.contains(id)
    else { return }
    raiseFloats(
      floatsCovered(by: id, floating: floatOrder, pids: floatPids(), stack: stack), keeping: r)
  }
  func takeAck() -> (action: Int, focused: UInt64?, expired: Bool)? {
    defer { pendingAck = nil }
    return pendingAck.map { ($0.0, $0.1, $0.2) }
  }
  // The current screen is a policy idea with no macOS counterpart: with no
  // window to focus on the display it moved to, nothing would tell the system
  // or the user that it changed. Move the pointer instead, as upstream's
  // UpdatePointer does, and only when it is on another display, so ordinary
  // plans and the user's own pointer are left alone.
  private func followScreen(_ display: Int) {
    defer { pointerScreen = display }
    guard pointerScreen != -1, display != pointerScreen,
      let d = displays.first(where: { $0.display == display }),
      let here = CGEvent(source: nil)?.location
    else { return }
    let r = d.usable
    let inside =
      here.x >= CGFloat(r.x) && here.x < CGFloat(r.x + r.width)
      && here.y >= CGFloat(r.y) && here.y < CGFloat(r.y + r.height)
    guard !inside else { return }
    CGWarpMouseCursorPosition(
      CGPoint(
        x: CGFloat(r.x + r.width / 2),
        y: CGFloat(r.y + r.height / 2)))
  }
  // Resolve the actual AX surface under the pointer, not a filtered list of
  // application windows that can omit the popup above them.
  func window(at point: CGPoint) -> UInt64? {
    // The filtered CG application-window list omits menus and popovers, so
    // using it here clicks through them to their owner. AX resolves the actual
    // topmost element, including Chrome's windows absent from that CG list.
    // An unavailable or unmanaged hit is not permission to focus behind it.
    guard let r = windowAt(point), r.token == nil else { return nil }
    return r.wid
  }
  func close(_ id: UInt64) {
    guard let r = records[id], actionable.contains(id),
      let button = axElement(r.element, kAXCloseButtonAttribute)
    else { return }
    let e = AXUIElementPerformAction(button, kAXPressAction as CFString)
    if e != .success { logMessage("Close failed: \(e.rawValue)") }
  }
  // Put every owned window back where it was before we hid it. The journal
  // holds that frame, so this works for parked and minimized windows alike.
  private func restore(_ r: AXRecord) {
    show(r)
    r.backoff.reset()  // Never let the move backoff skip a restore.
    guard let entry = journal.entries.first(where: { $0.token == r.token }) else { return }
    move(r, entry.frame)
  }
  func restoreAll() {
    let owned = records.values.filter { $0.token != nil }
    for r in owned { restore(r) }
    if !owned.isEmpty { Thread.sleep(forTimeInterval: 0.15) }
    // No further scan will run here, so confirm and release in place.
    for r in owned where r.token != nil {
      restore(r)
      if let observed = axFrame(r.element), onAnyDisplay(observed),
        axBoolean(r.element, kAXMinimizedAttribute) == false
      {
        releaseOwnership(r)
      }
    }
  }
  func invalidate(epoch: Int) {
    pointerDrag = nil
    activeEpoch = epoch
    latestGeneration = -1
    active = []
    actionable = []
    actionFirstSeen = [:]
    actionFrom = [:]
    pendingAck = nil
    // A new epoch is real input: retry each window immediately.
    for r in records.values { r.backoff.reset() }
  }

  // A new bridge has no valid old AX handles. Reattach only by an unambiguous
  // process-instance + AXIdentifier, or process-instance + title + frame match.
  // Entries whose application instance ended can be safely discarded.
  func recover(apps: [AppDescriptor], displays: [DisplayInfo]) {
    self.displays = displays
    for entry in journal.entries {
      guard
        let app = apps.first(where: {
          $0.pid == entry.pid && $0.bundle == entry.bundle && entry.launch > 0
            && abs($0.launch - entry.launch) < 0.01
        })
      else {
        try? journal.remove(entry.token)
        continue
      }
      let root = AXUIElementCreateApplication(app.pid)
      AXUIElementSetMessagingTimeout(root, 0.15)
      guard let windows = axCopy(root, kAXWindowsAttribute) as? [AXUIElement] else { continue }
      let matches = windows.filter { e in
        if !entry.identifier.isEmpty {
          return axString(e, kAXIdentifierAttribute) == entry.identifier
        }
        // Same title, and either still where it was or parked off every
        // display — a window we hid cannot be at its journaled frame.
        guard axString(e, kAXTitleAttribute) == entry.title,
          let frame = axFrame(e)
        else { return false }
        return frame.near(entry.frame) || !onAnyDisplay(frame)
      }
      guard matches.count == 1, let e = matches.first, let frame = axFrame(e) else {
        logMessage(
          "Recovery left ambiguous/unavailable window for PID \(entry.pid); journal retained.")
        continue
      }
      let r = AXRecord(nextID, e, app, frame)
      nextID += 1
      r.token = entry.token
      records[r.wid] = r
      restore(r)
    }
    restoreAll()
  }
}

func runAXSelfTest() -> AXSelfTestReport {
  var report = AXSelfTestReport(
    accessibilityTrusted: AXIsProcessTrusted(), focusedWindowFound: false,
    standardWindow: false, positionSettable: false, sizeSettable: false, minimizedSettable: false,
    frameReadable: false, sameFrameWriteSucceeded: false, readBackMatched: false,
    onScreenCorrelation: false,
    nativeFullScreen: false, pid: nil, title: nil, frame: nil, errors: [])
  guard report.accessibilityTrusted else {
    report.errors.append("Accessibility permission is not granted")
    return report
  }
  guard let window = focusedAXWindow() else {
    report.errors.append("No focused Accessibility window")
    return report
  }
  report.focusedWindowFound = true
  var pid: pid_t = 0
  if AXUIElementGetPid(window, &pid) == .success { report.pid = pid }
  report.title = axString(window, kAXTitleAttribute)
  report.standardWindow =
    axString(window, kAXRoleAttribute) == kAXWindowRole
    && axString(window, kAXSubroleAttribute) == kAXStandardWindowSubrole
  report.positionSettable = axSettable(window, kAXPositionAttribute)
  report.sizeSettable = axSettable(window, kAXSizeAttribute)
  report.minimizedSettable = axSettable(window, kAXMinimizedAttribute)
  report.nativeFullScreen = axBool(window, "AXFullScreen")
  guard let frame = axFrame(window) else {
    report.errors.append("Focused window frame is unreadable")
    return report
  }
  report.frameReadable = true
  report.frame = frame
  var point = CGPoint(x: frame.x, y: frame.y)
  var size = CGSize(width: frame.width, height: frame.height)
  if report.positionSettable && report.sizeSettable,
    let pv = AXValueCreate(.cgPoint, &point), let sv = AXValueCreate(.cgSize, &size)
  {
    let (p1, s1) = withImmediateAXGeometry(report.pid ?? 0) {
      (
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pv),
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sv)
      )
    }
    report.sameFrameWriteSucceeded = (p1 == .success && s1 == .success)
    if !report.sameFrameWriteSucceeded {
      report.errors.append("Same-frame AX write failed: \(p1.rawValue)/\(s1.rawValue)")
    }
    if let observed = axFrame(window) {
      report.readBackMatched = observed.near(frame, tolerance: 4)
    }
  }
  if let pid = report.pid {
    report.onScreenCorrelation = cgVisibleFrames()?
      .contains { $0.0 == pid && $0.1.near(frame, tolerance: 4) } ?? false
  }
  if !report.standardWindow { report.errors.append("Focused element is not a standard AX window") }
  if !report.positionSettable { report.errors.append("AXPosition is not settable") }
  if !report.sizeSettable { report.errors.append("AXSize is not settable") }
  if !report.minimizedSettable { report.errors.append("AXMinimized is not settable") }
  if !report.readBackMatched { report.errors.append("AX frame read-back did not match") }
  if !report.onScreenCorrelation {
    report.errors.append("Public CGWindow PID/frame correlation was not found")
  }
  if report.nativeFullScreen { report.errors.append("Focused window is in native full-screen") }
  return report
}
#endif
