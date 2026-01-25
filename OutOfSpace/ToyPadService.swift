import Foundation
import Combine
import DimensionPad

@MainActor
final class ToyPadService: ObservableObject {
    enum Pad {
        case all
        case center
        case left
        case right

        var rawValue: UInt8 {
            switch self {
            case .all: return 0
            case .center: return 1
            case .left: return 2
            case .right: return 3
            }
        }
    }

    @Published private(set) var connected: Bool = false
    @Published private(set) var pads: [UInt8: PadState] = [
        1: PadState(present: false, uid: nil, name: nil),
        2: PadState(present: false, uid: nil, name: nil),
        3: PadState(present: false, uid: nil, name: nil)
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
                try await pad.setColor(padByte: targetPad.rawValue, r: r, g: g, b: b)
            } catch {
                appendLog("color error: \(error)")
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
