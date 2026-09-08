#if os(macOS)
import Foundation
import AppKit
import ApplicationServices
import Darwin

func logMessage(_ s: String) {
    let text="[\(ISO8601DateFormatter().string(from:Date()))] \(s)\n"
    FileHandle.standardError.write(Data(text.utf8))
}
func axCopy(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e,name as CFString,&raw) == .success else { return nil }
    return raw
}
func axElement(_ e: AXUIElement, _ name: String) -> AXUIElement? {
    guard let raw=axCopy(e,name),CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(raw,to:AXUIElement.self)
}
func axBoolean(_ e: AXUIElement, _ name: String) -> Bool? { axCopy(e,name) as? Bool }
func axBool(_ e: AXUIElement, _ name: String) -> Bool { axBoolean(e,name) ?? false }
func axString(_ e: AXUIElement, _ name: String) -> String { (axCopy(e,name) as? String) ?? "" }
func axSettable(_ e: AXUIElement, _ name: String) -> Bool {
    var value: DarwinBoolean=false
    return AXUIElementIsAttributeSettable(e,name as CFString,&value) == .success && value.boolValue
}
func axFrame(_ e: AXUIElement) -> Rect? {
    guard let p=axCopy(e,kAXPositionAttribute),let s=axCopy(e,kAXSizeAttribute),
          CFGetTypeID(p) == AXValueGetTypeID(),CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point=CGPoint.zero, size=CGSize.zero
    guard AXValueGetValue(unsafeBitCast(p,to:AXValue.self),.cgPoint,&point),
          AXValueGetValue(unsafeBitCast(s,to:AXValue.self),.cgSize,&size),
          point.x.isFinite,point.y.isFinite,size.width.isFinite,size.height.isFinite,
          abs(point.x)<1_000_000,abs(point.y)<1_000_000,
          size.width>0,size.height>0,size.width<100_000,size.height<100_000 else { return nil }
    return Rect(x:Int(point.x.rounded()),y:Int(point.y.rounded()),
                width:Int(size.width.rounded()),height:Int(size.height.rounded()))
}
struct AppDescriptor {
    var pid: pid_t, name: String, bundle: String, launch: Double, hidden: Bool
}
struct RecoveryEntry: Codable {
    var token: String, pid: Int32, launch: Double, bundle: String
    var identifier: String, title: String, frame: Rect
}
final class RecoveryJournal {
    let url: URL
    private(set) var entries: [RecoveryEntry]
    init(_ url: URL) throws {
        self.url=url
        if FileManager.default.fileExists(atPath:url.path) {
            entries=try JSONDecoder().decode([RecoveryEntry].self,from:Data(contentsOf:url))
        } else { entries=[] }
    }
    private func persist(_ next: [RecoveryEntry]) throws {
        let data=try JSONEncoder().encode(next)
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        entries=next
    }
    func add(_ e: RecoveryEntry) throws { try persist(entries+[e]) }
    func remove(_ token: String) throws { try persist(entries.filter { $0.token != token }) }
}
final class AXRecord {
    let wid: UInt64, element: AXUIElement, descriptor: AppDescriptor
    var frame: Rect, title: String, identifier: String
    var token: String?
    var hideRequestedAt=Date.distantPast
    var wantsHidden=false
    // Set once AX confirms our minimize. Without it a restore cannot tell
    // "already back" from "the minimize has not landed yet".
    var hideConfirmed=false
    var restoreRequestedAt=Date.distantPast
    // Last AX-observed minimized state, like `frame`, kept so a failed read
    // does not drop the window from a snapshot.
    var lastMinimized: Bool?
    // Consecutive scans a known window has failed the on-screen match.
    var offScreen=0
    // Consecutive scans this window's application was missing from the
    // running-application list, or reported as hidden.
    var appAbsent=0
    var appHidden=0
    var eligible=false
    var absent=0
    var lastTarget: Rect?
    var lastActual: Rect?
    var lastAttempt=Date.distantPast
    init(_ wid: UInt64, _ e: AXUIElement, _ app: AppDescriptor, _ frame: Rect) {
        self.wid=wid; element=e; descriptor=app; self.frame=frame
        title=axString(e,kAXTitleAttribute); identifier=axString(e,kAXIdentifierAttribute)
    }
    var recovery: RecoveryEntry {
        RecoveryEntry(token:UUID().uuidString,pid:descriptor.pid,launch:descriptor.launch,
          bundle:descriptor.bundle,identifier:identifier,title:title,frame:frame)
    }
}
final class NotificationRelay {
    var changed: (() -> Void)?
    func notify() { DispatchQueue.main.async { [weak self] in self?.changed?() } }
}
struct ScanResult {
    var windows: [WindowInfo], focused: UInt64?, nativeFullScreen: Bool
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
        accessibilityTrusted && focusedWindowFound && standardWindow && positionSettable &&
        sizeSettable && minimizedSettable && frameReadable && sameFrameWriteSucceeded && readBackMatched &&
        onScreenCorrelation && !nativeFullScreen
    }
}

