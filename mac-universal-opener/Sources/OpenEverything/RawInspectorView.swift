import Foundation
import SwiftUI

struct RawInspectorView: View {
    let url: URL
    @State private var mode: Mode = .text
    @State private var contents = "Loading…"

    enum Mode: String, CaseIterable, Identifiable {
        case text = "Text"
        case hex = "Hex"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Raw view", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Spacer()
                Text("First 2 MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            ScrollView([.horizontal, .vertical]) {
                Text(contents)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
            }
        }
        .task(id: mode) { await load() }
    }

    private func load() async {
        let selectedMode = mode
        let target = url
        let output = await Task.detached(priority: .userInitiated) {
            do {
                let handle = try FileHandle(forReadingFrom: target)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 2 * 1_024 * 1_024) ?? Data()
                switch selectedMode {
                case .text:
                    return String(data: data, encoding: .utf8)
                        ?? String(data: data, encoding: .isoLatin1)
                        ?? "This file does not contain readable text. Switch to Hex."
                case .hex:
                    return Self.hexDump(data)
                }
            } catch {
                return "Could not read this file: \(error.localizedDescription)"
            }
        }.value
        contents = output
    }

    private static func hexDump(_ data: Data) -> String {
        var lines: [String] = []
        lines.reserveCapacity((data.count + 15) / 16)
        for offset in stride(from: 0, to: data.count, by: 16) {
            let end = min(offset + 16, data.count)
            let bytes = data[offset..<end]
            let hex = bytes.map { String(format: "%02X", $0) }
                .joined(separator: " ")
                .padding(toLength: 47, withPad: " ", startingAt: 0)
            let ascii = bytes.map { byte -> Character in
                (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "."
            }
            lines.append(String(format: "%08X  %@  |%@|", offset, hex, String(ascii)))
        }
        return lines.joined(separator: "\n")
    }
}