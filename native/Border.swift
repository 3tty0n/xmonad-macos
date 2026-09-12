#if os(macOS)
import AppKit

// A window belonging to another application cannot be given a border, so the
// focused one is traced by a click-through overlay of our own that follows it.
final class BorderOverlay {
    private var panel: NSPanel?
    private var width=0
    private var color=NSColor.systemRed
    private var current: Rect?
    private var currentWid: UInt64?

    func configure(width: Int, color hex: String) {
        self.width=max(0,min(width,16))
        self.color=BorderOverlay.parse(hex) ?? .systemRed
        if self.width == 0 { hide() }
        else if let r=current,let id=currentWid { current=nil; show(r,wid:id) }
    }
    // Top-left global coordinates, as everything else in the bridge uses.
    func show(_ rect: Rect, wid: UInt64) {
        guard width > 0 else { return }
        let p=panel ?? make()
        if rect != current {
            current=rect
            p.setFrame(BorderOverlay.appKitFrame(rect,inset:CGFloat(width)),display:true)
        }
        // Raise on every observation. Full stacks every window at the same
        // frame; Electron sits at pop-up level; Chrome reorders its content
        // window above a same-level overlay on each keystroke. alphaValue, not
        // orderOut: re-inserting the panel after a workspace switch is what
        // made the border lag the windows that were already back.
        currentWid=wid
        p.alphaValue=1
        p.orderFrontRegardless()
    }
    func hide() {
        current=nil
        currentWid=nil
        panel?.alphaValue=0
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
        // floatingWindow (3) sits under Electron's pop-up-level (101) content
        // windows. overlayWindow (102) is the public level above those.
        p.level=NSWindow.Level(Int(CGWindowLevelForKey(.overlayWindow)))
        p.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle,.fullScreenNone]
        let view=BorderView()
        view.owner=self
        p.contentView=view
        panel=p
        return p
    }
    fileprivate var stroke: (NSColor,CGFloat) { (color,CGFloat(width)) }

    // AppKit measures from the bottom-left of the primary display; the bridge
    // measures from its top-left. The overlay sits just outside the window.
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
    weak var owner: BorderOverlay?
    override func draw(_ dirty: NSRect) {
        guard let (color,width)=owner?.stroke,width > 0 else { return }
        // macOS windows are rounded, so a square trace would show at the corners.
        let path=NSBezierPath(roundedRect:bounds.insetBy(dx:width/2,dy:width/2),
                              xRadius:10,yRadius:10)
        path.lineWidth=width
        color.setStroke()
        path.stroke()
    }
}
#endif
