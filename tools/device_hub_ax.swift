// Device Hub accessibility helper for `tools/ios_sim.py` (iPhone Duo poses).
//
// System Events cannot script Device Hub on macOS 27: it reports every DeviceHub
// process with unix id 0 and no windows or menu bar, so JXA/AppleScript UI
// scripting sees nothing. The Accessibility API addressed by pid works, so
// `ios_sim.py` compiles this file once (cached by source hash) and calls it.
//
// It needs the macOS Accessibility permission of the *responsible* app (the app
// that launched the terminal or agent); it never changes privacy settings.
//
// Usage (every command prints one JSON object on stdout):
//   device_hub_ax trusted
//   device_hub_ax frontmost
//   device_hub_ax windows <pid>...
//   device_hub_ax dump <pid> <window> [--menus]
//   device_hub_ax press <pid> <window> <child-index>...
//   device_hub_ax select-row <pid> <window> <identifier>
//   device_hub_ax menu <pid> <title>...
//   device_hub_ax raise <pid> <window>

import ApplicationServices
import Foundation

// MARK: - Accessibility reads

/// Read one accessibility attribute.
///
/// - Parameters:
///   - element: The element to read.
///   - name: Attribute name, e.g. `AXTitle`.
/// - Returns: The raw value, or nil when absent or unreadable.
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

/// Read an attribute as a string (numbers and booleans are described).
///
/// - Parameters:
///   - element: The element to read.
///   - name: Attribute name.
/// - Returns: The string value, or nil.
func text(_ element: AXUIElement, _ name: String) -> String? {
    guard let value = attribute(element, name) else { return nil }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
}

/// Read an element's children.
///
/// - Parameter element: The parent element.
/// - Returns: Its `AXChildren`, or an empty array.
func children(_ element: AXUIElement) -> [AXUIElement] {
    (attribute(element, "AXChildren") as? [AXUIElement]) ?? []
}

/// List an element's action names.
///
/// - Parameter element: The element.
/// - Returns: Action names such as `AXPress`.
func actions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return (names as? [String]) ?? []
}

/// An application's windows.
///
/// - Parameter pid: Process id.
/// - Returns: Its `AXWindows`.
func windows(of pid: pid_t) -> [AXUIElement] {
    (attribute(AXUIElementCreateApplication(pid), "AXWindows") as? [AXUIElement]) ?? []
}

// MARK: - Output

/// Print a JSON object and exit.
///
/// - Parameters:
///   - object: A JSON-serializable dictionary.
///   - code: Process exit code.
func emit(_ object: [String: Any], code: Int32 = 0) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(code)
}

/// Print an error object and exit 1.
///
/// - Parameter message: What went wrong.
func fail(_ message: String) -> Never {
    emit(["error": message], code: 1)
}

/// Describe one element for `dump`.
///
/// - Parameters:
///   - element: The element.
///   - kind: `control` (window) or `menu` (menu bar).
///   - path: Index path from the window (or `-1` for the menu bar).
/// - Returns: A JSON-ready dictionary.
func describe(_ element: AXUIElement, kind: String, path: [Int]) -> [String: Any] {
    var entry: [String: Any] = ["kind": kind, "path": path, "actions": actions(element)]
    for (key, name) in [("role", "AXRole"), ("subrole", "AXSubrole"), ("title", "AXTitle"),
                        ("description", "AXDescription"), ("help", "AXHelp"),
                        ("identifier", "AXIdentifier"), ("value", "AXValue")] {
        if let value = text(element, name) { entry[key] = value }
    }
    if let enabled = attribute(element, "AXEnabled") as? Bool { entry["enabled"] = enabled }
    return entry
}

/// Walk an element tree depth-first, bounded.
///
/// - Parameters:
///   - element: Root.
///   - kind: Entry kind.
///   - path: Root's index path.
///   - depth: Current depth.
///   - out: Accumulated entries.
func walk(_ element: AXUIElement, kind: String, path: [Int], depth: Int, into out: inout [[String: Any]]) {
    guard depth <= 18, out.count < 4000 else { return }
    for (index, child) in children(element).enumerated() {
        let childPath = path + [index]
        out.append(describe(child, kind: kind, path: childPath))
        walk(child, kind: kind, path: childPath, depth: depth + 1, into: &out)
    }
}

// MARK: - Element lookup

/// Resolve a window and child-index path.
///
/// - Parameters:
///   - pid: Process id.
///   - window: Window index in `AXWindows`.
///   - path: Child indices below the window.
/// - Returns: The element.
func element(pid: pid_t, window: Int, path: [Int]) -> AXUIElement {
    let list = windows(of: pid)
    guard list.indices.contains(window) else { fail("pid \(pid) has no window \(window)") }
    var current = list[window]
    for index in path {
        let kids = children(current)
        guard kids.indices.contains(index) else { fail("path \(path) left the tree at \(index)") }
        current = kids[index]
    }
    return current
}

