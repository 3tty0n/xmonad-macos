#if os(macOS)
import Foundation
import CoreGraphics

private struct PhysicalKey: Hashable {
  var code: UInt16
  var mask: Int
}

// macOS window and space shortcuts that move windows behind the tiler's back.
// Swallowed only while tiling is active and the menu toggle is on; nothing is
// written to system preferences, so quitting restores every shortcut.
private let systemShortcuts: Set<PhysicalKey> = {
  let tab: UInt16 = 48
  let backtick: UInt16 = 50
  let h: UInt16 = 4
  let m: UInt16 = 46
  let arrows: [UInt16] = [123, 124, 125, 126]
  var set: Set<PhysicalKey> = [
    PhysicalKey(code: tab, mask: 64), PhysicalKey(code: tab, mask: 65),  // app switcher
    PhysicalKey(code: backtick, mask: 64), PhysicalKey(code: backtick, mask: 65),  // window cycling
    PhysicalKey(code: h, mask: 64), PhysicalKey(code: m, mask: 64),
  ]  // hide, minimize
  for a in arrows {  // Mission Control
    set.insert(PhysicalKey(code: a, mask: 4))
    set.insert(PhysicalKey(code: a, mask: 5))
  }
  return set
}()
final class KeyboardTap {
  private let lock = NSLock()
  private var bindings: [PhysicalKey: KeyBinding] = [:]
  private var swallowed: Set<UInt16> = []
  private var enabled = false
  private var suppressSystem = false
  private var logKeys = false
  private var grabUntil: Date?
  private lazy var tap = EventTap(
    name: "XMonadMac keyboard event tap",
    failure:
      "Keyboard event tap failed. Check Accessibility/Input Monitoring permissions, then restart.",
    types: [.keyDown, .keyUp],
    handler: { [weak self] type, event in
      guard let self = self else { return Unmanaged.passUnretained(event) }
      return self.handle(type, event)
    })
  var onKey: (((KeyBinding, Bool)?) -> Void)?  // (key, grabbed); nil = emergency pause
  var onReady: (() -> Void)?
  var onFailure: ((String) -> Void)?
  var onDebug: ((String) -> Void)?
  func configure(_ keys: [KeyBinding]) throws {
    var next: [PhysicalKey: KeyBinding] = [:]
    for k in keys {
      try validateBinding(k)
      let p = PhysicalKey(code: keyCodeForSym[k.sym]!, mask: k.mask)
      guard next[p] == nil else { throw WireError.invalid("Duplicate physical binding") }
      next[p] = k
    }
    lock.lock()
    bindings = next
    grabUntil = nil
    lock.unlock()
  }
  // A submap is waiting: the next stroke goes to the engine whatever it is.
  // One stroke only, and a user who walks away gets the keyboard back.
  func grabNext(for seconds: TimeInterval) {
    lock.lock()
    grabUntil = Date() + seconds
    lock.unlock()
  }
  func setEnabled(_ value: Bool) {
    lock.lock()
    enabled = value
    if !value { grabUntil = nil }
    lock.unlock()
  }
  func setSuppressSystemShortcuts(_ value: Bool) {
    lock.lock()
    suppressSystem = value
    lock.unlock()
  }
  func setLogKeys(_ value: Bool) {
    lock.lock()
    logKeys = value
    lock.unlock()
  }
  func start() {
    tap.onReady = { [weak self] in self?.onReady?() }
    tap.onFailure = { [weak self] problem in self?.onFailure?(problem) }
    tap.start()
  }
  func stop() {
    lock.lock()
    enabled = false
    lock.unlock()
    tap.stop()
  }
  private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let mask = modifierBits(event.flags)
    lock.lock()
    if type == .keyUp {
      let consumed = swallowed.remove(code) != nil
      lock.unlock()
      return consumed ? nil : Unmanaged.passUnretained(event)
    }
    let emergency = code == 53 && mask == (4 | 8 | 64)
    let grabbed = enabled && !emergency && (grabUntil.map { $0 > Date() } ?? false)
    if !emergency { grabUntil = nil }
    let key =
      grabbed
      ? KeyBinding(mask: mask, sym: symForKeyCode[code] ?? 0)
      : bindings[PhysicalKey(code: code, mask: mask)]
    let suppressed =
      enabled && key == nil && suppressSystem
      && systemShortcuts.contains(PhysicalKey(code: code, mask: mask))
    let consume = emergency || (enabled && key != nil) || suppressed
    if consume { swallowed.insert(code) }
    // Opt-in diagnosis for "my modifier does nothing": modified keys only.
    let report =
      (logKeys && mask != 0)
      ? "key code=\(code) mask=\(mask) bound=\(key != nil) grabbed=\(grabbed) consumed=\(consume) tiling=\(enabled)"
      : nil
    lock.unlock()
    if let report = report { DispatchQueue.main.async { [weak self] in self?.onDebug?(report) } }
    if consume {
      if emergency || key != nil {
        DispatchQueue.main.async { [weak self] in
          self?.onKey?(emergency ? nil : key.map { ($0, grabbed) })
        }
      }
      return nil
    }
    return Unmanaged.passUnretained(event)
  }
}
#endif
