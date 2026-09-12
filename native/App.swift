#if os(macOS)
import Foundation
import AppKit
import ApplicationServices
import Darwin

struct Paths {
    static let support=FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/XMonadMac",isDirectory:true)
    static let engine=support.appendingPathComponent("xmonad-engine")
    static let recovery=support.appendingPathComponent("recovery.json")
    static let session=support.appendingPathComponent("session.json")
    static let status=support.appendingPathComponent("status.json")
    static let selfTest=support.appendingPathComponent("self-test.json")
    // ~/.xmonad/xmonad.hs wins when present, matching upstream xmonad layouts;
    // computed on each use so creating it does not need an app restart.
    static var config: URL {
        let home=FileManager.default.homeDirectoryForCurrentUser
        let legacy=home.appendingPathComponent(".xmonad/xmonad.hs")
        if FileManager.default.fileExists(atPath:legacy.path) { return legacy }
        return home.appendingPathComponent(".config/xmonad-mac/xmonad.hs")
    }
    static let log=FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/XMonadMac/bridge.log")
    static func prepare() throws {
        for dir in [support,log.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,
                                                    attributes:[.posixPermissions:0o700])
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:dir.path)
        }
    }
}
let commandNotification=Notification.Name("org.xmonad.XMonadMac.command")
func descriptors() -> [AppDescriptor] {
    NSWorkspace.shared.runningApplications.compactMap { app in
        guard app.activationPolicy == .regular,app.processIdentifier != getpid() else { return nil }
        return AppDescriptor(pid:app.processIdentifier,name:app.localizedName ?? "",
          bundle:app.bundleIdentifier ?? "",
          launch:app.launchDate?.timeIntervalSince1970 ?? processStartTime(app.processIdentifier),
          hidden:app.isHidden)
    }
}
func displayInfo() -> [DisplayInfo] {
    let screens=NSScreen.screens
    let primaryID=Int(CGMainDisplayID())
    let primary=screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue == primaryID }
    let top=(primary ?? screens.first)?.frame.maxY ?? 0
    return screens.compactMap { s -> DisplayInfo? in
        guard let id=(s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue else { return nil }
        let r=s.visibleFrame
        let rect=Rect(x:Int(r.minX.rounded()),y:Int((top-r.maxY).rounded()),
                      width:Int(r.width.rounded()),height:Int(r.height.rounded()))
        return rect.valid ? DisplayInfo(display:id,usable:rect) : nil
    }.sorted { a,b in
        if a.display == primaryID { return b.display != primaryID }
        if b.display == primaryID { return false }
        return a.display < b.display
    }
}
let suppressDefaultsKey="SuppressSystemShortcuts"
let logKeysDefaultsKey="LogKeyEvents"
func acquireLock() throws -> Int32 {
    let url=Paths.support.appendingPathComponent("bridge.lock")
    let fd=open(url.path,O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,0o600)
    guard fd >= 0,flock(fd,LOCK_EX|LOCK_NB) == 0 else {
        if fd >= 0 { close(fd) }
        throw WireError.invalid("Another XMonadMac instance is running")
    }
    return fd
}
func redirectLog() {
    if let size=(try? FileManager.default.attributesOfItem(atPath:Paths.log.path)[.size]) as? NSNumber,
       size.intValue>5_000_000 {
        let previous=Paths.log.appendingPathExtension("previous")
        try? FileManager.default.removeItem(at:previous)
        try? FileManager.default.moveItem(at:Paths.log,to:previous)
    }
    let fd=open(Paths.log.path,O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW,0o600)
    if fd >= 0 { dup2(fd,STDERR_FILENO); close(fd) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let axQueue=DispatchQueue(label:"org.xmonad.XMonadMac.ax",qos:.userInitiated)
    private let writer=DispatchQueue(label:"org.xmonad.XMonadMac.engine-input")
    private let keyboard=KeyboardTap()
    private let pointer=PointerTap()
    private let border=BorderOverlay()
    private var hoverWid: UInt64?
    private let relay=NotificationRelay()
    private var store: AXStore!
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var suppressItem: NSMenuItem!
    private var logKeysItem: NSMenuItem!
    private var child: Process?
    private var compiler: Process?
    private var input: FileHandle?
    private var runToken=UUID()
    private var workspaces: [WorkspaceInfo]=[]
    private var poll: Timer?
    private var signalSources: [DispatchSourceSignal]=[]
    private var observers: [NSObjectProtocol]=[]
    private var lockFD: Int32 = -1
    private var running=false, configured=false, tapReady=false, pointerReady=false, recoveryDone=false
    private var quitting=false, recovering=false, recompiling=false, fullScreen=false
    private var scanInFlight=false, scanAgain=false
    private var scanWork: DispatchWorkItem?
    private var pointerUpdateInFlight=false
    private var pointerPendingPoint: CGPoint?
    private var pointerPendingEnd: CGPoint?
    private var sequence=0, currentEpoch=0, latestSent = -1
    // Set only for an explicit focus request. Ordinary plans must not move the
    // overlay, or a later scan of the outgoing window puts it on the old one.
    private var borderPin: UInt64?
    private var lastResponse=Date()
    private var checkpoint: JSONValue?
    private var sendCheckpoint=false
    // Nothing is scanned before this instant. Waking a display leaves macOS
    // answering for a second or two with an incomplete world: missing
    // applications, unreadable frames, windows the window server has not
    // placed yet. Acting on that is what loses the workspace assignments.
    private var settledAt=Date.distantPast
    private var lastSnapshot: Snapshot?
    private var dumpNext=false
    private var label="Paused"
    private var suppressShortcuts=UserDefaults.standard.bool(forKey:suppressDefaultsKey)
    private var logKeys=UserDefaults.standard.bool(forKey:logKeysDefaultsKey)
    private var axBusySince: Date?
    private let dryRun=CommandLine.arguments.contains("--dry-run")

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try Paths.prepare(); lockFD=try acquireLock(); redirectLog()
            store=AXStore(journal:try RecoveryJournal(Paths.recovery),relay:relay)
        } catch { fputs("XMonadMac: \(error)\n",stderr); NSApp.terminate(nil); return }
        makeMenu()
        relay.changed={ [weak self] in self?.scheduleScan() }
        keyboard.onKey={ [weak self] key in
            guard let self=self else { return }
            guard let key=key else { self.pause(reason:"Emergency pause; restoring owned windows"); return }
            if self.running && self.configured && !self.fullScreen {
                self.sendObject(["type":"key","mask":key.mask,"sym":key.sym])
            }
        }
        keyboard.onReady={ [weak self] in self?.tapReady=true; self?.updateKeyState() }
        keyboard.onFailure={ [weak self] problem in self?.pause(reason:problem) }
        keyboard.onDebug={ [weak self] line in _=self; logMessage(line) }
        pointer.onPointer={ [weak self] mode,phase,point in self?.handlePointer(mode:mode,phase:phase,point:point) }
        pointer.onHover={ [weak self] point in self?.handleHover(point) }
        pointer.onReady={ [weak self] in self?.pointerReady=true; self?.updateKeyState() }
        pointer.onFailure={ [weak self] problem in self?.pause(reason:problem) }
        DistributedNotificationCenter.default().addObserver(self,selector:#selector(receivedCommand(_:)),
          name:commandNotification,object:String(getuid()))
        let center=NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification,NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.scheduleScan() })
        }
        observers.append(center.addObserver(forName:NSWorkspace.activeSpaceDidChangeNotification,
          object:nil,queue:.main) { [weak self] _ in self?.spaceChanged() })
        observers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,
          object:nil,queue:.main) { [weak self] _ in self?.pause(reason:"Paused for sleep; choose Resume after wake") })
        // Display sleep, unlike system sleep, keeps everything running.
        for name in [NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) {
              [weak self] _ in self?.holdScanning("displays asleep") })
        }
        for name in [NSWorkspace.screensDidWakeNotification,NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) {
              [weak self] _ in self?.resumeScanning("displays awake") })
        }
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,
          object:nil,queue:.main) { [weak self] _ in self?.scheduleScan() })
        for sig in [SIGTERM,SIGINT] {
            signal(sig,SIG_IGN)
            let source=DispatchSource.makeSignalSource(signal:sig,queue:.main)
            source.setEventHandler { NSApp.terminate(nil) }; source.resume(); signalSources.append(source)
        }
        poll=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
            guard let self=self,self.running else { return }
            if !AXIsProcessTrusted() { self.pause(reason:"Accessibility permission revoked"); return }
            if Date().timeIntervalSince(self.lastResponse)>8 {
                self.pause(reason:"Haskell engine did not respond; restoring owned windows"); return
            }
            if let t=self.axBusySince,Date().timeIntervalSince(t)>8 {
                self.pause(reason:"Accessibility queue did not finish; restoring owned windows"); return
            }
            self.sendObject(["type":"ping"]); self.scheduleScan()
        }
        resume()
    }
    private func makeMenu() {
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        if let url=Bundle.main.url(forResource:"MenuBarIcon",withExtension:"pdf"),
           let icon=NSImage(contentsOf:url) {
            icon.size=NSSize(width:26,height:16)
            icon.isTemplate=true // Follows the menu bar's light and dark styling.
            statusItem.button?.image=icon
            statusItem.button?.imagePosition = .imageLeading
        }
        func item(_ title: String,_ selector: Selector) -> NSMenuItem {
            let i=NSMenuItem(title:title,action:selector,keyEquivalent:"")
            i.target=self
            return i
        }
        func submenu(_ title: String,_ items: [NSMenuItem]) -> NSMenuItem {
            let parent=NSMenuItem(title:title,action:nil,keyEquivalent:"")
            let sub=NSMenu()
            items.forEach { sub.addItem($0) }
            parent.submenu=sub
            return parent
        }
        // Everyday actions at the top; the rest is grouped so the menu stays
        // short. "Pause" already restores hidden windows, so it is one item.
        let menu=NSMenu()
        pauseItem=item("Resume",#selector(togglePause))
        menu.addItem(pauseItem)
        menu.addItem(item("Recompile xmonad.hs",#selector(recompileConfig)))
        menu.addItem(item("Open xmonad.hs",#selector(openConfig)))
        menu.addItem(NSMenuItem.separator())
        suppressItem=item("Disable macOS window shortcuts",#selector(toggleSuppressShortcuts))
        suppressItem.state=suppressShortcuts ? .on : .off
        logKeysItem=item("Log key events",#selector(toggleLogKeys))
        logKeysItem.state=logKeys ? .on : .off
        menu.addItem(submenu("Settings",[suppressItem,logKeysItem]))
        menu.addItem(submenu("Diagnostics",[
          item("Reload compiled xmonad.hs",#selector(reloadEngine)),
          item("Open log",#selector(openLog)),
          item("Write diagnostic snapshot",#selector(dumpSnapshot)),
          item("Run AX self-test",#selector(runSelfTest))]))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Quit XMonadMac",#selector(quitApp)))
        statusItem.menu=menu
        setStatus("Paused")
    }
    private func setStatus(_ text: String) {
        label=text
        statusItem?.button?.title=running ? " \(text)" : " paused"
        statusItem?.button?.toolTip=text
        pauseItem?.title=running ? "Pause" : "Resume"
        let state: [String:Any]=["pid":Int(getpid()),"running":running,"configured":configured,
          "keyboardReady":tapReady,"pointerReady":pointerReady,"nativeFullScreen":fullScreen,"dryRun":dryRun,"recompiling":recompiling,
          "status":text,"epoch":currentEpoch,"generation":latestSent,
          // Published for external bars: sketchybar, Übersicht, a shell loop.
          "workspaces":workspaces.map { ["tag":$0.tag,"windows":$0.windows,
            "current":$0.current,"visible":$0.visible] },
          "updated":Date().timeIntervalSince1970]
        if let data=try? JSONSerialization.data(withJSONObject:state,options:[.prettyPrinted,.sortedKeys]) {
            try? data.write(to:Paths.status,options:.atomic)
        }
    }
    private func updateKeyState() {
        let enabled = !dryRun && running && configured && latestSent >= 0 && !fullScreen
        keyboard.setEnabled(enabled && tapReady)
        keyboard.setSuppressSystemShortcuts(suppressShortcuts)
        keyboard.setLogKeys(logKeys)
        pointer.setEnabled(enabled && pointerReady)
    }
    private func resume() {
        guard !running,!recovering,!quitting else { return }
        guard AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary) else {
            setStatus("Grant Accessibility access to XMonadMac, then quit and relaunch")
            return
        }
        if dryRun && !recoveryDone {
            guard store.journal.entries.isEmpty else {
                setStatus("Pending recovery journal; run --recover before dry-run")
                return
            }
            recoveryDone=true
        }
        if !recoveryDone {
            recovering=true; setStatus("Checking recovery journal")
            let apps=descriptors()
            axQueue.async { [weak self] in
                guard let self=self else { return }
                self.store.recover(apps:apps,displays:displayInfo())
                let remaining=self.store.journal.entries.count
                DispatchQueue.main.async {
                    self.recovering=false
                    if remaining>0 {
                        self.setStatus("\(remaining) unresolved recovery entries; see log and recovery.json")
                        return
                    }
                    self.recoveryDone=true; self.resume()
                }
            }
            return
        }
        running=true; fullScreen=false; configured=false; latestSent = -1
        if !dryRun { keyboard.start(); pointer.start() }; launchEngine(); updateKeyState()
    }
    private func launchEngine() {
        guard running else { return }
        guard FileManager.default.isExecutableFile(atPath:Paths.engine.path) else {
            pause(reason:"Missing compiled engine: run scripts/install.sh"); return
        }
        runToken=UUID(); let token=runToken
        let p=Process(), toEngine=Pipe(), fromEngine=Pipe()
        p.executableURL=Paths.engine
        if dryRun { p.arguments=["--no-startup"] }
        p.standardInput=toEngine; p.standardOutput=fromEngine; p.standardError=FileHandle.standardError
        // Supply an ordinary login-like PATH without interpreting shell startup files.
        var env=ProcessInfo.processInfo.environment
        env["PATH"]="/opt/homebrew/bin:/usr/local/bin:"+(env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        p.environment=env
        p.terminationHandler={ [weak self] proc in
            DispatchQueue.main.async {
                guard let self=self,self.runToken == token,self.running,!self.quitting else { return }
                self.pause(reason:"Haskell engine exited (\(proc.terminationStatus)); restoring owned windows")
            }
        }
        do { try p.run() }
        catch { pause(reason:"Cannot launch Haskell engine: \(error)"); return }
        child=p; input=toEngine.fileHandleForWriting
        configured=false; lastResponse=Date(); sendCheckpoint=true
        setStatus("Starting")
        let handle=fromEngine.fileHandleForReading
        Thread.detachNewThread { [weak self] in
            var buffer=Data()
            do {
                // availableData, not read(upToCount:), which blocks until the
                // full count arrives and would stall on every short line.
                while case let chunk=handle.availableData,!chunk.isEmpty {
                    buffer.append(chunk)
                    guard buffer.count <= 2_097_152 else { throw WireError.invalid("Engine output buffer too large") }
                    while let nl=buffer.firstIndex(of:10) {
                        let line=Data(buffer.prefix(upTo:nl))
                        buffer.removeSubrange(buffer.startIndex...nl)
                        if line.isEmpty { continue }
                        let message=try JSONDecoder().decode(EngineMessage.self,from:line)
                        DispatchQueue.main.async { [weak self] in
                            guard let self=self,self.runToken == token else { return }
                            self.receive(message)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self=self,self.runToken == token else { return }
                    self.pause(reason:"Invalid engine output: \(error)")
                }
            }
            try? handle.close()
        }
    }
    private func stopEngine() {
        runToken=UUID() // Invalidate old output and the old termination callback first.
        configured=false; keyboard.setEnabled(false); pointer.setEnabled(false)
        let old=child; child=nil
        if let h=input { try? h.close() }; input=nil
        if let old=old,old.isRunning {
            old.terminate()
            DispatchQueue.global().asyncAfter(deadline:.now()+2) {
                if old.isRunning { Darwin.kill(old.processIdentifier,SIGKILL) }
            }
        }
    }
    private func send<T: Encodable>(_ event: T) {
        do { try sendData(JSONEncoder().encode(event)) }
        catch { pause(reason:"Cannot encode protocol: \(error)") }
    }
    private func sendObject(_ object: [String:Any]) {
        do { try sendData(JSONSerialization.data(withJSONObject:object)) }
        catch { pause(reason:"Cannot encode protocol: \(error)") }
    }
    private func sendData(_ bytes: Data) throws {
        guard running,let handle=input else { return }
        var line=bytes; line.append(10)
        let token=runToken
        writer.async { [weak self] in
            do { try handle.write(contentsOf:line) }
            catch {
                DispatchQueue.main.async {
                    guard let self=self,self.runToken == token else { return }
                    self.pause(reason:"Engine pipe closed; restoring owned windows")
                }
            }
        }
    }
    private func receive(_ message: EngineMessage) {
        guard running else { return }
        lastResponse=Date()
        switch message {
        case .configure(let version,let keys,let mouse,let look):
            guard version == 1 else { pause(reason:"Protocol version mismatch"); return }
            do { try keyboard.configure(keys); try pointer.configure(bindings:mouse) }
            catch { pause(reason:"Invalid input configuration: \(error)"); return }
            border.configure(width:look.borderWidth,color:look.borderColor,normal:look.normalBorderColor)
            pointer.setHover(look.focusFollowsMouse)
            configured=true; updateKeyState(); scheduleScan()
        case .plan(let plan):
            if logKeys {
                logMessage("plan gen=\(plan.generation)/\(latestSent) epoch=\(plan.epoch)/\(currentEpoch) ws=\(plan.workspace) frames=\(plan.frames.map(\.wid)) hide=\(plan.hide)")
            }
            guard configured,!fullScreen,plan.epoch == currentEpoch,plan.generation == latestSent else { return }
            if dryRun {
                do { try PlanSafety.validate(plan,active:Set(lastSnapshot?.windows.map(\.wid) ?? [])) }
                catch { pause(reason:"Invalid dry-run plan: \(error)"); return }
                workspaces=plan.workspaces ?? []
                logMessage("DRY-RUN workspace=\(plan.workspace) layout=\(plan.layout) frames=\(plan.frames.map { "\($0.wid):\($0.frame)" }) hide=\(plan.hide)")
                setStatus("DRY-RUN \(plan.workspace) · \(plan.layout)")
                return
            }
            checkpoint=plan.checkpoint
            workspaces=plan.workspaces ?? []
            let row=workspaces.isEmpty ? plan.workspace : workspaceRow(workspaces)
            setStatus("\(row) · \(plan.layout)")
            axBusySince=axBusySince ?? Date()
            axQueue.async { [weak self] in
                guard let self=self else { return }
                do {
                    let applied=try self.store.apply(plan)
                    let ack=applied ? self.store.takeAck() : nil
                    let prints=self.store.fingerprints()
                    DispatchQueue.main.async {
                        if self.axBusySince != nil,!self.scanInFlight { self.axBusySince=nil }
                        guard applied,self.running,self.configured else { return }
                        self.tracePlan(plan)
                        if let ack=ack {
                            var obj: [String:Any]=["type":"ack","action":ack.action,"expired":ack.expired]
                            if let focused=ack.focused { obj["focused"]=focused }
                            self.sendObject(obj)
                        }
                        self.persistSession(plan.checkpoint,prints:prints)
                    }
                }
                catch {
                    DispatchQueue.main.async { self.pause(reason:"Unsafe plan rejected: \(error)") }
                }
            }
        case .command(let name,let wid):
            if dryRun { logMessage("DRY-RUN ignored command: \(name)"); return }
            switch name {
            case "close": if let wid=wid { axQueue.async { [weak self] in self?.store.close(wid) } }
            case "recompile": recompileConfig()
            case "reload": reloadEngine()
            case "quit": NSApp.terminate(nil)
            case "pause": pause(reason:"Paused by xmonad.hs")
            default: pause(reason:"Unknown engine command: \(name)")
            }
        case .pong: break
        }
    }
    private func resetPointerCoalescer() {
        pointerPendingPoint=nil; pointerPendingEnd=nil
    }
    private func drainPointerUpdate() {
        guard !pointerUpdateInFlight,let point=pointerPendingPoint else {
            if !pointerUpdateInFlight,let end=pointerPendingEnd { finishPointerDrag(end) }
            return
        }
        pointerPendingPoint=nil; pointerUpdateInFlight=true
        axQueue.async { [weak self] in
            self?.store.updatePointerDrag(to:point)
            DispatchQueue.main.async {
                guard let self=self else { return }
                self.pointerUpdateInFlight=false
                guard self.running else { self.resetPointerCoalescer(); return }
                if let end=self.pointerPendingEnd { self.finishPointerDrag(end) }
                else { self.drainPointerUpdate() }
            }
        }
    }
    private func finishPointerDrag(_ point: CGPoint) {
        guard !pointerUpdateInFlight else { pointerPendingEnd=point; return }
        pointerPendingPoint=nil; pointerPendingEnd=nil; pointerUpdateInFlight=true
        axQueue.async { [weak self] in
            guard let self=self else { return }
            _=self.store.endPointerDrag(at:point)
            DispatchQueue.main.async {
                self.pointerUpdateInFlight=false
                guard self.running else { self.resetPointerCoalescer(); return }
                self.scheduleScan(); self.drainPointerUpdate()
            }
        }
    }
    // Draw borders where this observation says they belong. An empty rest
    // clears unfocused overlays; it must not reuse the previous workspace.
    private func paintBorders(focused: (UInt64,Rect)?, rest: [(UInt64,Rect)]) {
        border.paint(focused:focused,rest:rest)
    }
    private func traceFocus(_ result: ScanResult, displays: [DisplayInfo]) {
        guard running,configured,!fullScreen else { borderPin=nil; border.hide(); return }
        let visible=result.windows.filter { tracesFocusBorder($0,displays:displays) }
        let rest=visible.map { ($0.wid,$0.frame) }
        if let pin=borderPin {
            if let window=result.windows.first(where:{ $0.wid == pin }),
               tracesFocusBorder(window,displays:displays,pinned:true) {
                paintBorders(focused:(pin,window.frame),rest:rest)
                hoverWid=pin
                if !window.ownedHidden,result.focused == pin { borderPin=nil }
                return
            }
            borderPin=nil
        }
        if let wid=result.focused,
           let window=result.windows.first(where:{ $0.wid == wid }),
           tracesFocusBorder(window,displays:displays) {
            paintBorders(focused:(wid,window.frame),rest:rest)
            hoverWid=wid
            return
        }
        hoverWid=result.focused
        paintBorders(focused:nil,rest:rest)
    }
    private func tracePlan(_ plan: Plan) {
        guard running,configured,!fullScreen else { return }
        let rest=plan.frames.map { ($0.wid,$0.frame) }
        if let id=plan.focus,let chosen=plan.frames.first(where:{ $0.wid == id }) {
            borderPin=id
            paintBorders(focused:(id,chosen.frame),rest:rest)
            hoverWid=id
            return
        }
        if let id=borderPin ?? hoverWid,plan.hide.contains(id) {
            borderPin=nil; hoverWid=nil
        }
        let focus=(borderPin ?? hoverWid).flatMap { id in rest.first { $0.0 == id } }
        paintBorders(focused:focus,rest:rest)
    }
    // Focus follows the mouse: the helper only reports it when the config asked
    // for it, and policy decides whether the window may take focus.
    private func handleHover(_ point: CGPoint) {
        guard running,configured,!dryRun,!fullScreen else { return }
        axQueue.async { [weak self] in
            guard let self=self else { return }
            let wid=self.store.window(at:point)
            DispatchQueue.main.async {
                guard self.running,let wid=wid,wid != self.hoverWid else { return }
                self.hoverWid=wid
                self.sendObject(["type":"pointerFocus","wid":wid])
            }
        }
    }
    private func handlePointer(mode: PointerMode,phase: PointerPhase,point: CGPoint) {
        guard running,configured,!dryRun,!fullScreen else { return }
        switch phase {
        case .begin:
            if mode == .raise {
                axQueue.async { [weak self] in
                    let wid=self?.store.window(at:point)
                    DispatchQueue.main.async {
                        guard let self=self,self.running,let wid=wid else { return }
                        self.sendObject(["type":"pointerFocus","wid":wid])
                    }
                }
                return
            }
            resetPointerCoalescer()
            axQueue.async { [weak self] in
                guard let self=self else { return }
                let wid=self.store.beginPointerDrag(at:point,mode:mode)
                DispatchQueue.main.async {
                    guard self.running else { return }
                    guard let wid=wid else {
                        self.pointer.cancelGesture(); self.resetPointerCoalescer(); return
                    }
                    self.sendObject(["type":"mouseFloat","wid":wid])
                    self.scheduleScan()
                }
            }
        case .drag:
            guard pointerPendingEnd == nil else { return }
            pointerPendingPoint=point; drainPointerUpdate()
        case .end:
            pointerPendingPoint=nil; pointerPendingEnd=point
            if !pointerUpdateInFlight { finishPointerDrag(point) }
        }
    }
    private func scheduleScan() {
        guard running,configured,!quitting else { return }
        if scanInFlight { scanAgain=true; return }
        if scanWork != nil { return } // Bound debounce latency instead of resetting forever.
        let work=DispatchWorkItem { [weak self] in self?.scanWork=nil; self?.performScan() }
        scanWork=work; DispatchQueue.main.asyncAfter(deadline:.now()+0.08,execute:work)
    }
    private func performScan() {
        guard running,configured,!scanInFlight else { return }
        guard Date() >= settledAt else { return }
        let displays=displayInfo()
        guard !displays.isEmpty else { return }
        // An empty application list means the system is not answering yet,
        // as after a display wake. Scanning on it would report a world with no
        // windows in it.
        let apps=descriptors()
        guard !apps.isEmpty else { scheduleScan(); return }
        scanInFlight=true; scanAgain=false; sequence += 1
        axBusySince=axBusySince ?? Date()
        let seq=sequence, ep=currentEpoch, token=runToken
        axQueue.async { [weak self] in
            guard let self=self else { return }
            let result=self.store.scan(apps:apps,displays:displays,generation:seq,epoch:ep)
            let prints=self.store.fingerprints()
            DispatchQueue.main.async {
                self.scanInFlight=false
                if self.axBusySince != nil { self.axBusySince=nil }
                guard self.running,self.configured,self.runToken == token,self.currentEpoch == ep else {
                    if self.running { self.scheduleScan() }; return
                }
                self.fullScreen=result.nativeFullScreen
                self.updateKeyState()
                self.traceFocus(result,displays:displays)
                if self.fullScreen {
                    self.setStatus("Native full-screen; tiling suspended")
                } else {
                    var restore=self.sendCheckpoint ? self.checkpoint : nil
                    if self.sendCheckpoint,restore==nil {
                        restore=self.loadSession(prints:prints,epoch:ep)
                    }
                    let snapshot=Snapshot(generation:seq,epoch:ep,screens:displays,
                      windows:result.windows,focused:result.focused,restore:restore)
                    self.sendCheckpoint=false; self.latestSent=seq; self.lastSnapshot=snapshot
                    self.send(snapshot); self.updateKeyState()
                    if self.dumpNext { self.dumpNext=false; self.writeSnapshot(snapshot) }
                }
                if self.scanAgain { self.scheduleScan() }
            }
        }
    }
    // Stop observing until the world is trustworthy again. Plans already in
    // flight are dropped by the generation check, and nothing is moved or
    // hidden while this holds.
    private func holdScanning(_ reason: String) {
        settledAt = .distantFuture
        logMessage("Scanning held: \(reason)")
    }
    private func resumeScanning(_ reason: String) {
        settledAt = Date().addingTimeInterval(2)
        store?.displaysWoke()
        logMessage("Scanning resumes in 2s: \(reason)")
        DispatchQueue.main.asyncAfter(deadline:.now()+2.1) { [weak self] in self?.scheduleScan() }
    }
    private func spaceChanged() {
        currentEpoch += 1; checkpoint=nil; latestSent = -1; fullScreen=false
        borderPin=nil
        let ep=currentEpoch
        keyboard.setEnabled(false); pointer.setEnabled(false)
        axQueue.async { [weak self] in
            self?.store.restoreAll(); self?.store.invalidate(epoch:ep)
            DispatchQueue.main.async { self?.scheduleScan() }
        }
    }
    private func pause(reason: String) {
        running=false; scanWork?.cancel(); scanWork=nil; scanAgain=false; resetPointerCoalescer()
        borderPin=nil; border.hide()
        stopEngine(); setStatus(reason); logMessage(reason)
        if store != nil { axQueue.async { [weak self] in self?.store.cancelPointerDrag(); self?.store.restoreAll() } }
    }
    @objc private func toggleLogKeys() {
        logKeys = !logKeys
        UserDefaults.standard.set(logKeys,forKey:logKeysDefaultsKey)
        logKeysItem?.state=logKeys ? .on : .off
        updateKeyState()
    }
    @objc private func toggleSuppressShortcuts() {
        suppressShortcuts = !suppressShortcuts
        UserDefaults.standard.set(suppressShortcuts,forKey:suppressDefaultsKey)
        suppressItem?.state=suppressShortcuts ? .on : .off
        updateKeyState()
    }
    @objc private func togglePause() { if running { pause(reason:"Paused; restoring owned windows") } else { resume() } }
    @objc private func reloadEngine() {
        guard !recompiling else { return }
        guard running else { resume(); return }
        stopEngine(); latestSent = -1; launchEngine(); scheduleScan()
    }
    @objc private func recompileConfig() {
        guard !recompiling,!quitting else { return }
        guard FileManager.default.isExecutableFile(atPath:Paths.engine.path) else {
            setStatus("Installed engine missing; rerun make install")
            return
        }
        guard FileManager.default.fileExists(atPath:Paths.config.path) else {
            setStatus("Config missing: \(Paths.config.path)")
            return
        }
        recompiling=true
        let wasRunning=running
        setStatus("Compiling xmonad.hs")
        let p=Process()
        p.executableURL=Paths.engine
        p.arguments=["--recompile",Paths.config.path]
        p.standardOutput=FileHandle.standardError
        p.standardError=FileHandle.standardError
        var env=ProcessInfo.processInfo.environment
        env["PATH"]="/opt/homebrew/bin:/usr/local/bin:"+(env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        p.environment=env
        p.terminationHandler={ [weak self] proc in
            DispatchQueue.main.async {
                guard let self=self,self.compiler === proc else { return }
                self.compiler=nil; self.recompiling=false
                if proc.terminationStatus == 0 {
                    if wasRunning && self.running { self.reloadEngine() }
                    else { self.setStatus("Compiled xmonad.hs; Resume to use it") }
                } else {
                    self.setStatus("Compile failed; current engine unchanged (see log)")
                }
            }
        }
        do { try p.run(); compiler=p }
        catch {
            recompiling=false; compiler=nil
            setStatus("Cannot start config compiler: \(error)")
        }
    }
    @objc private func openConfig() {
        if FileManager.default.fileExists(atPath:Paths.config.path) { NSWorkspace.shared.open(Paths.config) }
        else { setStatus("Config missing: \(Paths.config.path)") }
    }
    @objc private func dumpSnapshot() {
        if let s=lastSnapshot { writeSnapshot(s) }
        else { dumpNext=true; scheduleScan() }
    }
    private func writeSnapshot(_ s: Snapshot) {
        let path=Paths.support.appendingPathComponent("diagnostic-snapshot.json")
        do {
            let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(s).write(to:path,options:.atomic)
            logMessage("Diagnostic snapshot written to \(path.path) (contains window titles)")
        } catch { logMessage("Snapshot write failed: \(error)") }
    }
    @objc private func runSelfTest() {
        setStatus("Running AX self-test")
        axQueue.async { [weak self] in
            guard let self=self else { return }
            let report=runAXSelfTest()
            do {
                let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
                try encoder.encode(report).write(to:Paths.selfTest,options:.atomic)
            } catch { logMessage("Self-test report write failed: \(error)") }
            DispatchQueue.main.async {
                self.setStatus(report.passed ? "AX self-test passed" : "AX self-test failed; see self-test.json")
            }
        }
    }
    @objc private func openLog() { NSWorkspace.shared.open(Paths.log) }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func receivedCommand(_ notification: Notification) {
        guard let command=notification.userInfo?["command"] as? String else { return }
        switch command {
        case "pause": pause(reason:"Paused from command line")
        case "resume": resume()
        case "reload": reloadEngine()
        case "recompile": recompileConfig()
        case "recover": pause(reason:"Paused; restoring hidden windows")
        case "dump": dumpSnapshot()
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateNow }
        quitting=true; running=false; poll?.invalidate(); scanWork?.cancel()
        if let compiler=compiler,compiler.isRunning { compiler.terminate() }
        self.compiler=nil; recompiling=false
        stopEngine(); keyboard.stop(); pointer.stop()
        guard store != nil else { return .terminateNow }
        // terminateLater needs its reply from the main queue, and the nested
        // event loop AppKit runs while waiting does not drain main-queue work,
        // so both the reply and its timeout were stranded and Quit hung for
        // good. AX is externally controlled, so bound the wait here instead.
        let restored=DispatchSemaphore(value:0)
        axQueue.async { [weak self] in self?.store.restoreAll(); restored.signal() }
        _=restored.wait(timeout:.now()+4)
        return .terminateNow
    }
    private func persistSession(_ checkpoint: JSONValue, prints: [WindowPrint]) {
        let file=SessionFile(checkpoint:checkpoint,prints:prints)
        do {
            let data=try JSONEncoder().encode(file)
            try data.write(to:Paths.session,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:Paths.session.path)
        } catch { logMessage("Session write failed: \(error)") }
    }
    private func loadSession(prints: [WindowPrint], epoch: Int) -> JSONValue? {
        guard let data=try? Data(contentsOf:Paths.session),
              let file=try? JSONDecoder().decode(SessionFile.self,from:data) else { return nil }
        let map=matchWindowPrints(old:file.prints,new:prints)
        guard !map.isEmpty else { return nil }
        return remapCheckpoint(file.checkpoint,map:map,epoch:epoch)
    }
    func applicationWillTerminate(_ notification: Notification) {
        if lockFD >= 0 {
            try? FileManager.default.removeItem(at:Paths.status)
            close(lockFD)
        }
    }
}

@main
struct XMonadMacMain {
    static func main() {
        umask(0o077); signal(SIGPIPE,SIG_IGN)
        let args=CommandLine.arguments
        do { try Paths.prepare() } catch { fputs("\(error)\n",stderr); exit(1) }
        if let i=args.firstIndex(of:"--validate-config"),i+1<args.count {
            do {
                let data=try Data(contentsOf:URL(fileURLWithPath:args[i+1]))
                guard case .configure(let version,let keys,let mouse,_)=try JSONDecoder().decode(EngineMessage.self,from:data), version == 1 else {
                    throw WireError.invalid("Expected protocol-1 configure object")
                }
                for key in keys { try validateBinding(key) }; try validateMouseBindings(mouse)
                guard Set(keys).count == keys.count else { throw WireError.invalid("Duplicate key bindings") }
                print("Validated \(keys.count) native key bindings")
                return
            } catch { fputs("Configuration: \(error)\n",stderr); exit(1) }
        }
        if args.contains("--self-test") {
            let report=runAXSelfTest()
            let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            do {
                let data=try encoder.encode(report)
                try data.write(to:Paths.selfTest,options:.atomic)
                FileHandle.standardOutput.write(data); print("")
                exit(report.passed ? 0 : 2)
            } catch { fputs("Self-test: \(error)\n",stderr); exit(1) }
        }
        if args.contains("--diagnose") {
            let info: [String:Any]=["macOS":ProcessInfo.processInfo.operatingSystemVersionString,
              "accessibility":AXIsProcessTrusted(),"engine":Paths.engine.path,
              "engineExecutable":FileManager.default.isExecutableFile(atPath:Paths.engine.path),
              "journalExists":FileManager.default.fileExists(atPath:Paths.recovery.path),
              "config":Paths.config.path,
              "log":Paths.log.path,"status":Paths.status.path]
            let data=try! JSONSerialization.data(withJSONObject:info,options:[.prettyPrinted,.sortedKeys])
            FileHandle.standardOutput.write(data); print(""); return
        }
        let commands=["pause","resume","reload","recompile","recover","dump","quit"]
        if let command=commands.first(where:{ args.contains("--"+$0) }) {
            if command == "recover",let probe=try? acquireLock() {
                close(probe)
                // Recover the previous session without starting the Haskell engine.
                standaloneRecovery(); return
            }
            DistributedNotificationCenter.default().postNotificationName(commandNotification,
              object:String(getuid()),userInfo:["command":command],deliverImmediately:true)
            return
        }
        if args.contains("--recover-only") { standaloneRecovery(); return }
        let application=NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate=AppDelegate(); application.delegate=delegate
        withExtendedLifetime(delegate) { application.run() }
    }
    private static func standaloneRecovery() {
        guard AXIsProcessTrusted() else {
            fputs("Grant Accessibility access to the installed XMonadMac app first.\n",stderr); exit(1)
        }
        do {
            let fd=try acquireLock(); defer { close(fd) }
            let journal=try RecoveryJournal(Paths.recovery)
            let store=AXStore(journal:journal,relay:NotificationRelay())
            store.recover(apps:descriptors(),displays:displayInfo())
            print("Unresolved recovery entries: \(journal.entries.count)")
            if !journal.entries.isEmpty { exit(2) }
        } catch { fputs("Recovery: \(error)\n",stderr); exit(1) }
    }
}
#endif
