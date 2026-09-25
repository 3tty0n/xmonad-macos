import Foundation
import AppKit

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
        // WindowServer handed these back after a display wake; Int(_:) traps on
        // them, so a bad rectangle must be refused rather than converted.
        check(Rect(CGRect(x:-1920,y:-98,width:1920,height:1080)) == Rect(x:-1920,y:-98,width:1920,height:1080),
              "on-screen CG rectangle")
        check(Rect(CGRect(x:Double.nan,y:0,width:100,height:50)) == nil,"NaN origin refused")
        check(Rect(CGRect(x:0,y:0,width:Double.infinity,height:50)) == nil,"infinite size refused")
        check(Rect(CGRect(x:1e30,y:0,width:100,height:50)) == nil,"origin past Int refused")
        check(Rect(CGRect(x:0,y:0,width:0,height:50)) == nil,"empty rectangle refused")
        let ds=[DisplayInfo(display:1,usable:primary),
                DisplayInfo(display:2,usable:Rect(x:-1920,y:0,width:1920,height:1080))]
        check(bestDisplay(for:Rect(x:-1600,y:100,width:900,height:700),in:ds) == 2,"left screen")
        check(bestDisplay(for:Rect(x:100,y:100,width:900,height:700),in:ds) == 1,"primary screen")
        let json="""
        {"type":"plan","generation":7,"epoch":2,
         "frames":[{"wid":1,"frame":{"x":0,"y":24,"width":800,"height":900}}],
         "hide":[2],"focus":1,"action":7,"focusForMs":400,"workspace":"日本語","layout":"Tall",
         "checkpoint":{"savedVersion":1,"value":[null,true,2.5,"x"]}}
        """
        let message=try JSONDecoder().decode(EngineMessage.self,from:Data(json.utf8))
        guard case .plan(var plan)=message else { fatalError("decode plan") }
        try PlanSafety.validate(plan,active:[1,2,3]); count += 1
        check(plan.workspace == "日本語","UTF-8 protocol")
        check(plan.action == 7 && plan.focusForMs == 400,"action sequencing fields")
        check(plan.borders == nil,"a plan without borders still decodes")
        check(plan.status == nil,"a plan without a PP status still decodes")
        let bjson="""
        {"type":"plan","generation":1,"epoch":1,
         "frames":[{"wid":1,"frame":{"x":0,"y":24,"width":800,"height":900}},
                   {"wid":3,"frame":{"x":0,"y":924,"width":800,"height":900}}],
         "hide":[],"focus":1,"workspace":"1","layout":"Tall","checkpoint":null,
         "borders":[{"wid":1,"width":0},{"wid":3,"width":4}]}
        """
        let bdata=Data(bjson.utf8)
        let msg=try JSONDecoder().decode(EngineMessage.self,from:bdata)
        guard case .plan(let named)=msg else { fatalError("decode borders") }
        check(named.borders?.count == 2,"per-window border widths decode")
        check(named.borders?.first?.wid == 1
              && named.borders?.first?.width == 0,"zero means no border at all")
        check(named.borders?.last?.width == 4,"the plan may narrow a border")
        try PlanSafety.validate(named,active:[1,3]); count += 1
        let ejson="""
        {"type":"plan","generation":1,"epoch":1,"frames":[],"hide":[],
         "workspace":"1","layout":"Tall","checkpoint":null,"borders":[],
         "status":"[1] : Tall"}
        """
        let edata=Data(ejson.utf8)
        let emsg=try JSONDecoder().decode(EngineMessage.self,from:edata)
        guard case .plan(let none)=emsg else { fatalError("empty borders") }
        check(none.borders?.isEmpty == true,"an empty border list is not nil")
        check(none.status == "[1] : Tall","a logHook's PP status decodes")
        var bad=plan; bad.hide=[1]; rejects(bad,"show/hide conflict")
        bad=plan; bad.frames.append(bad.frames[0]); rejects(bad,"duplicate frame")
        bad=plan; bad.hide=[2,2]; rejects(bad,"duplicate hidden ID")
        bad=plan; bad.focus=3; rejects(bad,"focus missing from frames")
        bad=plan; bad.frames[0].frame.width=0; rejects(bad,"zero dimension")
        bad=plan; bad.frames[0].frame.x=Int.max; rejects(bad,"coordinate overflow")
        bad=plan; bad.hide=[9]; rejects(bad,"unknown window ID")
        bad=plan; bad.borders=[BorderOverride(wid:9,width:1)]
        try PlanSafety.validate(bad,active:[1,2,3]); count += 1
        bad=plan; bad.borders=Array(repeating:BorderOverride(wid:1,width:0),count:10_001)
        rejects(bad,"unreasonable border list")
        bad=plan; bad.borders=[BorderOverride(wid:1,width:-1)]
        rejects(bad,"negative border width")
        bad=plan; bad.borders=[BorderOverride(wid:1,width:65)]
        rejects(bad,"border width above the cap")
        bad=plan; bad.borders=[BorderOverride(wid:1,width:0)]
        try PlanSafety.validate(bad,active:[1,2,3]); count += 1
        // Moving the last window off a smartBorders workspace empties it while
        // the layout still states that window's width, so the engine sends an
        // empty frame list with a border for a hidden window. That must plan.
        let emptied="""
        {"type":"plan","generation":9,"epoch":0,
         "frames":[],"hide":[1,2,3],"focus":null,"action":null,"focusForMs":400,
         "workspace":"2","layout":"ThreeColMid","screen":1,"checkpoint":null,
         "borders":[{"wid":1,"width":1}],"workspaces":[]}
        """
        let emptiedMessage=try JSONDecoder().decode(EngineMessage.self,from:Data(emptied.utf8))
        guard case .plan(let emptiedPlan)=emptiedMessage else { fatalError("decode emptied workspace") }
        try PlanSafety.validate(emptiedPlan,active:[1,2,3]); count += 1
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
        check(symForKeyCode[38] == 106 && symForKeyCode[53] == 0xff1b,"grabbed keys map back to keysyms")
        check(keyCodeForSym.allSatisfy { symForKeyCode[$0.value] == $0.key },"key codes are unique")
        let config=Data(("{\"type\":\"configure\",\"protocol\":1,\"keys\":[{\"mask\":68,\"sym\":106}]"
          + ",\"mouseMask\":68,\"mouse\":[{\"mask\":68,\"button\":1,\"action\":\"move\"}"
          + ",{\"mask\":68,\"button\":3,\"action\":\"resize\"},{\"mask\":68,\"button\":2,\"action\":\"raise\"}]"
          + ",\"borderWidth\":2,\"borderColor\":\"#00ff00\",\"normalBorderColor\":\"#dddddd\""
          + ",\"focusFollowsMouse\":true}").utf8)
        if case .configure(let v,let keys,let mouse,let look)=try JSONDecoder().decode(EngineMessage.self,from:config) {
            check(v == 1 && keys.count == 1 && mouse.count == 3,"configure decoding")
            check(look.borderWidth == 2 && look.focusFollowsMouse && look.normalBorderColor == "#dddddd","appearance decoding")
            check(mouse[0].action == .move && mouse[1].button == 3 && mouse[2].action == .raise,"mouse bindings")
            check(BorderOverlay.parse(look.borderColor)?.greenComponent == 1,"border colour")
            check(BorderOverlay.parse("nope") == nil,"bad border colour rejected")
        } else { fatalError("configuration") }
        let tiled=NSRect(x:0,y:0,width:800,height:900)
        let floated=NSRect(x:200,y:200,width:400,height:300)
        if let hole=BorderOverlay.hole(in:tiled,cutting:floated) {
            check(hole.origin.x == 199 && hole.origin.y == 199
                  && hole.width == 402 && hole.height == 302,"focused float punches a hole")
        } else { check(false,"focused float must clip the tiled frame") }
        let edge=NSRect(x:790,y:0,width:200,height:50)
        if let hole=BorderOverlay.hole(in:tiled,cutting:edge) {
            check(hole.origin.x == 789 && hole.width == 11,"clip is the overlap only")
        } else { check(false,"overlapping edge must clip") }
        check(BorderOverlay.hole(in:tiled,cutting:NSRect(x:900,y:0,width:10,height:10)) == nil,
              "disjoint frames keep the unfocused border")
        try validateMouseBindings([MouseBind(mask:68,button:1,action:.move)]); count += 1
        do { try validateMouseBindings([]); fatalError("empty mouse bindings accepted") }
        catch { count += 1 }
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
        check(window["subrole"] as? String == "AXStandardWindow","default subrole")
        check(isManagedPopupSubrole("AXDialog") && isManagedPopupSubrole("AXSystemDialog")
              && isManagedPopupSubrole("AXFloatingWindow") && isManagedPopupSubrole("AXSystemFloatingWindow"),
              "popup subroles")
        check(!isManagedPopupSubrole("AXStandardWindow") && !isManagedPopupSubrole("AXSheet")
              && !isManagedPopupSubrole("AXUnknown"),"sheets stay unmanaged")
        check(reportsAsWindowRole("AXWindow") && reportsAsWindowRole("AXTextField")
              && reportsAsWindowRole("AXTextArea"),"Emacs frames report as windows")
        check(!reportsAsWindowRole("AXSheet") && !reportsAsWindowRole("AXUnknown"),
              "sheets are not window roles")
        check(windowRoleIsEligible(role:"AXWindow",subrole:"AXStandardWindow",fullScreen:false,
                                   positionSettable:true,sizeSettable:true),
              "standard window tiles without AXMinimized")
        check(windowRoleIsEligible(role:"AXWindow",subrole:"",fullScreen:false,
                                   positionSettable:true,sizeSettable:true),
              "empty subrole is a standard window")
        check(windowRoleIsEligible(role:"AXTextField",subrole:"AXStandardWindow",fullScreen:false,
                                   positionSettable:true,sizeSettable:true),
              "NS Emacs AXTextField frames are eligible")
        check(!windowRoleIsEligible(role:"AXWindow",subrole:"AXSheet",fullScreen:false,
                                    positionSettable:true,sizeSettable:true),
              "sheets stay ineligible")
        check(!windowRoleIsEligible(role:"AXWindow",subrole:"AXUnknown",fullScreen:false,
                                    positionSettable:true,sizeSettable:true),
              "unknown subroles stay ineligible")
        let axFrame=Rect(x:0,y:24,width:800,height:600)
        let cgFrame=Rect(x:0,y:0,width:800,height:624)
        check(cgMatchesAXFrame(axFrame,cgFrame),"titlebar offset still matches CG")
        check(!cgMatchesAXFrame(axFrame,Rect(x:900,y:0,width:800,height:624)),
              "a neighbour CG window is not this frame")
        check(cgWindowIsApplicationLayer(0) && cgWindowIsApplicationLayer(3)
              && cgWindowIsApplicationLayer(8) && cgWindowIsApplicationLayer(19),"application layers")
        check(!cgWindowIsApplicationLayer(-1) && !cgWindowIsApplicationLayer(20)
              && !cgWindowIsApplicationLayer(24),"dock and menu layers excluded")
        check(bundleOmitsOnScreenCGWindows("com.google.Chrome")
              && bundleOmitsOnScreenCGWindows("com.google.Chrome.beta")
              && bundleOmitsOnScreenCGWindows("com.google.Chrome.canary"),
              "Chrome withholds on-screen CGWindow metadata")
        check(!bundleOmitsOnScreenCGWindows("com.apple.Safari")
              && !bundleOmitsOnScreenCGWindows("com.mitchellh.ghostty"),
              "AppKit apps still require CGWindow correlation")
        let screen=[DisplayInfo(display:1,usable:Rect(x:0,y:0,width:1800,height:1169))]
        let parked=Rect(x:1864,y:1233,width:782,height:1120)
        let finder=Rect(x:1013,y:44,width:782,height:1120)
        check(parkedOffDisplay(parked,screen) && !parkedOffDisplay(finder,screen),"corner clamp is parked")
        check(cgShowsOriginal(pid:1,original:finder,windows:[(1,finder)],displays:screen),
              "CG still at the original on-display frame")
        check(!cgShowsOriginal(pid:1,original:finder,windows:[(1,parked)],displays:screen),
              "CG at the parking clamp is not the original")
        check(parksByMinimizing("com.apple.finder"),"Finder hides by minimizing")
        check(!parksByMinimizing("com.apple.Safari") && !parksByMinimizing("com.google.Chrome"),
              "other apps still park first")
        check(tracesFocusBorder(wi,displays:screen),"visible window is traced")
        var restoring=wi; restoring.ownedHidden=true
        check(!tracesFocusBorder(restoring,displays:screen),"owned hide is not traced as focus")
        check(tracesFocusBorder(restoring,displays:screen,pinned:true),"pinned restore still traces an on-screen window")
        restoring.frame=parked
        check(!tracesFocusBorder(restoring,displays:screen,pinned:true),"parked window is not traced")
        var mini=wi; mini.minimized=true
        check(!tracesFocusBorder(mini,displays:screen),"minimized window is not traced")
        // Finder has no NSRunningApplication launch date, and a hide without a
        // process instance is refused. Every live process has a start time.
        let started=processStartTime(getpid())
        check(started>0 && started<=Date().timeIntervalSince1970,"process start time is readable")
        check(processStartTime(getpid())==started,"process start time is stable")
        check(processStartTime(-1)==0,"no start time for a process that cannot exist")
        check(resizeFloor(nil)==(80,60) && resizeFloor((24,24))==(24,24),"resize floor")
        let oldp=WindowPrint(wid:1,pid:9,launch:1,bundle:"b",identifier:"id",title:"t",frame:primary)
        let newp=WindowPrint(wid:99,pid:9,launch:1,bundle:"b",identifier:"id",title:"t",frame:primary)
        check(matchWindowPrints(old:[oldp],new:[newp])[1]==99,"fingerprint remaps a unique identifier")
        let titled=WindowPrint(wid:2,pid:8,launch:1,bundle:"b",identifier:"",title:"same",frame:primary)
        let titledNew=WindowPrint(wid:50,pid:8,launch:1,bundle:"b",identifier:"",title:"same",frame:primary)
        check(matchWindowPrints(old:[titled],new:[titledNew])[2]==50,"fingerprint remaps unique title and frame")
        var ck=JSONValue.object(["savedVersion":.number(1),"savedEpoch":.number(7),
          "savedWindows":.array([.number(1)]),"savedFocus":.number(1),
          "savedFloats":.array([.array([.number(1),.number(0),.number(0),.number(0.5),.number(0.5)])])])
        ck=remapCheckpoint(ck,map:[1:99],epoch:3)
        if case .object(let o)=ck, case .number(let ep)=o["savedEpoch"],
           case .array(let wins)=o["savedWindows"], case .number(let w)=wins.first {
            check(ep==3 && w==99,"checkpoint wids and epoch rewrite")
        } else { check(false,"checkpoint rewrite shape") }
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
