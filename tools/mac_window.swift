// Window lookup and graceful quit for tools/mac_app.py.
//
// Usage:
//   mac_window list <pid>   Print one JSON object per on-screen window owned by <pid>:
//                           {"id": CGWindowID, "layer": Int, "name": String?, "x", "y", "w", "h"}.
//   mac_window resize <w> <h>  Ask the Debug app to set its main window's content size.
//   mac_window quit         Post the Debug-only distributed notification that asks the
//                           Festival Mac app to terminate normally (no Apple Events, so no
//                           Automation permission prompt and no "reopen windows" state).
//
// Only window metadata of the given process is read; nothing here captures pixels.

import CoreGraphics
import Foundation

/// Distributed notification observed by the Debug Mac app (`MacDebugHooks`).
let quitNotification = Notification.Name("com.sfenton.festivalscoretracker.mac.debug.quit")
/// Distributed notification carrying `width`/`height` (points) for the main window.
let resizeNotification = Notification.Name("com.sfenton.festivalscoretracker.mac.debug.resize")

/// Print the given process's on-screen windows as JSON lines.
///
/// - Parameter pid: Owning process identifier.
func listWindows(pid: Int32) {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return
    }
    for window in info {
        guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
              let id = window[kCGWindowNumber as String] as? Int,
              let bounds = window[kCGWindowBounds as String] as? [String: Double]
        else { continue }
        var entry: [String: Any] = [
            "id": id,
            "layer": window[kCGWindowLayer as String] as? Int ?? 0,
            "x": bounds["X"] ?? 0, "y": bounds["Y"] ?? 0,
            "w": bounds["Width"] ?? 0, "h": bounds["Height"] ?? 0,
        ]
        if let name = window[kCGWindowName as String] as? String { entry["name"] = name }
        if let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) {
            print(line)
        }
    }
}

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "" {
case "list" where arguments.count == 3:
    guard let pid = Int32(arguments[2]) else { exit(2) }
    listWindows(pid: pid)
case "resize" where arguments.count == 4:
    guard let width = Double(arguments[2]), let height = Double(arguments[3]) else { exit(2) }
    DistributedNotificationCenter.default().postNotificationName(
        resizeNotification, object: nil,
        userInfo: ["width": width, "height": height], deliverImmediately: true
    )
case "quit":
    DistributedNotificationCenter.default().postNotificationName(
        quitNotification, object: nil, userInfo: nil, deliverImmediately: true
    )
default:
    FileHandle.standardError.write(Data("usage: mac_window list <pid> | resize <w> <h> | quit\n".utf8))
    exit(2)
}
