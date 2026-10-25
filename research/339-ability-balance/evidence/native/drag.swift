import AppKit
import CoreGraphics
import ApplicationServices
let args = CommandLine.arguments
if args.count == 1 {
 print("post_event_access=\(CGPreflightPostEventAccess()) accessibility=\(AXIsProcessTrusted())")
 exit(0)
}
func fail(_ reason: String) -> Never { fputs(reason + "\n", stderr); exit(1) }
guard [6,7].contains(args.count), let pid = Int32(args[1]), let sx = Double(args[2]), let sy = Double(args[3]), let ex = Double(args[4]), let ey = Double(args[5]) else { fail("usage: drag PID SX SY EX EY (window relative points)") }
guard CGPreflightPostEventAccess() else { fail("post event permission unavailable") }
guard let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == "org.godotengine.godot" else { fail("owned Godot missing") }
app.activate(options: [.activateIgnoringOtherApps])
Thread.sleep(forTimeInterval:0.2)
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { fail("owned Godot must be frontmost") }
let wins = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let matches = wins.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowName as String] as? String) == "BGLike (DEBUG)" }
guard matches.count == 1, let bounds = matches[0][kCGWindowBounds as String] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: bounds) else { fail("expected one visible Godot window") }
guard [sx,ex].allSatisfy({ $0 >= 0 && $0 < rect.width }), [sy,ey].allSatisfy({ $0 >= 0 && $0 < rect.height }) else { fail("coordinates outside window") }
let source = CGEventSource(stateID: .hidSystemState)!
var previous = CGPoint(x:sx,y:sy)
func send(_ type: CGEventType, _ x: Double, _ y: Double) {
 let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: CGPoint(x:rect.minX+x,y:rect.minY+y), mouseButton:.left)!
 event.setIntegerValueField(.mouseEventClickState,value:1)
 event.setIntegerValueField(.mouseEventDeltaX,value:Int64((x-previous.x).rounded()))
 event.setIntegerValueField(.mouseEventDeltaY,value:Int64((y-previous.y).rounded()))
 previous=CGPoint(x:x,y:y)
 guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { fail("focus changed; input stopped") }
 event.post(tap: .cghidEventTap)
}
print("pid=\(pid) bounds=\(rect) start=(\(sx),\(sy)) end=(\(ex),\(ey))")
send(.mouseMoved,sx,sy)
Thread.sleep(forTimeInterval:0.1)
send(.leftMouseDown,sx,sy)
Thread.sleep(forTimeInterval:0.15)
for step in 1...30 {
 let t = Double(step)/30
 send(.leftMouseDragged,sx+(ex-sx)*t,sy+(ey-sy)*t)
 Thread.sleep(forTimeInterval:0.02)
}
if args.count == 7 {
 guard args[6] == "cancel" else { fail("unknown option") }
 for pressed in [true,false] {
  let key = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: pressed)!
  key.post(tap:.cghidEventTap)
  Thread.sleep(forTimeInterval:0.1)
 }
}
send(.leftMouseUp,ex,ey)
print("posted down, 30 held-motion events, up")
