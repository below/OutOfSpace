//
//  ContentView.swift
//  OutOfSpace
//
//  Created by Alexander von Below on 14.01.26.
//

import SwiftUI
import DimensionPad

struct ContentView: View {
    @StateObject private var tps = ToyPadService()
    @State private var autoGreenEnabled: Bool = true
    @State private var padColors: [UInt8: Color] = [:]
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(tps.connected ? "Toy Pad: Connected ✅" : "Toy Pad: Disconnected ⛔️")
                Spacer()
            }

            Toggle("Auto: Tag → Green", isOn: $autoGreenEnabled)

            GroupBox("Zones") {
                VStack(alignment: .leading, spacing: 8) {
                    zoneRow(title: "Center", pad: .center)
                    zoneRow(title: "Left", pad: .left)
                    zoneRow(title: "Right", pad: .right)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox("Flash") {
                HStack {
                    Button("Pulse Center") {
                        tps.flash(pad: .center, r: 255, g: 120, b: 0)
                    }
                    .disabled(!tps.connected)
                    Button("Pulse All") {
                        tps.flashAllDemo()
                    }
                    .disabled(!tps.connected)
                    Spacer()
                }
            }
            
            GroupBox("Fade") {
                HStack {
                    Button("Fade Center") {
                        tps.fade(pad: .center)
                    }
                    .disabled(!tps.connected)
                    Button("Fade All") {
                        tps.fadeAllDemo()
                    }
                    .disabled(!tps.connected)
                    Spacer()
                }
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
                let state = newPads[padNumber] ?? PadState(present: false, uid: nil, characterID: nil, name: nil)
                guard let p = Pad(rawValue: padNumber) else { continue }
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

    @ViewBuilder
    private func zoneRow(title: String, pad: Pad) -> some View {
        let state = tps.pads[pad.rawValue] ?? PadState(present: false, uid: nil, characterID: nil, name: nil)
        let displayName = state.name ?? "Unknown"
        HStack {
            Text(title)
                .frame(width: 60, alignment: .leading)
            Text(state.present ? "present" : "empty")
                .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(.body))
                Text(state.characterID.map { String($0) } ?? state.uid ?? "-")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
            Spacer()
            ColorPicker("Color", selection: Binding(
                get: { padColors[pad.rawValue] ?? .green },
                set: { newColor in
                    padColors[pad.rawValue] = newColor
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    NSColor(newColor).usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
                    tps.color(pad: pad,
                              r: UInt8(max(0, min(255, Int(round(r * 255))))),
                              g: UInt8(max(0, min(255, Int(round(g * 255))))),
                              b: UInt8(max(0, min(255, Int(round(b * 255))))))
                }
            ))
            .labelsHidden()
            .frame(width: 44)
            .disabled(!tps.connected)
            Button("Off") {
                tps.color(pad: pad, r: 0, g: 0, b: 0)
            }
        }
    }
}

#Preview {
    ContentView()
}
