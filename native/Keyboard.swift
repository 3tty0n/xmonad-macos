#if os(macOS)
import Foundation
import CoreGraphics

private struct PhysicalKey: Hashable { var code: UInt16; var mask: Int }

// macOS window and space shortcuts that move windows behind the tiler's back.
// Swallowed only while tiling is active and the menu toggle is on; nothing is
// written to system preferences, so quitting restores every shortcut.
private let systemShortcuts: Set<PhysicalKey> = {
    let tab: UInt16=48, backtick: UInt16=50, h: UInt16=4, m: UInt16=46
    let arrows: [UInt16]=[123,124,125,126]
    var set: Set<PhysicalKey> = [
        PhysicalKey(code:tab,mask:64), PhysicalKey(code:tab,mask:65),        // app switcher
        PhysicalKey(code:backtick,mask:64), PhysicalKey(code:backtick,mask:65), // window cycling
        PhysicalKey(code:h,mask:64), PhysicalKey(code:m,mask:64)]            // hide, minimize
    for a in arrows {                                                        // Mission Control
        set.insert(PhysicalKey(code:a,mask:4)); set.insert(PhysicalKey(code:a,mask:5))
    }
    return set
}()
final class KeyboardTap {
    private let lock = NSLock()
    private var bindings: [PhysicalKey:KeyBinding] = [:]
    private var swallowed: Set<UInt16> = []
    private var enabled = false
    private var suppressSystem = false
    private var logKeys = false
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    var onKey: ((KeyBinding?) -> Void)?  // nil = emergency pause/recovery
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onDebug: ((String) -> Void)?
    func configure(_ keys: [KeyBinding]) throws {
        var next: [PhysicalKey:KeyBinding] = [:]
        for k in keys {
            try validateBinding(k)
            let p = PhysicalKey(code:keyCodeForSym[k.sym]!,mask:k.mask)
            guard next[p] == nil else { throw WireError.invalid("Duplicate physical binding") }
            next[p] = k
        }
        lock.lock(); bindings=next; lock.unlock()
    }
    func setEnabled(_ value: Bool) { lock.lock(); enabled=value; lock.unlock() }
    func setSuppressSystemShortcuts(_ value: Bool) { lock.lock(); suppressSystem=value; lock.unlock() }
    func setLogKeys(_ value: Bool) { lock.lock(); logKeys=value; lock.unlock() }
    func start() {
        guard thread == nil else { return }
        let t = Thread { [weak self] in
            guard let self = self else { return }
            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) |
                       (CGEventMask(1) << CGEventType.keyUp.rawValue)
            let context = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,
                options:.defaultTap,eventsOfInterest:mask,callback:{ _,type,event,context in
                    guard let context = context else { return Unmanaged.passUnretained(event) }
                    return Unmanaged<KeyboardTap>.fromOpaque(context).takeUnretainedValue()
                        .handle(type,event)
                },userInfo:context) else {
                DispatchQueue.main.async {
                    self.onFailure?("Keyboard event tap failed. Check Accessibility/Input Monitoring permissions, then restart.")
                }
                return
            }
            let loop = CFRunLoopGetCurrent()
            self.lock.lock(); self.port=tap; self.runLoop=loop; self.lock.unlock()
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
            CFRunLoopAddSource(loop,source,.commonModes)
            CGEvent.tapEnable(tap:tap,enable:true)
            DispatchQueue.main.async { self.onReady?() }
            CFRunLoopRun()
            CFMachPortInvalidate(tap)
        }
        t.name="XMonadMac keyboard event tap"
        thread=t; t.start()
    }
    func stop() {
        lock.lock(); let p=port; let r=runLoop; enabled=false; lock.unlock()
        if let p = p { CFMachPortInvalidate(p) }
        if let r = r { CFRunLoopStop(r) }
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock(); let p=port; lock.unlock()
            if let p = p { CGEvent.tapEnable(tap:p,enable:true) }
            return Unmanaged.passUnretained(event)
        }
        let code=UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let f=event.flags
        let mask=(f.contains(.maskShift) ? 1 : 0) | (f.contains(.maskControl) ? 4 : 0) |
                 (f.contains(.maskAlternate) ? 8 : 0) | (f.contains(.maskCommand) ? 64 : 0)
        lock.lock()
        if type == .keyUp {
            let consumed=swallowed.remove(code) != nil
            lock.unlock()
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        let emergency=code == 53 && mask == (4|8|64)
        let key=bindings[PhysicalKey(code:code,mask:mask)]
        let suppressed=enabled && key == nil && suppressSystem
                       && systemShortcuts.contains(PhysicalKey(code:code,mask:mask))
        let consume=emergency || (enabled && key != nil) || suppressed
        if consume { swallowed.insert(code) }
        // Opt-in diagnosis for "my modifier does nothing": modified keys only.
        let report=(logKeys && mask != 0)
          ? "key code=\(code) mask=\(mask) bound=\(key != nil) consumed=\(consume) tiling=\(enabled)"
          : nil
        lock.unlock()
        if let report=report { DispatchQueue.main.async { [weak self] in self?.onDebug?(report) } }
        if consume {
            if emergency || key != nil {
                DispatchQueue.main.async { [weak self] in self?.onKey?(emergency ? nil : key) }
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
#endif
