import Foundation

// Protocol and safety logic have no AppKit dependency and are tested on Linux.
struct Rect: Codable, Equatable {
    var x: Int, y: Int, width: Int, height: Int
    func near(_ other: Rect, tolerance: Int = 2) -> Bool {
        abs(x-other.x) <= tolerance && abs(y-other.y) <= tolerance &&
        abs(width-other.width) <= tolerance && abs(height-other.height) <= tolerance
    }
    var valid: Bool {
        abs(Double(x)) < 1_000_000 && abs(Double(y)) < 1_000_000 &&
        width > 0 && height > 0 && width < 100_000 && height < 100_000
    }
    static func quartz(appKit r: Rect, primaryTop: Int) -> Rect {
        Rect(x: r.x, y: primaryTop-r.y-r.height, width: r.width, height: r.height)
    }
    func intersectionArea(_ other: Rect) -> Double {
        let w = max(0, min(x+width,other.x+other.width)-max(x,other.x))
        let h = max(0, min(y+height,other.y+other.height)-max(y,other.y))
        return Double(w)*Double(h)
    }
}
struct DisplayInfo: Codable, Equatable { var display: Int; var usable: Rect }
struct WindowInfo: Codable, Equatable {
    var wid: UInt64, pid: Int32
    var app: String, bundle: String, titleText: String
    var onDisplay: Int, frame: Rect
    var minimized: Bool, ownedHidden: Bool
}
struct Snapshot: Encodable {
    let type = "snapshot"
    var generation: Int, epoch: Int, screens: [DisplayInfo], windows: [WindowInfo]
    var focused: UInt64?
    var restore: JSONValue?
}
struct KeyBinding: Codable, Hashable { var mask: Int; var sym: Int }
struct Placement: Codable { var wid: UInt64; var frame: Rect }
struct WorkspaceInfo: Codable, Equatable {
    var tag: String, windows: Int, current: Bool, visible: Bool
}
struct Plan: Decodable {
    var generation: Int, epoch: Int, frames: [Placement], hide: [UInt64]
    var focus: UInt64?, workspace: String, layout: String, checkpoint: JSONValue
    var workspaces: [WorkspaceInfo]?
    var screen: Int?
}
// xmobar-style row: every workspace that holds windows, plus the current one.
// "[2]" is current, a bare tag has windows, so an empty desktop stays quiet.
func workspaceRow(_ all: [WorkspaceInfo]) -> String {
    let shown = all.filter { $0.windows > 0 || $0.current || $0.visible }
    return shown.map { w in
        w.current ? "[\(w.tag)]" : (w.visible ? "(\(w.tag))" : w.tag)
    }.joined(separator: " ")
}
enum JSONValue: Codable {
    case object([String:JSONValue]), array([JSONValue]), string(String)
    case number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String:JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}
