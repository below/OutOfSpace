//
//  ContentView.swift
//  OutOfSpace
//
//  Created by Alexander von Below on 14.01.26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var tps = ToyPadService()
    @StateObject private var tagRegistry = TagRegistryStore()
    @State private var autoGreenEnabled: Bool = true
    @State private var padColors: [UInt8: Color] = [:]
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(tps.connected ? "Toy Pad: Connected ✅" : "Toy Pad: Disconnected ⛔️")
                Spacer()
            }

            Toggle("Auto: Tag → Green", isOn: $autoGreenEnabled)

            Button ("Read D2") {
                Task {
                    do {
                        let bytes = try await tps.readPages(padByte: 2, startPage: 0x24)
                        print(bytes.map{ String(format:"%02X",$0)}.joined(separator:" "))
                    } catch {
                        print ("error \(error)")
                    }
                }
            }
            GroupBox("Zones") {
                VStack(alignment: .leading, spacing: 8) {
                    zoneRow(title: "Center", pad: 1)
                    zoneRow(title: "Left", pad: 2)
                    zoneRow(title: "Right", pad: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Log") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tps.log.indices, id: \.self) { idx in
                            Text(tps.log[idx])
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 220)
            }
        }
        .padding()
        .onReceive(tps.$pads) { newPads in
            guard autoGreenEnabled else { return }
            for padNumber: UInt8 in [1, 2, 3] {
                let state = newPads[padNumber] ?? (present: false, uid: nil)
                guard let p = padEnum(padNumber) else { continue }
                if state.present {
                    tps.color(pad: p, r: 0, g: 255, b: 0)
                } else {
                    tps.color(pad: p, r: 0, g: 0, b: 0)
                }
            }
        }
        .onAppear { tps.start() }
        .onDisappear {
            tps.color(pad: .all, r: 0, g: 0, b: 0)
            tps.stop()
        }
    }

    private func padEnum(_ pad: UInt8) -> ToyPadService.Pad? {
        switch pad {
        case 0: return .all
        case 1: return .center
        case 2: return .left
        case 3: return .right
        default: return nil
        }
    }

    @ViewBuilder
    private func zoneRow(title: String, pad: UInt8) -> some View {
        let state = tps.pads[pad] ?? (present: false, uid: nil)
        HStack {
            Text(title)
                .frame(width: 60, alignment: .leading)
            Text(state.present ? "present" : "empty")
                .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(tagRegistry.displayName(for: state.uid))
                    .font(.system(.body))
                Text(state.uid ?? "—")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
            Spacer()
            ColorPicker("Color", selection: Binding(
                get: { padColors[pad] ?? .green },
                set: { newColor in
                    padColors[pad] = newColor
                    if let p = padEnum(pad) {
                        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                        NSColor(newColor).usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
                        tps.color(pad: p,
                                  r: UInt8(max(0, min(255, Int(round(r * 255))))),
                                  g: UInt8(max(0, min(255, Int(round(g * 255))))),
                                  b: UInt8(max(0, min(255, Int(round(b * 255))))))
                    }
                }
            ))
            .labelsHidden()
            .frame(width: 44)
            .disabled(!tps.connected)
            Button("Off") {
                if let p = padEnum(pad) {
                    tps.color(pad: p, r: 0, g: 0, b: 0)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