// All methods except the notification callback run on one serial AX queue.
// AppKit, the event tap and the engine reader never wait synchronously on AX.
final class AXStore {
    let journal: RecoveryJournal
    let relay: NotificationRelay
    private var records: [UInt64:AXRecord]=[:]
    private var observers: [pid_t:AXObserver]=[:]
    private var nextID: UInt64=1
    private var active: Set<UInt64>=[]
    private var latestGeneration = -1
    private var activeEpoch = 0
    private var lastAmbiguityWarning=Date.distantPast
    private var displays: [DisplayInfo]=[]
    private var pointerDrag: PointerDragSession?
    init(journal: RecoveryJournal,relay: NotificationRelay) {
        self.journal=journal; self.relay=relay
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(),0.2)
    }
    private func observe(_ app: AppDescriptor, _ root: AXUIElement) {
        guard observers[app.pid] == nil else { return }
        var raw: AXObserver?
        guard AXObserverCreate(app.pid,{ _,_,_,context in
            guard let context=context else { return }
            Unmanaged<NotificationRelay>.fromOpaque(context).takeUnretainedValue().notify()
        },&raw) == .success,let observer=raw else { return }
        let context=Unmanaged.passUnretained(relay).toOpaque()
        for name in [kAXWindowCreatedNotification,kAXFocusedWindowChangedNotification,
                     kAXApplicationHiddenNotification,kAXApplicationShownNotification] {
            AXObserverAddNotification(observer,root,name as CFString,context)
        }
        observers[app.pid]=observer
        DispatchQueue.main.async {
            CFRunLoopAddSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes)
        }
    }
    private func observeWindow(_ r: AXRecord) {
        guard let observer=observers[r.descriptor.pid] else { return }
        let context=Unmanaged.passUnretained(relay).toOpaque()
        for name in [kAXUIElementDestroyedNotification,kAXMovedNotification,kAXResizedNotification,
                     kAXWindowMiniaturizedNotification,kAXWindowDeminiaturizedNotification,
                     kAXTitleChangedNotification] {
            AXObserverAddNotification(observer,r.element,name as CFString,context)
        }
    }
    // ESRCH means no such process; anything else means it is still there, or
    // that we may not ask, and either way the window is not proven gone.
    private func processIsGone(_ pid: pid_t) -> Bool {
        kill(pid,0) == -1 && errno == ESRCH
    }
    private func releaseOwnership(_ r: AXRecord) {
        guard let token=r.token else { return }
        do { try journal.remove(token); r.token=nil }
        catch { logMessage("Cannot update recovery journal: \(error)") }
    }
    private func cgVisibleFrames() -> [(pid_t,Rect)] {
        guard let list=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],
                       kCGNullWindowID) as? [[String:Any]] else { return [] }
        return list.compactMap { d in
            guard (d[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid=(d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds=d[kCGWindowBounds as String] as? [String:Any],
                  let r=CGRect(dictionaryRepresentation:bounds as CFDictionary) else { return nil }
            return (pid,Rect(x:Int(r.minX.rounded()),y:Int(r.minY.rounded()),
                       width:Int(r.width.rounded()),height:Int(r.height.rounded())))
        }
    }
    func scan(apps: [AppDescriptor],displays: [DisplayInfo],generation: Int,epoch: Int) -> ScanResult {
        latestGeneration=generation; activeEpoch=epoch
        self.displays=displays
        let livePIDs=Set(apps.map(\.pid))
        // An application missing from one scan is not proof that it exited:
        // coming back from display sleep, NSWorkspace briefly reports an
        // incomplete list. Forgetting a window here is expensive, because the
        // engine then treats it as new and adopts it onto the workspace in
        // view, so wait for a second scan and ask the kernel as well.
        for (id,r) in Array(records) {
            let listed=apps.contains { $0.pid == r.descriptor.pid
              && abs($0.launch-r.descriptor.launch) < 0.01 }
            if listed { r.appAbsent=0; continue }
            r.appAbsent += 1
            if r.appAbsent >= 2,processIsGone(r.descriptor.pid) {
                releaseOwnership(r); records.removeValue(forKey:id)
            }
        }
        for pid in Array(observers.keys) where !livePIDs.contains(pid) {
            if let ob=observers.removeValue(forKey:pid) {
                DispatchQueue.main.async {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(ob),.commonModes)
                }
            }
        }
        var seen: Set<UInt64>=[], succeeded: Set<pid_t>=[], hiddenPIDs: Set<pid_t>=[]
        for app in apps.sorted(by:{ $0.pid < $1.pid }) {
            if app.hidden { hiddenPIDs.insert(app.pid) }
            let root=AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(root,0.15)
            observe(app,root)
            guard let windows=axCopy(root,kAXWindowsAttribute) as? [AXUIElement] else { continue }
            succeeded.insert(app.pid)
            for e in windows {
                let r: AXRecord
                if let old=records.values.first(where:{ $0.descriptor.pid == app.pid && CFEqual($0.element,e) }) {
                    // Keep the last good geometry: a busy app fails this read
                    // during its own animations, and losing the record would
                    // hand the window back to the engine as a new one.
                    r=old
                    if let frame=axFrame(e) { r.frame=frame }
                    r.title=axString(e,kAXTitleAttribute)
                } else {
                    guard let frame=axFrame(e) else { continue }
                    r=AXRecord(nextID,e,app,frame); nextID += 1; records[r.wid]=r
                    AXUIElementSetMessagingTimeout(e,0.15); observeWindow(r)
                }
                seen.insert(r.wid); r.absent=0
                // Freeze eligibility while we own the window. It is hidden for
                // a non-visible workspace, and a minimized window reports
                // AXSubrole as AXDialog; recomputing would drop it from the
                // snapshot, and the engine would forget which workspace owns it.
                if r.token == nil {
                    r.eligible=axString(e,kAXRoleAttribute) == kAXWindowRole &&
                      axString(e,kAXSubroleAttribute) == kAXStandardWindowSubrole &&
                      !axBool(e,"AXFullScreen") && axSettable(e,kAXPositionAttribute) &&
                      axSettable(e,kAXSizeAttribute) && axSettable(e,kAXMinimizedAttribute)
                }
                // An owned window is driven to the last requested state until AX
                // agrees, in both directions. Hidden: if it comes back on its own
                // (an app that un-minimizes, or the user reopening it from the
                // Dock), re-assert the minimize rather than releasing ownership,
                // because releasing flips ownedHidden false and the engine then
                // re-inserts the window onto the workspace in view. Shown: a
                // restore that a late in-flight minimize undid is re-asserted,
                // and ownership is dropped only once the window is really back.
                if r.token != nil,let mini=axBoolean(e,kAXMinimizedAttribute) {
                    if mini { r.hideConfirmed=true }
                    if r.wantsHidden {
                        if !mini,onAnyDisplay(r.frame),
                           Date().timeIntervalSince(r.hideRequestedAt)>0.5 {
                            hide(r)   // Came back on its own: park it again.
                        }
                    } else if Date().timeIntervalSince(r.restoreRequestedAt)>0.12 {
                        if mini {
                            r.restoreRequestedAt=Date()
                            AXUIElementSetAttributeValue(e,kAXMinimizedAttribute as CFString,kCFBooleanFalse)
                        } else if onAnyDisplay(r.frame) { releaseOwnership(r) }
                    }
                }
            }
        }
        // A window this scan did not enumerate. Only an element the window
        // server has actually destroyed, or a dead process, proves it is gone:
        // a busy application returns an incomplete window list, and an
        // incomplete list is exactly what waking a display produces. Guessing
        // here costs the window its workspace, because the engine then treats
        // it as new and adopts it onto the workspace in view.
        for (id,r) in Array(records) where !seen.contains(id) {
            guard succeeded.contains(r.descriptor.pid) else { continue }
            r.absent += 1
            guard r.absent >= 2 else { continue }
            var value: CFTypeRef?
            let error=AXUIElementCopyAttributeValue(r.element,kAXRoleAttribute as CFString,&value)
            if error == .invalidUIElement {
                logMessage("Window \(id) removed: its element was destroyed")
                releaseOwnership(r); records.removeValue(forKey:id)
            } else if processIsGone(r.descriptor.pid) {
                logMessage("Window \(id) removed: process \(r.descriptor.pid) exited")
                releaseOwnership(r); records.removeValue(forKey:id)
            }
        }
        let cg=cgVisibleFrames()
        let all=Array(records.values)
        var result: [WindowInfo]=[], ambiguous=0
        for r in all.sorted(by:{ $0.wid < $1.wid }) {
            guard r.eligible else { continue }
            // Cmd-H takes an application's windows out of management, but one
            // observation is not enough: on wake macOS reports applications
            // hidden that are not, and dropping them here costs the workspace.
            if hiddenPIDs.contains(r.descriptor.pid) { r.appHidden += 1 } else { r.appHidden=0 }
            guard r.appHidden < 2 else { continue }
            // A busy app can fail this read for one scan, typically during its
            // own minimize animation. Dropping the window from the snapshot
            // would make the engine treat it as closed and re-insert it on the
            // workspace in view, so fall back to the last observed state.
            guard let mini=axBoolean(r.element,kAXMinimizedAttribute) ?? r.lastMinimized
            else { continue }
            r.lastMinimized=mini
            let own=r.token != nil
            // On-screen association uses public PID + bounds only. Ambiguous
            // same-PID/same-frame windows across native Spaces are NOT touched.
            let peers=all.filter { $0.descriptor.pid == r.descriptor.pid &&
              $0.frame.near(r.frame) && !axBool($0.element,kAXMinimizedAttribute) }.count
            let visible=cg.filter { $0.0 == r.descriptor.pid && $0.1.near(r.frame) }.count
            let onScreen=visible > 0 && visible >= peers
            if onScreen || mini { r.offScreen=0 } else { r.offScreen += 1 }
            // The on-screen match decides which windows may be *admitted*: an
            // ambiguous one across native Spaces is never touched. Retaining a
            // window already in the snapshot is a different question, and a
            // window animating out of the Dock, or mid-move, is missing from
            // the window-server list for a scan or two. Dropping it there makes
            // the engine treat it as closed and re-insert it on the workspace in
            // view, which silently migrates windows on every workspace switch.
            let known=active.contains(r.wid) && r.offScreen<3
            guard own || (!mini && (onScreen || known)) else {
                if !mini && visible > 0 { ambiguous += 1 }
                continue
            }
            // Keep WM-owned minimized windows; user-minimized windows are excluded.
            result.append(WindowInfo(wid:r.wid,pid:r.descriptor.pid,app:r.descriptor.name,
              bundle:r.descriptor.bundle,titleText:r.title,onDisplay:bestDisplay(for:r.frame,in:displays),
              frame:r.frame,minimized:mini,ownedHidden:own))
        }
        if ambiguous > 0 && Date().timeIntervalSince(lastAmbiguityWarning)>30 {
            logMessage("Skipped \(ambiguous) ambiguous on-screen windows (same PID/frame). Use one native Space per display.")
            lastAmbiguityWarning=Date()
        }
        // Losing a known window is how a send-to-workspace turns into a window
        // stuck in the Dock: the engine treats it as closed. Leave a trace.
        let next=Set(result.map(\.wid))
        for id in active.subtracting(next) {
            guard let r=records[id] else {
                logMessage("Window \(id) left the snapshot: closed"); continue
            }
            logMessage("Window \(id) (\(r.descriptor.name)) left the snapshot: "
              + "eligible=\(r.eligible) owned=\(r.token != nil) "
              + "minimized=\(r.lastMinimized.map(String.init) ?? "unreadable")")
        }
        active=next
        var focused: UInt64?, fullScreen=false
        if let app=axElement(AXUIElementCreateSystemWide(),kAXFocusedApplicationAttribute),
           let window=axElement(app,kAXFocusedWindowAttribute) {
            fullScreen=axBool(window,"AXFullScreen")
            focused=all.first(where:{ CFEqual($0.element,window) && active.contains($0.wid) &&
              axBoolean($0.element,kAXMinimizedAttribute) == false })?.wid
        }
        return ScanResult(windows:result,focused:focused,nativeFullScreen:fullScreen)
    }
    private func windowAt(_ point: CGPoint) -> AXRecord? {
        let system=AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system,Float(point.x),Float(point.y),&hit) == .success,
              let first=hit else { return nil }
        var candidates: [AXUIElement]=[first]
        if let w=axElement(first,kAXWindowAttribute) { candidates.append(w) }
        var current=first
        for _ in 0..<8 {
            guard let parent=axElement(current,kAXParentAttribute) else { break }
            candidates.append(parent); current=parent
        }
        for e in candidates {
            if let r=records.values.first(where:{ active.contains($0.wid) && $0.eligible && CFEqual($0.element,e) }) {
                return r
            }
        }
        return nil
    }
    func beginPointerDrag(at point: CGPoint,mode: PointerMode) -> UInt64? {
        guard pointerDrag == nil,let r=windowAt(point),
              axBoolean(r.element,kAXMinimizedAttribute) == false,
              let frame=axFrame(r.element) else { return nil }
        pointerDrag=PointerDragSession(wid:r.wid,mode:mode,start:point,initial:frame)
        return r.wid
    }
    func updatePointerDrag(to point: CGPoint) {
        guard let drag=pointerDrag,let r=records[drag.wid] else { pointerDrag=nil; return }
        let dx=Int((point.x-drag.start.x).rounded()),dy=Int((point.y-drag.start.y).rounded())
        let target: Rect
        switch drag.mode {
        case .move:
            target=Rect(x:drag.initial.x+dx,y:drag.initial.y+dy,
                        width:drag.initial.width,height:drag.initial.height)
        case .resize:
            target=Rect(x:drag.initial.x,y:drag.initial.y,
                        width:max(80,drag.initial.width+dx),height:max(60,drag.initial.height+dy))
        }
        move(r,target)
        if let observed=axFrame(r.element) { r.frame=observed }
        relay.notify()
    }
    func endPointerDrag(at point: CGPoint) -> UInt64? {
        guard let drag=pointerDrag else { return nil }
        updatePointerDrag(to:point); pointerDrag=nil; relay.notify(); return drag.wid
    }
    func cancelPointerDrag() { pointerDrag=nil }

    // A window on another workspace is parked past the right edge of the
    // display arrangement, keeping its size. Unlike AXMinimized this involves
    // no Dock, no animation and no app that may refuse, and the window is
    // brought back by the ordinary placement that follows.
    private func parkingSpot(for r: AXRecord) -> Rect {
        let right=displays.map { $0.usable.x+$0.usable.width }.max() ?? r.frame.x
        let bottom=displays.map { $0.usable.y+$0.usable.height }.max() ?? r.frame.y
        return Rect(x:right+64,y:bottom+64,width:r.frame.width,height:r.frame.height)
    }
    // AppKit will not let a window leave the screen completely: it keeps about
    // 40 points of it in view. Parked into the bottom-right corner both limits
    // apply at once and roughly 40x32 points remain, so anything under a
    // 64-point square counts as hidden. Beyond that a window would show a
    // visible strip over the workspace and has to be minimized instead.
    private func onAnyDisplay(_ rect: Rect) -> Bool {
        displays.map { $0.usable.intersectionArea(rect) }.reduce(0,+) > 4096
    }
    private func show(_ r: AXRecord) {
        guard r.token != nil else { return }  // Never restore a user's hiding.
        r.wantsHidden=false
        r.restoreRequestedAt=Date()
        // A window we had to minimize because parking was refused.
        if axBoolean(r.element,kAXMinimizedAttribute) == true {
            let error=AXUIElementSetAttributeValue(r.element,kAXMinimizedAttribute as CFString,kCFBooleanFalse)
            if error != .success { logMessage("Restore failed for window \(r.wid): \(error.rawValue)") }
        }
        // Placement puts it back on screen; ownership ends when a scan agrees.
    }
    private func hide(_ r: AXRecord) {
        guard (axBoolean(r.element,kAXMinimizedAttribute) ?? r.lastMinimized) == false
        else {
            // Ours is already hidden; only someone else's minimization is news.
            if r.token == nil { logMessage("Hide skipped for window \(r.wid): user-minimized") }
            return
        }
        guard let actual=axFrame(r.element) else { return }
        // Already parked: the clamped position never equals the requested one,
        // so compare visibility rather than coordinates or we rewrite it on
        // every scan.
        if r.token != nil,!onAnyDisplay(actual) { r.wantsHidden=true; return }
        guard r.descriptor.launch>0 else { logMessage("Cannot journal unknown application lifetime"); return }
        if r.token == nil {
            let entry=r.recovery
            do { try journal.add(entry); r.token=entry.token }
            catch { logMessage("Refusing to hide without a durable recovery record: \(error)"); return }
        }
        r.wantsHidden=true; r.hideRequestedAt=Date(); r.hideConfirmed=false
        let spot=parkingSpot(for:r)
        var point=CGPoint(x:spot.x,y:spot.y)
        guard let pv=AXValueCreate(.cgPoint,&point) else { return }
        AXUIElementSetAttributeValue(r.element,kAXPositionAttribute as CFString,pv)
        // Apps may clamp a position back onto a display. Such a window would
        // cover the workspace, so fall back to minimizing that one.
        if let observed=axFrame(r.element) {
            r.frame=observed
            if onAnyDisplay(observed) {
                let error=AXUIElementSetAttributeValue(r.element,kAXMinimizedAttribute as CFString,kCFBooleanTrue)
                if error != .success {
                    logMessage("Window \(r.wid) refuses to be parked or minimized")
                    releaseOwnership(r)
                }
            }
        }
    }
    private func move(_ r: AXRecord,_ target: Rect) {
        guard axBoolean(r.element,kAXMinimizedAttribute) == false,let actual=axFrame(r.element) else { return }
        if actual.near(target) { return }
        if r.lastTarget == target,r.lastActual == actual,
           Date().timeIntervalSince(r.lastAttempt)<2 { return }
        r.lastTarget=target; r.lastAttempt=Date()
        var size=CGSize(width:target.width,height:target.height)
        var point=CGPoint(x:target.x,y:target.y)
        guard let sv=AXValueCreate(.cgSize,&size),let pv=AXValueCreate(.cgPoint,&point) else { return }
        // Size-position-size handles many cross-display AppKit constraint cases.
        let e1=AXUIElementSetAttributeValue(r.element,kAXSizeAttribute as CFString,sv)
        let e2=AXUIElementSetAttributeValue(r.element,kAXPositionAttribute as CFString,pv)
        let e3=AXUIElementSetAttributeValue(r.element,kAXSizeAttribute as CFString,sv)
        let observed=axFrame(r.element)
        let warn=r.lastActual != observed || (e1 != .success || e2 != .success || e3 != .success)
        r.lastActual=observed
        if warn,let observed=observed,!observed.near(target,tolerance:4) {
            logMessage("Window \(r.wid) constrained requested=\(target) actual=\(observed), AX=\(e1.rawValue)/\(e2.rawValue)/\(e3.rawValue)")
        }
    }
    func apply(_ p: Plan) throws {
        guard p.epoch == activeEpoch,p.generation == latestGeneration else {
            if !p.hide.isEmpty {
                logMessage("Dropped plan gen=\(p.generation)/\(latestGeneration) "
                  + "epoch=\(p.epoch)/\(activeEpoch) hide=\(p.hide)")
            }
            return
        }
        try PlanSafety.validate(p,active:active)
        // Restore and place destinations before hiding sources. Only deliberate
        // policy focus requests may activate an app; ordinary scans never do.
        let dragging=pointerDrag?.wid
        for placement in p.frames {
            guard placement.wid != dragging,let r=records[placement.wid] else { continue }
            show(r); move(r,placement.frame)
        }
        for id in p.hide {
            guard id != dragging else { logMessage("Hide skipped for window \(id): drag"); continue }
            guard let r=records[id] else { logMessage("Hide skipped for window \(id): no record"); continue }
            hide(r)
        }
        if let id=p.focus,let r=records[id],axBoolean(r.element,kAXMinimizedAttribute) == false {
            if let app=NSRunningApplication(processIdentifier:r.descriptor.pid) {
                app.activate(options:[.activateIgnoringOtherApps]) // Deliberate hotkey focus only; never activateAllWindows.
            }
            let app=AXUIElementCreateApplication(r.descriptor.pid)
            AXUIElementSetAttributeValue(app,kAXFocusedWindowAttribute as CFString,r.element)
            AXUIElementSetAttributeValue(r.element,kAXMainAttribute as CFString,kCFBooleanTrue)
            AXUIElementPerformAction(r.element,kAXRaiseAction as CFString)
        }
    }
    func close(_ id: UInt64) {
        guard let r=records[id],active.contains(id),
              let button=axElement(r.element,kAXCloseButtonAttribute) else { return }
        let e=AXUIElementPerformAction(button,kAXPressAction as CFString)
        if e != .success { logMessage("Close failed: \(e.rawValue)") }
    }
    // Put every owned window back where it was before we hid it. The journal
    // holds that frame, so this works for parked and minimized windows alike.
    private func restore(_ r: AXRecord) {
        show(r)
        r.lastTarget=nil   // Never let the move throttle skip a restore.
        guard let entry=journal.entries.first(where:{ $0.token == r.token }) else { return }
        move(r,entry.frame)
    }
    func restoreAll() {
        let owned=records.values.filter { $0.token != nil }
        for r in owned { restore(r) }
        if !owned.isEmpty { Thread.sleep(forTimeInterval:0.15) }
        // No further scan will run here, so confirm and release in place.
        for r in owned where r.token != nil {
            restore(r)
            if let observed=axFrame(r.element),onAnyDisplay(observed),
               axBoolean(r.element,kAXMinimizedAttribute) == false { releaseOwnership(r) }
        }
    }
    func invalidate(epoch: Int) { pointerDrag=nil; activeEpoch=epoch; latestGeneration = -1; active=[] }

    // A new bridge has no valid old AX handles. Reattach only by an unambiguous
    // process-instance + AXIdentifier, or process-instance + title + frame match.
    // Entries whose application instance ended can be safely discarded.
    func recover(apps: [AppDescriptor],displays: [DisplayInfo]) {
        self.displays=displays
        for entry in journal.entries {
            guard let app=apps.first(where:{ $0.pid == entry.pid && $0.bundle == entry.bundle &&
                  entry.launch>0 && abs($0.launch-entry.launch)<0.01 }) else {
                try? journal.remove(entry.token); continue
            }
            let root=AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(root,0.15)
            guard let windows=axCopy(root,kAXWindowsAttribute) as? [AXUIElement] else { continue }
            let matches=windows.filter { e in
                if !entry.identifier.isEmpty {
                    return axString(e,kAXIdentifierAttribute) == entry.identifier
                }
                // Same title, and either still where it was or parked off every
                // display — a window we hid cannot be at its journaled frame.
                guard axString(e,kAXTitleAttribute) == entry.title,
                      let frame=axFrame(e) else { return false }
                return frame.near(entry.frame) || !onAnyDisplay(frame)
            }
            guard matches.count == 1,let e=matches.first,let frame=axFrame(e) else {
                logMessage("Recovery left ambiguous/unavailable window for PID \(entry.pid); journal retained.")
                continue
            }
            let r=AXRecord(nextID,e,app,frame); nextID += 1; r.token=entry.token
            records[r.wid]=r; restore(r)
        }
        restoreAll()
    }
}


