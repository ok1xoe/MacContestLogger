import CoreGraphics
import Foundation
// wins [pid]  — on-screen windows (id, pid, layer, x y w h, title), front to back
let pidFilter: Int? = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) : nil
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list {
    let pid = w[kCGWindowOwnerPID as String] as! Int
    if let f = pidFilter, f != pid { continue }
    let id = w[kCGWindowNumber as String] as! Int
    let layer = w[kCGWindowLayer as String] as! Int
    let b = w[kCGWindowBounds as String] as! [String: Any]
    let name = w[kCGWindowName as String] as? String ?? ""
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    print("\(id)\t\(pid)\t\(layer)\t\(b["X"]!) \(b["Y"]!) \(b["Width"]!) \(b["Height"]!)\t\(owner)\t\(name)")
}
