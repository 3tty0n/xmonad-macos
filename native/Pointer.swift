#if os(macOS)
import Foundation
import CoreGraphics

enum PointerPhase { case begin, drag, end }

final class PointerTap {
    private let lock = NSLock()
    private var bindings: [MouseBind]=[]
    private var enabled = false
    private var activeMode: PointerMode?
    private var activeButton=0
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var hoverEnabled=false
    private var lastHover=Date.distantPast
    var onPointer: ((PointerMode, PointerPhase, CGPoint) -> Void)?
    // Reported at most every 80ms, and never during a mod-drag.
    var onHover: ((CGPoint) -> Void)?
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?

    func configure(bindings: [MouseBind]) throws {
        try validateMouseBindings(bindings)
        lock.lock(); self.bindings = bindings; lock.unlock()
    }
    func setEnabled(_ value: Bool) {
        lock.lock(); enabled=value
        if !value { activeMode=nil; activeButton=0 }
        lock.unlock()
    }
    func cancelGesture() { lock.lock(); activeMode=nil; activeButton=0; lock.unlock() }
    func setHover(_ value: Bool) { lock.lock(); hoverEnabled=value; lock.unlock() }
    func start() {
        guard thread == nil else { return }
        let t=Thread { [weak self] in
            guard let self=self else { return }
            let types: [CGEventType] = [.leftMouseDown,.leftMouseDragged,.leftMouseUp,
                                        .rightMouseDown,.rightMouseDragged,.rightMouseUp,
                                        .otherMouseDown,.otherMouseDragged,.otherMouseUp,
                                        .mouseMoved]
            let mask=types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            let context=Unmanaged.passUnretained(self).toOpaque()
            guard let tap=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,
                options:.defaultTap,eventsOfInterest:mask,callback:{ _,type,event,context in
                    guard let context=context else { return Unmanaged.passUnretained(event) }
                    return Unmanaged<PointerTap>.fromOpaque(context).takeUnretainedValue().handle(type,event)
                },userInfo:context) else {
                DispatchQueue.main.async {
                    self.onFailure?("Pointer event tap failed. Check Accessibility/Input Monitoring permissions, then restart.")
                }
                return
            }
            let loop=CFRunLoopGetCurrent()
            self.lock.lock(); self.port=tap; self.runLoop=loop; self.lock.unlock()
            let source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
            CFRunLoopAddSource(loop,source,.commonModes)
            CGEvent.tapEnable(tap:tap,enable:true)
            DispatchQueue.main.async { self.onReady?() }
            CFRunLoopRun()
            CFMachPortInvalidate(tap)
        }
        t.name="XMonadMac pointer event tap"; thread=t; t.start()
    }
    func stop() {
        lock.lock(); let p=port; let r=runLoop; enabled=false; activeMode=nil; lock.unlock()
        if let p=p { CFMachPortInvalidate(p) }
        if let r=r { CFRunLoopStop(r) }
    }
    private func modifierBits(_ flags: CGEventFlags) -> Int {
        (flags.contains(.maskShift) ? 1 : 0) | (flags.contains(.maskControl) ? 4 : 0) |
        (flags.contains(.maskAlternate) ? 8 : 0) | (flags.contains(.maskCommand) ? 64 : 0)
    }
    private func handle(_ type: CGEventType,_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock(); let p=port; lock.unlock()
            if let p=p { CGEvent.tapEnable(tap:p,enable:true) }
            return Unmanaged.passUnretained(event)
        }
        let location=event.location
        if type == .mouseMoved {
            lock.lock()
            let report=hoverEnabled && activeMode == nil
              && Date().timeIntervalSince(lastHover) > 0.08
            if report { lastHover=Date() }
            lock.unlock()
            if report { DispatchQueue.main.async { [weak self] in self?.onHover?(location) } }
            return Unmanaged.passUnretained(event)
        }
        lock.lock()
        let isEnabled=enabled, binds=bindings
        let down = type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
        let up = type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp
        let button: Int
        switch type {
        case .leftMouseDown,.leftMouseDragged,.leftMouseUp: button=1
        case .rightMouseDown,.rightMouseDragged,.rightMouseUp: button=3
        default: button=Int(event.getIntegerValueField(.mouseEventButtonNumber))
        }
        if down,isEnabled,let bind=binds.first(where:{ $0.mask == modifierBits(event.flags) && $0.button == button }) {
            activeMode=bind.action; activeButton=button
        }
        let active=activeMode
        let matching=active != nil && button == activeButton
        if up { activeMode=nil; activeButton=0 }
        lock.unlock()
        guard matching,let active=active else { return Unmanaged.passUnretained(event) }
        if active == .raise {
            if down { DispatchQueue.main.async { [weak self] in self?.onPointer?(.raise,.begin,location) } }
            return nil
        }
        let phase: PointerPhase = down ? .begin : (up ? .end : .drag)
        DispatchQueue.main.async { [weak self] in self?.onPointer?(active,phase,location) }
        return nil
    }
}
#endif
