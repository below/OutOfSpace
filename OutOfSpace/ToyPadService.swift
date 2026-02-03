import Foundation
import Combine
import DimensionPad

@MainActor
final class ToyPadService: ObservableObject {
    @Published private(set) var connected: Bool = false
    @Published private(set) var pads = PadSlots(
        center: PadState(present: false, uid: nil, characterID: nil, name: nil, world: nil),
        left: [],
        right: []
    )
    @Published private(set) var log: [String] = []

    private let pad = DimensionPad()
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    init() {
        pad.$connected
            .removeDuplicates()
            .sink { [weak self] isConnected in
                guard let self else { return }
                self.connected = isConnected
                self.appendLog(isConnected ? "ToyPad connected" : "ToyPad disconnected")
            }
            .store(in: &cancellables)

        pad.$pads
            .sink { [weak self] newPads in
                guard let self else { return }
                self.pads = newPads
            }
            .store(in: &cancellables)

        pad.events
            .sink { [weak self] event in
                guard let self else { return }
                let action = event.action == .add ? "add" : "remove"
                self.appendLog("\(action): pad \(event.pad) uid=\(event.signature)")
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !started else { return }
        started = true
        pad.connect()
    }

    func stop() {
        started = false
    }

    func color(pad targetPad: Pad, r: UInt8, g: UInt8, b: UInt8) {
        Task { @MainActor in
            do {
                try pad.setColor(pad: targetPad, r: r, g: g, b: b)
            } catch {
                appendLog("color error: \(error)")
            }
        }
    }

    @MainActor
    func stopAllLights() {
        do {
            try pad.setColor(pad: .all, r: 0, g: 0, b: 0)
        } catch {
            appendLog("stop lights error: \(error)")
        }
    }


    func flash(pad targetPad: Pad, tickOn: UInt8 = 8, tickOff: UInt8 = 8, tickCount: UInt8 = 8, r: UInt8 = 255, g: UInt8 = 255, b: UInt8 = 0) {
        Task { @MainActor in
            do {
                try await pad.flash(pad: targetPad, tickOn: tickOn, tickOff: tickOff, tickCount: tickCount, r: r, g: g, b: b)
            } catch {
                appendLog("flash error: \(error)")
            }
        }
    }
    
    func fade(pad targetPad: Pad, tickTime: UInt8 = 16, tickCount: UInt8 = 6, r: UInt8 = 0, g: UInt8 = 120, b: UInt8 = 255) {
        Task { @MainActor in
            do {
                try pad.fade(pad: targetPad, tickTime: tickTime, tickCount: tickCount, r: r, g: g, b: b)
            } catch {
                appendLog("fade error: \(error)")
            }
        }
    }
    
    private func appendLog(_ message: String) {
        log.append(message)
        if log.count > 300 {
            log.removeFirst(log.count - 300)
        }
    }
}
