#if os(macOS)
import AppKit

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
        if let (id,rect)=focused { self.focused=place(self.focused,rect:rect,color:focusedColor,wid:id) }
        else { retire(&self.focused) }
        let skip=focused?.0
        var next: [UInt64:NSPanel]=[:]
        for (id,rect) in rest where id != skip {
            next[id]=place(others.removeValue(forKey:id),rect:rect,color:normalColor,wid:id)
        }
        for p in others.values { retire(p); spare.append(p) }
        others=next
    }
    func hide() {
        retire(&focused)
        for p in others.values { retire(p); spare.append(p) }
        others=[:]
        spare.forEach(retire)
    }
    private func place(_ existing: NSPanel?, rect: Rect, color: NSColor, wid: UInt64) -> NSPanel {
        _=wid
        let p=existing ?? spare.popLast() ?? make()
        p.setFrame(BorderOverlay.appKitFrame(rect,inset:CGFloat(width)),display:true)
        (p.contentView as? BorderView)?.color=color
        (p.contentView as? BorderView)?.lineWidth=CGFloat(width)
        p.contentView?.needsDisplay=true
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
