import AppKit
import ApplicationServices
import BarelyRealCore
import Foundation
import IOKit.hid

struct DiagnosticsBundle {
    struct Snapshot {
        var kmRunning: Bool
        var clipboardRunning: Bool
        var controlRunning: Bool
        var receiverLinkUp: Bool
        var lockOnDisconnect: Bool
        var localDisplays: [DisplayInfo]
        var remoteDisplays: [DisplayInfo]
        var remoteScreensStale: Bool
        var virtualLayout: Layout
        var logLines: [String]
        var lastError: String?
    }

    static func write(_ snapshot: Snapshot) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let downloads = try FileManager.default.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = downloads.appendingPathComponent("BarelyReal-Diagnostics-\(stamp).txt")
        try report(snapshot).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func report(_ snapshot: Snapshot) -> String {
        var lines: [String] = []
        lines.append("BarelyReal Diagnostics")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        lines.append("== App ==")
        lines.append("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        lines.append("Bundle path: \(Bundle.main.bundlePath)")
        lines.append("Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")
        lines.append("Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")")
        lines.append("Process: \(ProcessInfo.processInfo.processName) pid=\(ProcessInfo.processInfo.processIdentifier)")
        lines.append("")

        lines.append("== System ==")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Host: \(Host.current().localizedName ?? "unknown")")
        lines.append("")

        lines.append("== Permissions ==")
        lines.append("Accessibility: \(AXIsProcessTrusted() ? "granted" : "missing")")
        lines.append("Input Monitoring: \(inputMonitoringStatus())")
        lines.append("")

        lines.append("== Runtime ==")
        lines.append("KM running: \(snapshot.kmRunning)")
        lines.append("Clipboard running: \(snapshot.clipboardRunning)")
        lines.append("Control running: \(snapshot.controlRunning)")
        lines.append("Receiver link up: \(snapshot.receiverLinkUp)")
        lines.append("Lock on disconnect: \(snapshot.lockOnDisconnect)")
        lines.append("Remote screens stale: \(snapshot.remoteScreensStale)")
        if let lastError = snapshot.lastError {
            lines.append("Last error: \(lastError)")
        }
        lines.append("")

        lines.append("== Displays ==")
        lines.append("Local:")
        lines.append(contentsOf: displayLines(snapshot.localDisplays))
        lines.append("Remote:")
        lines.append(contentsOf: displayLines(snapshot.remoteDisplays))
        lines.append("")

        lines.append("== Virtual Layout ==")
        if let layout = try? JSONEncoder.prettyBarelyReal.encode(snapshot.virtualLayout),
           let json = String(data: layout, encoding: .utf8) {
            lines.append(json)
        } else {
            lines.append("layout encode failed")
        }
        lines.append("")

        lines.append("== Recent Activity ==")
        lines.append("Clipboard contents, keystrokes, and file bytes are intentionally not included.")
        lines.append(contentsOf: snapshot.logLines.map(redactLogLine))
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func displayLines(_ displays: [DisplayInfo]) -> [String] {
        if displays.isEmpty {
            return ["  none"]
        }
        return displays.map {
            "  peer=\($0.peerId) id=\($0.screenId) x=\($0.x) y=\($0.y) w=\($0.width) h=\($0.height) scale=\($0.scale) primary=\($0.isPrimary)"
        }
    }

    private static func inputMonitoringStatus() -> String {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return "granted"
        case kIOHIDAccessTypeDenied:
            return "denied"
        default:
            return "unknown"
        }
    }

    private static func redactLogLine(_ line: String) -> String {
        let lower = line.lowercased()
        if lower.contains("clipboard sent: text") {
            return replaceClipboardSuffix(in: line, with: "Clipboard sent: text/plain [redacted]")
        }
        if lower.contains("clipboard received: text") {
            return replaceClipboardSuffix(in: line, with: "Clipboard received: text/plain [redacted]")
        }
        if lower.contains("clipboard sent: files") {
            return replaceClipboardSuffix(in: line, with: "Clipboard sent: files [redacted names]")
        }
        if lower.contains("clipboard received: files") {
            return replaceClipboardSuffix(in: line, with: "Clipboard received: files [redacted names]")
        }
        return line
    }

    private static func replaceClipboardSuffix(in line: String, with replacement: String) -> String {
        guard let range = line.range(of: "Clipboard") else { return replacement }
        return String(line[..<range.lowerBound]) + replacement
    }
}

private extension JSONEncoder {
    static var prettyBarelyReal: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
