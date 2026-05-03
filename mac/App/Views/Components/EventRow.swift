import SwiftUI

struct EventRow: View {
    let line: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.caption)
                .frame(width: 14)
            Text(displayText)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }

    private var displayText: String {
        // Render the existing "[HH:MM:SS] message" format with a softer separator.
        if let bracketEnd = line.firstIndex(of: "]"),
           line.first == "[" {
            let timestamp = line[line.index(after: line.startIndex)..<bracketEnd]
            let rest = line[line.index(after: bracketEnd)...].trimmingCharacters(in: .whitespaces)
            return "\(timestamp)  ·  \(rest)"
        }
        return line
    }

    private var icon: String {
        let lower = line.lowercased()
        if lower.contains("fail") || lower.contains("error") || lower.contains("missing") {
            return "exclamationmark.circle.fill"
        }
        if lower.contains("link up") || lower.contains("started") || lower.contains("clipboard <-") || lower.contains("clipboard ->") {
            return "checkmark.circle"
        }
        if lower.contains("link lost") || lower.contains("stopped") || lower.contains("disconnected") {
            return "minus.circle"
        }
        return "circle.fill"
    }

    private var tint: Color {
        let lower = line.lowercased()
        if lower.contains("fail") || lower.contains("error") || lower.contains("missing") {
            return .red
        }
        if lower.contains("link lost") || lower.contains("stopped") {
            return .secondary
        }
        if lower.contains("link up") || lower.contains("started") {
            return .green
        }
        return .secondary
    }
}