/// Find the first descendant with an accessibility identifier.
///
/// - Parameters:
///   - root: Search root.
///   - identifier: Exact `AXIdentifier`.
///   - depth: Current depth.
/// - Returns: The element and its ancestors (outermost first), or nil.
func find(_ root: AXUIElement, identifier: String, depth: Int = 0) -> [AXUIElement]? {
    guard depth <= 18 else { return nil }
    for child in children(root) {
        if text(child, "AXIdentifier") == identifier { return [child] }
        if let found = find(child, identifier: identifier, depth: depth + 1) { return [child] + found }
    }
    return nil
}

// MARK: - Commands

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail("missing command") }
if command == "trusted" { emit(["trusted": AXIsProcessTrusted()]) }
guard AXIsProcessTrusted() else { emit(["error": "not-trusted"], code: 4) }

/// Parse an integer argument or fail.
///
/// - Parameter index: Position in `arguments`.
/// - Returns: The integer.
func integer(_ index: Int) -> Int {
    guard arguments.indices.contains(index), let value = Int(arguments[index]) else {
        fail("argument \(index) must be an integer")
    }
    return value
}

switch command {
case "frontmost":
    // NSWorkspace reports DeviceHub's pid as -1 on macOS 27; the system-wide element does not.
    var pid: pid_t = 0
    guard let app = attribute(AXUIElementCreateSystemWide(), "AXFocusedApplication"),
          AXUIElementGetPid(app as! AXUIElement, &pid) == .success else { fail("no focused application") }
    emit(["pid": Int(pid)])
case "windows":
    var list: [[String: Any]] = []
    for raw in arguments.dropFirst() {
        guard let pid = pid_t(raw) else { continue }
        for (index, window) in windows(of: pid).enumerated() {
            var entry: [String: Any] = ["pid": Int(pid), "window": index]
            entry["title"] = text(window, "AXTitle") ?? ""
            entry["subrole"] = text(window, "AXSubrole") ?? ""
            entry["minimized"] = (attribute(window, "AXMinimized") as? Bool) ?? false
            entry["main"] = (attribute(window, "AXMain") as? Bool) ?? false
            list.append(entry)
        }
    }
    emit(["windows": list])
case "dump":
    let pid = pid_t(integer(1)), window = integer(2)
    var out: [[String: Any]] = []
    let root = element(pid: pid, window: window, path: [])
    walk(root, kind: "control", path: [], depth: 0, into: &out)
    if arguments.contains("--menus"), let bar = attribute(AXUIElementCreateApplication(pid), "AXMenuBar") {
        walk(bar as! AXUIElement, kind: "menu", path: [-1], depth: 0, into: &out)
    }
    emit(["controls": out])
case "press":
    let pid = pid_t(integer(1)), window = integer(2)
    let path = (3..<arguments.count).map(integer)
    let target = element(pid: pid, window: window, path: path)
    let result = AXUIElementPerformAction(target, "AXPress" as CFString)
    guard result == .success else { fail("AXPress failed (\(result.rawValue))") }
    emit(["pressed": path])
case "select-row":
    let pid = pid_t(integer(1)), window = integer(2)
    guard arguments.count > 3 else { fail("missing identifier") }
    guard let chain = find(element(pid: pid, window: window, path: []), identifier: arguments[3]) else {
        fail("no element with identifier \(arguments[3])")
    }
    guard let row = chain.last(where: { text($0, "AXRole") == "AXRow" }) else { fail("identifier is not in a row") }
    let result = AXUIElementSetAttributeValue(row, "AXSelected" as CFString, kCFBooleanTrue)
    guard result == .success else { fail("selecting the row failed (\(result.rawValue))") }
    emit(["selected": arguments[3]])
case "menu":
    let pid = pid_t(integer(1))
    let titles = Array(arguments.dropFirst(2))
    guard !titles.isEmpty, let bar = attribute(AXUIElementCreateApplication(pid), "AXMenuBar") else {
        fail("no menu bar or titles")
    }
    var current = bar as! AXUIElement
    for (offset, title) in titles.enumerated() {
        // Menu bar items and menu items hold their items inside one AXMenu child.
        let candidates = children(current).flatMap { child -> [AXUIElement] in
            text(child, "AXRole") == "AXMenu" ? children(child) : [child]
        }
        guard let match = candidates.first(where: { text($0, "AXTitle") == title }) else {
            fail("no menu item \"\(title)\" (after \(titles.prefix(offset).joined(separator: " > ")))")
        }
        current = match
    }
    if let enabled = attribute(current, "AXEnabled") as? Bool, !enabled { fail("menu item is disabled") }
    let result = AXUIElementPerformAction(current, "AXPress" as CFString)
    guard result == .success else { fail("AXPress failed (\(result.rawValue))") }
    emit(["pressed": titles])
case "raise":
    // Un-minimize and make the window main, so menu commands act on its device.
    let pid = pid_t(integer(1)), window = integer(2)
    let target = element(pid: pid, window: window, path: [])
    AXUIElementSetAttributeValue(target, "AXMinimized" as CFString, kCFBooleanFalse)
    AXUIElementSetAttributeValue(target, "AXMain" as CFString, kCFBooleanTrue)
    AXUIElementPerformAction(target, "AXRaise" as CFString)
    emit(["raised": window])
default:
    fail("unknown command \(command)")
}