enum WireError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { if case .invalid(let s) = self { return s }; return "invalid" }
}
enum EngineMessage: Decodable {
    case configure(Int, [KeyBinding], Int), plan(Plan), command(String, UInt64?), pong
    private enum CodingKeys: String, CodingKey { case type, `protocol`, keys, mouseMask, name, wid }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "configure": self = .configure(try c.decode(Int.self,forKey:.protocol),
                                             try c.decode([KeyBinding].self,forKey:.keys),
                                             try c.decodeIfPresent(Int.self,forKey:.mouseMask) ?? 0)
        case "plan": self = .plan(try Plan(from: decoder))
        case "command": self = .command(try c.decode(String.self,forKey:.name),
                                         try c.decodeIfPresent(UInt64.self,forKey:.wid))
        case "pong": self = .pong
        default: throw WireError.invalid("Unknown engine message")
        }
    }
}
struct PlanSafety {
    static func validate(_ p: Plan, active: Set<UInt64>) throws {
        let shown = p.frames.map(\.wid)
        guard shown.count <= 10_000, p.hide.count <= 10_000 else {
            throw WireError.invalid("Unreasonable plan size")
        }
        guard Set(shown).count == shown.count, Set(p.hide).count == p.hide.count else {
            throw WireError.invalid("Duplicate window IDs in plan")
        }
        guard Set(shown).isDisjoint(with: Set(p.hide)) else {
            throw WireError.invalid("A window cannot be shown and hidden simultaneously")
        }
        guard Set(shown+p.hide).isSubset(of: active) else {
            throw WireError.invalid("Plan refers to windows outside the current snapshot")
        }
        guard p.frames.allSatisfy({ $0.frame.valid }) else {
            throw WireError.invalid("Invalid rectangle in plan")
        }
        if let focus = p.focus, !shown.contains(focus) {
            throw WireError.invalid("Focus target is hidden")
        }
    }
}
func bestDisplay(for rect: Rect, in displays: [DisplayInfo]) -> Int {
    guard let first = displays.first else { return 0 }
    var best = first, area = -1.0, distance = Double.greatestFiniteMagnitude
    for d in displays {
        let a = rect.intersectionArea(d.usable)
        let dx = Double(rect.x)+Double(rect.width)/2-Double(d.usable.x)-Double(d.usable.width)/2
        let dy = Double(rect.y)+Double(rect.height)/2-Double(d.usable.y)-Double(d.usable.height)/2
        let dist = dx*dx+dy*dy
        if a > area || (a == area && dist < distance) { best=d; area=a; distance=dist }
    }
    return best.display
}

// Keysyms are translated to physical ANSI/JIS letter-key positions, not text.
// This avoids Option-generated characters and preserves modifier-release behavior.
let keyCodeForSym: [Int:UInt16] = {
    let pairs: [(Character,UInt16)] = [
        ("a",0),("s",1),("d",2),("f",3),("h",4),("g",5),("z",6),("x",7),
        ("c",8),("v",9),("b",11),("q",12),("w",13),("e",14),("r",15),
        ("y",16),("t",17),("1",18),("2",19),("3",20),("4",21),("6",22),
        ("5",23),("=",24),("9",25),("7",26),("-",27),("8",28),("0",29),
        ("]",30),("o",31),("u",32),("[",33),("i",34),("p",35),("l",37),
        ("j",38),("'",39),("k",40),(";",41),("\\",42),(",",43),("/",44),
        ("n",45),("m",46),(".",47),(" ",49),("`",50)]
    var map = Dictionary(uniqueKeysWithValues: pairs.map { (Int($0.0.asciiValue!),$0.1) })
    for (s,k) in [(0xff0d,36),(0xff09,48),(0xff08,51),(0xff1b,53),
                   (0xffff,117),(0xff51,123),(0xff52,126),(0xff53,124),(0xff54,125),
                   (0xff50,115),(0xff57,119),(0xff55,116),(0xff56,121)] {
        map[s] = UInt16(k)
    }
    let fs: [UInt16] = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
    for (i,k) in fs.enumerated() { map[0xffbe+i] = k }
    return map
}()
func validateModifierMask(_ mask: Int) throws {
    guard mask >= 0, mask & ~(1|4|8|64) == 0 else {
        throw WireError.invalid("Unsupported modifier mask=\(mask)")
    }
}
func validatePointerMask(_ mask: Int) throws {
    try validateModifierMask(mask)
    guard mask != 0 else { throw WireError.invalid("Pointer modifier mask must not be zero") }
}
func validateBinding(_ key: KeyBinding) throws {
    try validateModifierMask(key.mask)
    guard keyCodeForSym[key.sym] != nil else {
        throw WireError.invalid("Unsupported key binding mask=\(key.mask) sym=\(key.sym)")
    }
    guard key.mask != 0 || key.sym >= 0xff00 else {
        throw WireError.invalid("Unmodified printable global shortcuts are disabled")
    }
}