func runAXSelfTest() -> AXSelfTestReport {
    var report=AXSelfTestReport(accessibilityTrusted:AXIsProcessTrusted(),focusedWindowFound:false,
      standardWindow:false,positionSettable:false,sizeSettable:false,minimizedSettable:false,
      frameReadable:false,sameFrameWriteSucceeded:false,readBackMatched:false,onScreenCorrelation:false,
      nativeFullScreen:false,pid:nil,title:nil,frame:nil,errors:[])
    guard report.accessibilityTrusted else { report.errors.append("Accessibility permission is not granted"); return report }
    let system=AXUIElementCreateSystemWide()
    guard let app=axElement(system,kAXFocusedApplicationAttribute),
          let window=axElement(app,kAXFocusedWindowAttribute) else {
        report.errors.append("No focused Accessibility window"); return report
    }
    report.focusedWindowFound=true
    var pid: pid_t=0
    if AXUIElementGetPid(window,&pid) == .success { report.pid=pid }
    report.title=axString(window,kAXTitleAttribute)
    report.standardWindow=axString(window,kAXRoleAttribute) == kAXWindowRole &&
      axString(window,kAXSubroleAttribute) == kAXStandardWindowSubrole
    report.positionSettable=axSettable(window,kAXPositionAttribute)
    report.sizeSettable=axSettable(window,kAXSizeAttribute)
    report.minimizedSettable=axSettable(window,kAXMinimizedAttribute)
    report.nativeFullScreen=axBool(window,"AXFullScreen")
    guard let frame=axFrame(window) else { report.errors.append("Focused window frame is unreadable"); return report }
    report.frameReadable=true; report.frame=frame
    var point=CGPoint(x:frame.x,y:frame.y),size=CGSize(width:frame.width,height:frame.height)
    if report.positionSettable && report.sizeSettable,
       let pv=AXValueCreate(.cgPoint,&point),let sv=AXValueCreate(.cgSize,&size) {
        let p1=AXUIElementSetAttributeValue(window,kAXPositionAttribute as CFString,pv)
        let s1=AXUIElementSetAttributeValue(window,kAXSizeAttribute as CFString,sv)
        report.sameFrameWriteSucceeded=(p1 == .success && s1 == .success)
        if !report.sameFrameWriteSucceeded { report.errors.append("Same-frame AX write failed: \(p1.rawValue)/\(s1.rawValue)") }
        if let observed=axFrame(window) { report.readBackMatched=observed.near(frame,tolerance:4) }
    }
    if let list=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]],
       let pid=report.pid {
        report.onScreenCorrelation=list.contains { d in
            guard (d[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let bounds=d[kCGWindowBounds as String] as? [String:Any],
                  let cg=CGRect(dictionaryRepresentation:bounds as CFDictionary) else { return false }
            return Rect(x:Int(cg.minX.rounded()),y:Int(cg.minY.rounded()),
                        width:Int(cg.width.rounded()),height:Int(cg.height.rounded())).near(frame,tolerance:4)
        }
    }
    if !report.standardWindow { report.errors.append("Focused element is not a standard AX window") }
    if !report.positionSettable { report.errors.append("AXPosition is not settable") }
    if !report.sizeSettable { report.errors.append("AXSize is not settable") }
    if !report.minimizedSettable { report.errors.append("AXMinimized is not settable") }
    if !report.readBackMatched { report.errors.append("AX frame read-back did not match") }
    if !report.onScreenCorrelation { report.errors.append("Public CGWindow PID/frame correlation was not found") }
    if report.nativeFullScreen { report.errors.append("Focused window is in native full-screen") }
    return report
}
#endif
