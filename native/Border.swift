#if os(macOS)
import AppKit
import QuartzCore

// A window belonging to another application cannot be given a border, so the
// helper traces them with click-through overlays of its own.
final class BorderOverlay {
    private var width=0
    private var focusedColor=NSColor.systemRed
    private var normalColor=NSColor(white:0.85,alpha:1)
    private var focused: NSPanel?
    private var others: [UInt64:NSPanel]=[:]
    private var spare: [NSPanel]=[]

    func configure(width: Int, color hex: String, normal: String = "#dddddd") {
        self.width=max(0,min(width,16))
        self.focusedColor=BorderOverlay.parse(hex) ?? .systemRed
        self.normalColor=BorderOverlay.parse(normal) ?? NSColor(white:0.85,alpha:1)
        if self.width == 0 { hide() }
    }
    func show(_ rect: Rect, wid: UInt64) { paint(focused:(wid,rect),rest:[]) }
    func paint(focused: (UInt64,Rect)?, rest: [(UInt64,Rect)]) {
        guard width > 0 else { hide(); return }
        let inset=CGFloat(width)
        let focusedFrame=focused.map { BorderOverlay.appKitFrame($0.1,inset:inset) }
        if let (_,rect)=focused {
            self.focused=place(self.focused,rect:rect,color:focusedColor,exclude:nil,front:true)
        } else { retire(&self.focused) }
        let skip=focused?.0
        var next: [UInt64:NSPanel]=[:]
        for (id,rect) in rest where id != skip {
            let overlay=BorderOverlay.appKitFrame(rect,inset:inset)
            let hole=focusedFrame.flatMap { BorderOverlay.hole(in:overlay,cutting:$0) }
            next[id]=place(others.removeValue(forKey:id),rect:rect,color:normalColor,exclude:hole,front:false)
        }
        for p in others.values { retire(p); spare.append(p) }
        others=next
        // Unfocused frames are placed after the focused overlay, so raise it
        // again: a floating window's content must sit above those white frames.
        self.focused?.orderFrontRegardless()
    }
    func hide() {
        retire(&focused)
        for p in others.values { retire(p); spare.append(p) }
        others=[:]
        spare.forEach(retire)
    }
    private func place(_ existing: NSPanel?, rect: Rect, color: NSColor, exclude: NSRect?, front: Bool) -> NSPanel {
        let overlayLevel=Int(CGWindowLevelForKey(.overlayWindow))
        let p=existing ?? spare.popLast() ?? make()
        p.setFrame(BorderOverlay.appKitFrame(rect,inset:CGFloat(width)),display:true)
        // Unfocused frames stay just under the focused overlay. Both remain at
        // public overlay levels so Electron content cannot cover them, but a
        // hole is clipped where they would paint over the focused window.
        p.level=NSWindow.Level(overlayLevel - (front ? 0 : 1))
        let view=p.contentView as? BorderView
        view?.color=color
        view?.lineWidth=CGFloat(width)
        view?.exclude=exclude
        view?.needsDisplay=true
        p.alphaValue=1
        p.orderFrontRegardless()
        return p
    }
    private func retire(_ panel: inout NSPanel?) {
        if let p=panel { retire(p); spare.append(p) }
        panel=nil
    }
    private func retire(_ p: NSPanel) {
        p.alphaValue=0
        p.setFrame(.zero,display:false)
    }
    private func make() -> NSPanel {
        let p=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],
                      backing:.buffered,defer:false)
        p.isOpaque=false
        p.backgroundColor = .clear
        p.hasShadow=false
        p.ignoresMouseEvents=true
        p.hidesOnDeactivate=false
        p.isReleasedWhenClosed=false
        p.animationBehavior = .none
        p.alphaValue=0
        p.level=NSWindow.Level(Int(CGWindowLevelForKey(.overlayWindow)))
        p.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle,.fullScreenNone]
        p.contentView=BorderView()
        return p
    }

    static func appKitFrame(_ r: Rect,inset: CGFloat) -> NSRect {
        let top=(NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?
          .frame.maxY ?? 0
        return NSRect(x:CGFloat(r.x)-inset,y:top-CGFloat(r.y+r.height)-inset,
                      width:CGFloat(r.width)+inset*2,height:CGFloat(r.height)+inset*2)
    }
    // Overlay-local rectangle to clip out of an unfocused frame so the focused
    // window (and its own overlay) is not covered. Nil when they do not overlap.
    static func hole(in overlay: NSRect, cutting other: NSRect) -> NSRect? {
        let hit=overlay.intersection(other.insetBy(dx:-1,dy:-1))
        guard !hit.isNull, hit.width > 0.5, hit.height > 0.5 else { return nil }
        return NSRect(x:hit.minX-overlay.minX,y:hit.minY-overlay.minY,
                      width:hit.width,height:hit.height)
    }
    static func parse(_ hex: String) -> NSColor? {
        var text=hex.trimmingCharacters(in:.whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6,let value=UInt32(text,radix:16) else { return nil }
        return NSColor(srgbRed:CGFloat((value>>16)&0xff)/255,
                       green:CGFloat((value>>8)&0xff)/255,
                       blue:CGFloat(value&0xff)/255,alpha:1)
    }
}

private final class BorderView: NSView {
    var color=NSColor.systemRed
    var lineWidth: CGFloat=1
    var exclude: NSRect? { didSet { updateMask(); needsDisplay=true } }
    override init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
        wantsLayer=true
        layer?.isOpaque=false
        layer?.backgroundColor=CGColor.clear
    }
    required init?(coder: NSCoder) { fatalError("BorderView") }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateMask()
    }
    private func updateMask() {
        guard let hole=exclude, hole.width > 0, hole.height > 0 else {
            layer?.mask=nil
            return
        }
        let path=CGMutablePath()
        path.addRect(bounds)
        path.addRect(hole)
        let mask=CAShapeLayer()
        mask.fillRule = .evenOdd
        mask.path=path
        layer?.mask=mask
    }
    override func draw(_ dirty: NSRect) {
        guard lineWidth > 0 else { return }
        let path=NSBezierPath(roundedRect:bounds.insetBy(dx:lineWidth/2,dy:lineWidth/2),
                              xRadius:10,yRadius:10)
        path.lineWidth=lineWidth
        color.setStroke()
        path.stroke()
    }
}
#endif
