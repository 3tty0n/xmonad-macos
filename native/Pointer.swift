#if os(macOS)
import Foundation
import CoreGraphics

enum PointerPhase { case begin, drag, end }

final class PointerTap {
  private let lock = NSLock()
  private var bindings: [MouseBind] = []
  private var enabled = false
  private var activeMode: PointerMode?
  private var activeButton = 0
  private lazy var tap = EventTap(
    name: "XMonadMac pointer event tap",
    failure:
      "Pointer event tap failed. Check Accessibility/Input Monitoring permissions, then restart.",
    types: [
      .leftMouseDown, .leftMouseDragged, .leftMouseUp,
      .rightMouseDown, .rightMouseDragged, .rightMouseUp,
      .otherMouseDown, .otherMouseDragged, .otherMouseUp,
      .mouseMoved,
    ],
    handler: { [weak self] type, event in
      guard let self = self else { return Unmanaged.passUnretained(event) }
      return self.handle(type, event)
    })
  private var hoverEnabled = false
  private var lastHover = Date.distantPast
  var onPointer: ((PointerMode, PointerPhase, CGPoint) -> Void)?
  // Reported at most every 80ms, and never during a mod-drag.
  var onHover: ((CGPoint) -> Void)?
  var onReady: (() -> Void)?
  var onFailure: ((String) -> Void)?

  func configure(bindings: [MouseBind]) throws {
    try validateMouseBindings(bindings)
    lock.lock()
    self.bindings = bindings
    lock.unlock()
  }
  func setEnabled(_ value: Bool) {
    lock.lock()
    enabled = value
    if !value {
      activeMode = nil
      activeButton = 0
    }
    lock.unlock()
  }
  func cancelGesture() {
    lock.lock()
    activeMode = nil
    activeButton = 0
    lock.unlock()
  }
  func setHover(_ value: Bool) {
    lock.lock()
    hoverEnabled = value
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
    activeMode = nil
    lock.unlock()
    tap.stop()
  }
  private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    let location = event.location
    if type == .mouseMoved {
      lock.lock()
      let report =
        hoverEnabled && activeMode == nil
        && Date().timeIntervalSince(lastHover) > 0.08
      if report { lastHover = Date() }
      lock.unlock()
      if report { DispatchQueue.main.async { [weak self] in self?.onHover?(location) } }
      return Unmanaged.passUnretained(event)
    }
    lock.lock()
    let isEnabled = enabled
    let binds = bindings
    let down = type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
    let up = type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp
    let button: Int
    switch type {
    case .leftMouseDown, .leftMouseDragged, .leftMouseUp: button = 1
    case .rightMouseDown, .rightMouseDragged, .rightMouseUp: button = 3
    default: button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
    }
    if down, isEnabled,
      let bind = binds.first(where: { $0.mask == modifierBits(event.flags) && $0.button == button })
    {
      activeMode = bind.action
      activeButton = button
    }
    let active = activeMode
    let matching = active != nil && button == activeButton
    if up {
      activeMode = nil
      activeButton = 0
    }
    lock.unlock()
    guard matching, let active = active else { return Unmanaged.passUnretained(event) }
    if active == .raise {
      if down {
        DispatchQueue.main.async { [weak self] in self?.onPointer?(.raise, .begin, location) }
      }
      return nil
    }
    let phase: PointerPhase = down ? .begin : (up ? .end : .drag)
    DispatchQueue.main.async { [weak self] in self?.onPointer?(active, phase, location) }
    return nil
  }
}
#endif
