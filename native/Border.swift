#if os(macOS)
import AppKit
import QuartzCore

// One window and the width its border is drawn at in this pass. A layout may
// ask for a narrower border or for none at all.
struct BorderSpec { var wid: UInt64; var rect: Rect; var width: Int }

// A window belonging to another application cannot be given a border, so the
// helper traces them with click-through overlays of its own.
final class BorderOverlay {
    private(set) var width=0
    private var focusedColor=NSColor.systemRed
    private var normalColor=NSColor(white:0.85,alpha:1)
    // Each window keeps its own overlay across focus changes, so moving focus
    // only recolours two frames instead of swapping panels between windows.
    private var panels: [UInt64:NSPanel]=[:]
    private var focusedWid: UInt64?
    private var spare: [NSPanel]=[]
    private static let overlayLevel=Int(CGWindowLevelForKey(.dockWindow)) - 1

    func configure(width: Int, color hex: String, normal: String = "#dddddd") {
        self.width=max(0,min(width,16))
        self.focusedColor=BorderOverlay.parse(hex) ?? .systemRed
        self.normalColor=BorderOverlay.parse(normal) ?? NSColor(white:0.85,alpha:1)
        if self.width == 0 { hide() }
    }
    func show(_ rect: Rect, wid: UInt64) {
        paint(focused:BorderSpec(wid:wid,rect:rect,width:width),rest:[])
    }
    func paint(focused: BorderSpec?, rest: [BorderSpec]) {
        // The hole is cut from the focused window's rectangle as if it kept the
        // configured width, so a borderless focused window still is not covered
        // by the unfocused frames around it.
        let inset=CGFloat(width)
        let focusedFrame=focused.map {
            BorderOverlay.appKitFrame($0.rect,inset:inset)
        }
        var next: [UInt64:NSPanel]=[:]
        if let spec=focused, spec.width > 0 {
            next[spec.wid]=place(panels.removeValue(forKey:spec.wid),spec:spec,
                                 color:focusedColor,exclude:nil,front:true)
        }
        let skip=focused?.wid
        for spec in rest where spec.wid != skip && spec.width > 0
                             && next[spec.wid] == nil {
            let overlay=BorderOverlay.appKitFrame(spec.rect,inset:CGFloat(spec.width))
            let hole=focusedFrame.flatMap {
                BorderOverlay.hole(in:overlay,cutting:$0)
            }
            next[spec.wid]=place(panels.removeValue(forKey:spec.wid),spec:spec,
                                 color:normalColor,exclude:hole,front:false)
        }
        for p in panels.values { retire(p) }
        panels=next
        focusedWid=focused.flatMap { next[$0.wid] == nil ? nil : $0.wid }
        // Unfocused frames are placed after the focused overlay, so raise it
        // again: a floating window's content must sit above those white frames.
        if let wid=focusedWid { panels[wid]?.orderFrontRegardless() }
    }
    func hide() {
        for p in panels.values { retire(p) }
        panels=[:]
        focusedWid=nil
    }
    // The view is updated and drawn before the panel becomes visible or moves,
    // so the window server never composites a frame with stale content.
    private func place(_ existing: NSPanel?, spec: BorderSpec, color: NSColor,
                       exclude: NSRect?, front: Bool) -> NSPanel {
        let p=existing ?? spare.popLast() ?? make()
        let frame=BorderOverlay.appKitFrame(spec.rect,inset:CGFloat(spec.width))
        let level=NSWindow.Level(BorderOverlay.overlayLevel - (front ? 0 : 1))
        let hidden=p.alphaValue == 0
        if p.level != level { p.level=level }
        if let view=p.contentView as? BorderView,
           view.update(color:color,lineWidth:CGFloat(spec.width),exclude:exclude)
             || p.frame != frame {
            if p.frame != frame { p.setFrame(frame,display:false) }
            view.display()
        }
        if hidden {
            p.alphaValue=1
            p.orderFrontRegardless()
        }
        return p
    }
    private func retire(_ p: NSPanel) {
        p.alphaValue=0
        p.setFrame(.zero,display:false)
        spare.append(p)
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
        p.level=NSWindow.Level(BorderOverlay.overlayLevel)
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
    private var color=NSColor.systemRed
    private var lineWidth: CGFloat=1
    private var exclude: NSRect?
    // Reports whether anything changed, so an unchanged frame is not redrawn.
    func update(color: NSColor, lineWidth: CGFloat, exclude: NSRect?) -> Bool {
        guard color != self.color || lineWidth != self.lineWidth
                || exclude != self.exclude else { return false }
        self.color=color
        self.lineWidth=lineWidth
        if exclude != self.exclude { self.exclude=exclude; updateMask() }
        return true
    }
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.mask=mask
        CATransaction.commit()
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
