import Foundation

@main struct WireTests {
    static var count=0
    static func check(_ b: @autoclosure () -> Bool,_ name: String) {
        guard b() else { fatalError("FAIL: \(name)") }; count += 1
    }
    static func rejects(_ plan: Plan, _ name: String) {
        do { try PlanSafety.validate(plan,active:[1,2,3]); fatalError("FAIL: \(name)") }
        catch { count += 1 }
    }
    static func main() throws {
        let primary=Rect(x:0,y:0,width:1512,height:982)
        check(Rect.quartz(appKit:primary,primaryTop:982) == primary,"primary origin")
        check(Rect.quartz(appKit:Rect(x:-1920,y:0,width:1920,height:1080),primaryTop:982)
              == Rect(x:-1920,y:-98,width:1920,height:1080),"negative X and offset Y")
        check(Rect.quartz(appKit:Rect(x:0,y:982,width:2560,height:1440),primaryTop:982).y == -1440,
              "display above primary uses negative Quartz Y")
        check(Rect.quartz(appKit:Rect(x:0,y:-1080,width:1920,height:1080),primaryTop:982).y == 982,
              "display below primary")
        let usable=Rect.quartz(appKit:Rect(x:0,y:70,width:1512,height:875),primaryTop:982)
        check(usable == Rect(x:0,y:37,width:1512,height:875),"Dock and menu bar reserved in points")
        let ds=[DisplayInfo(display:1,usable:primary),
                DisplayInfo(display:2,usable:Rect(x:-1920,y:0,width:1920,height:1080))]
        check(bestDisplay(for:Rect(x:-1600,y:100,width:900,height:700),in:ds) == 2,"left screen")
        check(bestDisplay(for:Rect(x:100,y:100,width:900,height:700),in:ds) == 1,"primary screen")
        let json="""
        {"type":"plan","generation":7,"epoch":2,
         "frames":[{"wid":1,"frame":{"x":0,"y":24,"width":800,"height":900}}],
         "hide":[2],"focus":1,"workspace":"日本語","layout":"Tall",
         "checkpoint":{"savedVersion":1,"value":[null,true,2.5,"x"]}}
        """
        let message=try JSONDecoder().decode(EngineMessage.self,from:Data(json.utf8))
        guard case .plan(var plan)=message else { fatalError("decode plan") }
        try PlanSafety.validate(plan,active:[1,2,3]); count += 1
        check(plan.workspace == "日本語","UTF-8 protocol")
        var bad=plan; bad.hide=[1]; rejects(bad,"show/hide conflict")
        bad=plan; bad.frames.append(bad.frames[0]); rejects(bad,"duplicate frame")
        bad=plan; bad.hide=[2,2]; rejects(bad,"duplicate hidden ID")
        bad=plan; bad.focus=3; rejects(bad,"focus missing from frames")
        bad=plan; bad.frames[0].frame.width=0; rejects(bad,"zero dimension")
        bad=plan; bad.frames[0].frame.x=Int.max; rejects(bad,"coordinate overflow")
        bad=plan; bad.hide=[9]; rejects(bad,"unknown window ID")
        bad=plan; bad.frames[0].frame.height = -1; rejects(bad,"negative dimension")
        plan.frames[0].frame.x = -1800
        try PlanSafety.validate(plan,active:[1,2,3]); count += 1
        for key in [KeyBinding(mask:68,sym:106),KeyBinding(mask:69,sym:0xff0d),
                    KeyBinding(mask:0,sym:0xffbe),KeyBinding(mask:8,sym:0x20)] {
            try validateBinding(key); count += 1
        }
        for key in [KeyBinding(mask:0,sym:106),KeyBinding(mask:16,sym:106),
                    KeyBinding(mask:68,sym:0x1008ff11)] {
            do { try validateBinding(key); fatalError("invalid key accepted") }
            catch { count += 1 }
        }
        check(keyCodeForSym[106] == 38,"J physical key")
        check(keyCodeForSym[0xffd1] == 90,"F20 mapping")
        let config=Data(("{\"type\":\"configure\",\"protocol\":1,\"keys\":[{\"mask\":68,\"sym\":106}]"
          + ",\"mouseMask\":68,\"borderWidth\":2,\"borderColor\":\"#00ff00\""
          + ",\"focusFollowsMouse\":true}").utf8)
        if case .configure(let v,let keys,let mouseMask,let look)=try JSONDecoder().decode(EngineMessage.self,from:config) {
            check(v == 1 && keys.count == 1 && mouseMask == 68,"configure decoding")
            check(look.borderWidth == 2 && look.focusFollowsMouse,"appearance decoding")
            check(BorderOverlay.parse(look.borderColor)?.greenComponent == 1,"border colour")
            check(BorderOverlay.parse("nope") == nil,"bad border colour rejected")
        } else { fatalError("configuration") }
        try validatePointerMask(68); count += 1
        do { try validatePointerMask(128); fatalError("invalid pointer modifier accepted") }
        catch { count += 1 }
        do { try validatePointerMask(0); fatalError("unmodified pointer grab accepted") }
        catch { count += 1 }
        let value=try JSONDecoder().decode(JSONValue.self,from:Data("{\"a\":[true,false,null,1.5,\"日本語\"]}".utf8))
        _=try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(value)); count += 1
        let wi=WindowInfo(wid:42,pid:123,app:"Terminal",bundle:"com.apple.Terminal",
          titleText:"α\nβ",onDisplay:1,frame:primary,minimized:false,ownedHidden:false)
        let snap=Snapshot(generation:8,epoch:1,screens:ds,windows:[wi],focused:42,restore:nil)
        let encoded=try JSONEncoder().encode(snap)
        let object=try JSONSerialization.jsonObject(with:encoded) as! [String:Any]
        check(object["type"] as? String == "snapshot","snapshot event type")
        let window=(object["windows"] as! [[String:Any]])[0]
        check(window["titleText"] as? String == "α\nβ","title escaping")
        check(window["ownedHidden"] as? Bool == false,"ownership wire name")
        // Geometry stress: round trips hold for logical-coordinate rectangles.
        for x in stride(from:-6000,through:6000,by:1200) {
            for y in stride(from:-3000,through:3000,by:600) {
                let r=Rect(x:x,y:y,width:1920,height:1080)
                check(Rect.quartz(appKit:Rect.quartz(appKit:r,primaryTop:982),primaryTop:982) == r,
                      "coordinate involution")
            }
        }
        print("PASS: \(count) portable Swift checks")
    }
}
