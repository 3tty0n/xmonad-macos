#if os(macOS)
import Foundation
import CoreGraphics

// Modifier bits exactly as the Haskell side names them: shift 1, control 4,
// option 8, command 64. Both taps encode the mask the engine's keymap and
// mouse bindings are written against, so it is defined once here.
func modifierBits(_ flags: CGEventFlags) -> Int {
  (flags.contains(.maskShift) ? 1 : 0) | (flags.contains(.maskControl) ? 4 : 0)
    | (flags.contains(.maskAlternate) ? 8 : 0) | (flags.contains(.maskCommand) ? 64 : 0)
}

// One CGEvent tap and the thread that runs it. The caller keeps the policy:
// which events it wants and what to do with each one. The tap itself only
// owns the lifecycle, so the keyboard and the pointer cannot drift apart.
final class EventTap {
  var onReady: (() -> Void)?
  var onFailure: ((String) -> Void)?
  private let name: String, failureMessage: String, mask: CGEventMask
  private let handler: (CGEventType, CGEvent) -> Unmanaged<CGEvent>?
  private let lock = NSLock()
  private var port: CFMachPort?
  private var runLoop: CFRunLoop?
  private var thread: Thread?

  init(
    name: String, failure: String, types: [CGEventType],
    handler: @escaping (CGEventType, CGEvent) -> Unmanaged<CGEvent>?
  ) {
    self.name = name
    failureMessage = failure
    self.handler = handler
    mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
  }
  func start() {
    guard thread == nil else { return }
    let t = Thread { [weak self] in
      guard let self = self else { return }
      let context = Unmanaged.passUnretained(self).toOpaque()
      guard
        let tap = CGEvent.tapCreate(
          tap: .cgSessionEventTap, place: .headInsertEventTap,
          options: .defaultTap, eventsOfInterest: self.mask,
          callback: { _, type, event, context in
            guard let context = context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<EventTap>.fromOpaque(context).takeUnretainedValue()
              .dispatch(type, event)
          }, userInfo: context)
      else {
        DispatchQueue.main.async { self.onFailure?(self.failureMessage) }
        return
      }
      let loop = CFRunLoopGetCurrent()
      self.lock.lock()
      self.port = tap
      self.runLoop = loop
      self.lock.unlock()
      let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
      CFRunLoopAddSource(loop, source, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)
      DispatchQueue.main.async { self.onReady?() }
      CFRunLoopRun()
      CFMachPortInvalidate(tap)
    }
    t.name = name
    thread = t
    t.start()
  }
  func stop() {
    lock.lock()
    let p = port
    let r = runLoop
    lock.unlock()
    if let p = p { CFMachPortInvalidate(p) }
    if let r = r { CFRunLoopStop(r) }
  }
  // macOS disables a tap that was too slow to answer, and waits to be told to
  // carry on. Losing the tap silently would lose the keyboard or the pointer
  // for the rest of the session.
  private func dispatch(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      lock.lock()
      let p = port
      lock.unlock()
      if let p = p { CGEvent.tapEnable(tap: p, enable: true) }
      return Unmanaged.passUnretained(event)
    }
    return handler(type, event)
  }
}
#endif
