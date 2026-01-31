import Foundation
import Combine
import DimensionPad

@MainActor
final class ToyPadService: ObservableObject {
    @Published private(set) var connected: Bool = false
    @Published private(set) var pads: [UInt8: PadState] = [
        1: PadState(present: false, uid: nil, characterID: nil, name: nil),
        2: PadState(present: false, uid: nil, characterID: nil, name: nil),
        3: PadState(present: false, uid: nil, characterID: nil, name: nil)
    ]
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
                try await pad.setColor(pad: targetPad, r: r, g: g, b: b)
            } catch {
                appendLog("color error: \(error)")
            }
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
    
    func flashAllDemo() {
        Task { @MainActor in
            do {
                let center = FlashPad(tickOn: 8, tickOff: 8, tickCount: 12, r: 255, g: 255, b: 0)
                let left = FlashPad(tickOn: 4, tickOff: 4, tickCount: 0xFF, r: 0, g: 255, b: 255)
                let right = FlashPad(tickOn: 12, tickOff: 12, tickCount: 6, r: 255, g: 0, b: 255)
                try await pad.flashAll(center: center, left: left, right: right)
            } catch {
                appendLog("flashAll error: \(error)")
            }
        }
    }
    
    func fade(pad targetPad: Pad, tickTime: UInt8 = 16, tickCount: UInt8 = 6, r: UInt8 = 0, g: UInt8 = 120, b: UInt8 = 255) {
        Task { @MainActor in
            do {
                try await pad.fade(pad: targetPad, tickTime: tickTime, tickCount: tickCount, r: r, g: g, b: b)
            } catch {
                appendLog("fade error: \(error)")
            }
        }
    }
    
    func fadeAllDemo() {
        Task { @MainActor in
            do {
                let center = FadePad(tickTime: 24, tickCount: 3, r: 255, g: 0, b: 0)
                let left = FadePad(tickTime: 12, tickCount: 0xFF, r: 0, g: 255, b: 0)
                let right = FadePad(tickTime: 18, tickCount: 7, r: 255, g: 255, b: 255)
                try await pad.fadeAll(center: center, left: left, right: right)
            } catch {
                appendLog("fadeAll error: \(error)")
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
