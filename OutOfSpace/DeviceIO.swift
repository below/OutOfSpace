import Foundation
import IOKit.hid
import Combine

@MainActor
final class ToyPadService: ObservableObject {
    @Published var connected: Bool = false
    @Published var log: [String] = []

    @Published var pads: [UInt8: (present: Bool, uid: String?)] = [
        1: (false, nil),
        2: (false, nil),
        3: (false, nil)
    ]

    private let manager: IOHIDManager
    internal var device: IOHIDDevice?

    // Must live long enough for callbacks
    private var inputReport = [UInt8](repeating: 0, count: 32)

    private let vendorID = 0x0E6F
    private let productID = 0x0241

    private let TOYPAD_INIT: [UInt8] = [
        0x55, 0x0f, 0xb0, 0x01, 0x28, 0x63, 0x29, 0x20,
        0x4c, 0x45, 0x47, 0x4f, 0x20, 0x32, 0x30, 0x31,
        0x34, 0xf7, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ]

    internal var msgCounter: UInt8 = 0x01

    /// Optional authentication strategy. If nil, the service will not attempt portal authentication.
    ///
    /// This keeps the code ready for a future, legitimate authentication flow without embedding
    /// any bypass logic.
    protocol AuthStrategy {
        /// Called after INIT (B0). Return `true` if authenticated, otherwise `false`.
        func authenticate(service: ToyPadService) async throws -> Bool
    }

    /// Set this from the outside if you ever have a legitimate way to authenticate.
    var authStrategy: AuthStrategy? = nil

    private var authState: AuthState = .unknown

    private enum AuthState {
        case unknown
        case notAuthenticated
        case authenticated
    }

    internal enum PendingKind {
        case readPages
        case other
    }

    internal struct Pending55 {
        let kind: PendingKind
        let continuation: CheckedContinuation<[UInt8], Error>
    }

    internal var pending55: [UInt8: Pending55] = [:]

    private func nextMsg() -> UInt8 {
        let m = msgCounter
        msgCounter &+= 1
        return m
    }

    /// Send a 0x55 command frame and await the 0x55 response payload (without checksum).
    private func request55(kind: PendingKind, dev: IOHIDDevice, cmd: [UInt8], timeoutNs: UInt64 = 800_000_000) async throws -> [UInt8] {
        // cmd must already include the leading 0x55, length, opcode, msg, ...
        guard cmd.count >= 4, cmd[0] == 0x55 else { throw ToyPadReadError.malformedResponse }
        let msg = cmd[3]

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
            pending55[msg] = Pending55(kind: kind, continuation: cont)
            sendCommand(dev, cmd)

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNs)
                if let pending = self.pending55.removeValue(forKey: msg) {
                    pending.continuation.resume(throwing: ToyPadReadError.timeout)
                }
            }
        }
    }

    private func ensureAuthenticatedIfPossible() async {
        switch authState {
        case .authenticated:
            return
        default:
            break
        }

        guard let strategy = authStrategy else {
            authState = .notAuthenticated
            return
        }

        do {
            let ok = try await strategy.authenticate(service: self)
            authState = ok ? .authenticated : .notAuthenticated
            appendLog(ok ? "Auth ✅ (strategy)" : "Auth ⛔️ (strategy returned false)")
        } catch {
            authState = .notAuthenticated
            appendLog("Auth ⛔️ (strategy threw): \(error)")
        }
    }

    enum ToyPadReadError: Error {
        case notConnected
        case timeout
        case malformedResponse
        case deviceError(status: UInt8)
        case checksumMismatch
    }
    
    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, dev in
            let this = Unmanaged<ToyPadService>.fromOpaque(context!).takeUnretainedValue()
            Task { @MainActor in await this.deviceMatched(dev) }
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, dev in
            let this = Unmanaged<ToyPadService>.fromOpaque(context!).takeUnretainedValue()
            Task { @MainActor in this.deviceRemoved(dev) }
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        appendLog(r == kIOReturnSuccess ? "HID manager open ✅" : "HID manager open ❌ \(r)")
    }

    func stop() {
        if let dev = device {
            IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        connected = false
        appendLog("Stopped.")
    }

    public func color(pad: Pad, r: UInt8, g: UInt8, b: UInt8) {
        guard let dev = self.device else { return }
        switchPad(dev, pad: pad, r: r, g: g, b: b)
    }
    
    private func createReadTagCommand(msg: UInt8, index: UInt8, page: UInt8) -> [UInt8] {
        [0x55, 0x04, 0xD2, msg, index, page]
    }
    
    func readPages(padByte: UInt8, startPage: UInt8) async throws -> [UInt8] {
        guard let dev = self.device else { throw ToyPadReadError.notConnected }

        if authState == .unknown {
            await ensureAuthenticatedIfPossible()
        }

        // D2 braucht den index (0/1/2), nicht pad (1/2/3)
//        guard let index = presentIndexByPad[padByte] else {
//            throw ToyPadReadError.malformedResponse
//        }
        let index = padByte
        let msg = nextMsg()
        appendLog("D2 READ msg=\(msg) pad=\(padByte) index=\(index) page=\(String(format:"%02X", startPage))")

        // cmd: 55 04 D2 <msg> <index> <page>
        let data16 = try await request55(
            kind: .readPages,
            dev: dev,
            cmd: createReadTagCommand(msg: msg, index: index, page: startPage)
        )

        // handle55Response(.readPages) liefert bereits nur die 16 Datenbytes
        guard data16.count == 16 else { throw ToyPadReadError.malformedResponse }
        return data16
    }

    private func d2PadByte(for pad: Pad) -> UInt8 {
        switch pad {
        case .right:  return 0
        case .center: return 1
        case .left:   return 2
        case .all:    return 1 // für read macht "all" keinen Sinn; nimm center als default
        }
    }
    
    private func publishPad(_ pad: UInt8, present: Bool, uid: String?) {
        pads[pad] = (present, uid)
    }

    private func runLightshow(on dev: IOHIDDevice) async {
        // Smooth ~3s lightshow using simple interpolation steps
        func lerp(_ a: UInt8, _ b: UInt8, _ t: Double) -> UInt8 {
            let av = Double(a)
            let bv = Double(b)
            return UInt8(max(0, min(255, Int(av + (bv - av) * t))))
        }

        @inline(__always)
        func fade(pad: Pad, from: (UInt8, UInt8, UInt8), to: (UInt8, UInt8, UInt8), duration: Double, steps: Int) async {
            let nanosPerStep = UInt64((duration / Double(steps)) * 1_000_000_000)
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let r = lerp(from.0, to.0, t)
                let g = lerp(from.1, to.1, t)
                let b = lerp(from.2, to.2, t)
                switchPad(dev, pad: pad, r: r, g: g, b: b)
                try? await Task.sleep(nanoseconds: nanosPerStep)
            }
        }

        // Start all off
        switchPad(dev, pad: .all, r: 0, g: 0, b: 0)
        try? await Task.sleep(nanoseconds: 80_000_000)

        // 1) Fade in center green (0.8s)
        await fade(pad: .center, from: (0, 0, 0), to: (0, 255, 0), duration: 0.8, steps: 12)

        // 2) Fade in left blue while slightly dimming center for motion (0.8s)
        await fade(pad: .left, from: (0, 0, 0), to: (0, 0, 255), duration: 0.8, steps: 12)
        await fade(pad: .center, from: (0, 255, 0), to: (0, 180, 0), duration: 0.3, steps: 6)

        // 3) Fade in right red (0.6s)
        await fade(pad: .right, from: (0, 0, 0), to: (255, 0, 0), duration: 0.6, steps: 10)

        // 4) Brief soft white pulse on all (0.5s up, 0.3s down)
        await fade(pad: .all, from: (100, 100, 100), to: (255, 255, 255), duration: 0.5, steps: 10)
        await fade(pad: .all, from: (255, 255, 255), to: (80, 80, 80), duration: 0.3, steps: 6)

        // 5) Sweep off: center -> left -> right (0.2s each)
        await fade(pad: .center, from: (80, 80, 80), to: (0, 0, 0), duration: 0.2, steps: 4)
        await fade(pad: .left, from: (80, 80, 80), to: (0, 0, 0), duration: 0.2, steps: 4)
        await fade(pad: .right, from: (80, 80, 80), to: (0, 0, 0), duration: 0.2, steps: 4)
    }

    private func deviceMatched(_ dev: IOHIDDevice) async {
        device = dev
        connected = true
        // New USB session → reset protocol state
        authState = .unknown
        msgCounter = 0x01
        pending55.removeAll()
        presentUIDByPad.removeAll()
        
        appendLog("Device matched: \(getString(dev, kIOHIDProductKey as CFString) ?? "—")")

        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else {
            appendLog("IOHIDDeviceOpen failed: \(r)")
            return
        }

        // INIT wakes it up
        sendOutputReport(dev, TOYPAD_INIT)

        // Quick lightshow to indicate the device is active (await before registering input)
 //       await runLightshow(on: dev)

        // Register input callback
        inputReport = [UInt8](repeating: 0, count: 32)
        inputReport.withUnsafeMutableBytes { buf in
            guard let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            IOHIDDeviceRegisterInputReportCallback(
                dev,
                ptr,
                buf.count,
                { context, result, _, _, reportID, report, reportLength in
                    let this = Unmanaged<ToyPadService>.fromOpaque(context!).takeUnretainedValue()
                    Task { @MainActor in
                        this.handleInput(result: result, reportID: reportID, report: report, length: reportLength)
                    }
                },
                Unmanaged.passUnretained(self).toOpaque()
            )
        }

        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        appendLog("Input callback registered + INIT sent.")
    }

    private func deviceRemoved(_ dev: IOHIDDevice) {
        if let current = device, CFEqual(current, dev) {
            pending55.removeAll()
            authState = .unknown
            device = nil
            connected = false
            appendLog("Device removed.")
        }
    }

    private func handleInput(result: IOReturn, reportID: UInt32, report: UnsafeMutablePointer<UInt8>?, length: CFIndex) {
        guard result == kIOReturnSuccess, let report, length > 0 else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))

        if bytes.count == 32, bytes[0] == 0x55 {
            if handle55Response(bytes) { return }
        }
        if let ev = parseTag(bytes) {
            handleTag(ev)
        }
    }

    private var presentUIDByPad: [UInt8: String] = [:]

    private func handleTag(_ ev: TagEv) {
        let uid = uidHex(ev.uid)

        switch ev.action {
        case 0: // inserted
            // Only log/publish if this is a new UID for that pad
            if presentUIDByPad[ev.pad] != uid {
                presentUIDByPad[ev.pad] = uid
                print("✅ \(padName(ev.pad)) inserted uid=\(uid)")
                publishPad(ev.pad, present: true, uid: uid)
            }
//            Task {
//                let array = try! await readPages(padByte: ev.pad, startPage: 0x24)
//                appendLog("Read Page 0x24: \(hex(array))")
//            }


        case 1: // removed
            // Only log/publish if something was present
            if presentUIDByPad[ev.pad] != nil {
                presentUIDByPad[ev.pad] = nil
                print("❌ \(padName(ev.pad)) removed")
                publishPad(ev.pad, present: false, uid: nil)
            }

        default:
            break
        }
    }

    private func padName(_ pad: UInt8) -> String {
        switch pad {
        case 1: return "Center"
        case 2: return "Left"
        case 3: return "Right"
        default: return "Pad \(pad)"
        }
    }
    
    private func uidHex(_ uid: [UInt8]) -> String {
        uid.map { String(format: "%02X", $0) }.joined()
    }
    
    private struct TagEv {
        let pad: UInt8        // 1=center, 2=left, 3=right
        let index: UInt8      // index
        let action: UInt8     // 0=inserted, 1=removed
        let uid: [UInt8]      // 7 bytes
    }

    private func parseTag(_ b: [UInt8]) -> TagEv? {
        guard b.count == 32 else { return nil }
        guard b[0] == 0x56, b[1] == 0x0B else { return nil }

        let pad = b[2]
        let index = b[4]          // 0,1,2  (slot)
        let action = b[5]
        let uid = Array(b[7...13]) // 7 bytes

        appendLog("TAG \(hex(b))")

        return TagEv(pad: pad, index: index, action: action, uid: uid)
    }

    private func handle55Response(_ b: [UInt8]) -> Bool {
        // Frame starts with 0x55 and is always 32 bytes (padded)
        guard b.count == 32, b[0] == 0x55 else { return false }

        let len = Int(b[1])

        // Two observed conventions exist in the wild:
        // A) len counts (payload + checksum) and excludes the msg byte.
        //    -> [55][len][msg][payload...][cs]
        // B) len counts (msg + payload + checksum).
        //    -> [55][len][msg][payload...][cs]
        // We try both and accept the one with a valid checksum.

        func parseA() -> (msg: UInt8, payload: [UInt8], cs: UInt8)? {
            let start = 3
            let end = start + len
            guard len >= 1, end <= b.count else { return nil }
            let msg = b[2]
            let payloadPlusCs = Array(b[start..<end])
            guard let cs = payloadPlusCs.last else { return nil }
            let payload = Array(payloadPlusCs.dropLast())
            return (msg, payload, cs)
        }

        func parseB() -> (msg: UInt8, payload: [UInt8], cs: UInt8)? {
            let start = 2
            let end = start + len
            guard len >= 2, end <= b.count else { return nil }
            let msg = b[2]
            let payloadPlusCs = Array(b[3..<end])
            guard let cs = payloadPlusCs.last else { return nil }
            let payload = Array(payloadPlusCs.dropLast())
            return (msg, payload, cs)
        }

        func checksumValid(lenByte: UInt8, msg: UInt8, payload: [UInt8], cs: UInt8) -> Bool {
            // checksum is sum of all bytes before checksum modulo 256
            var sum: UInt16 = 0
            sum += UInt16(0x55)
            sum += UInt16(lenByte)
            sum += UInt16(msg)
            for x in payload { sum += UInt16(x) }
            return UInt8(sum & 0xFF) == cs
        }

        let lenByte = b[1]

        let candidateA = parseA()
        let candidateB = parseB()

        let chosen: (msg: UInt8, payload: [UInt8], cs: UInt8)? = {
            if let a = candidateA, checksumValid(lenByte: lenByte, msg: a.msg, payload: a.payload, cs: a.cs) { return a }
            if let b = candidateB, checksumValid(lenByte: lenByte, msg: b.msg, payload: b.payload, cs: b.cs) { return b }
            // If neither matches, still try A as a last resort (some pads ignore checksum)
            return candidateA ?? candidateB
        }()

        guard let frame = chosen else { return false }

        // Only handle frames for pending requests we are awaiting.
        guard let pending = pending55.removeValue(forKey: frame.msg) else {
            return false
        }

        // Debug what we actually got (helps when status != 0 or payload is short)
        appendLog("IN55 len=\(len) msg=\(frame.msg) payloadLen=\(frame.payload.count) payload=\(hex(frame.payload))")

        switch pending.kind {
        case .other:
            pending.continuation.resume(returning: frame.payload)
            return true

        case .readPages:
            guard frame.payload.count >= 1 else {
                pending.continuation.resume(throwing: ToyPadReadError.malformedResponse)
                return true
            }

            let status = frame.payload[0]
            guard status == 0 else {
                pending.continuation.resume(throwing: ToyPadReadError.deviceError(status: status))
                return true
            }

            guard frame.payload.count >= 1 + 16 else {
                pending.continuation.resume(throwing: ToyPadReadError.malformedResponse)
                return true
            }

            let data16 = Array(frame.payload[1..<(1 + 16)])
            pending.continuation.resume(returning: data16)
            return true
        }
    }
    
    private func sendOutputReport(_ dev: IOHIDDevice, _ bytes: [UInt8], reportID: CFIndex = 0) {
        bytes.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: UInt8.self).baseAddress!
            let r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, reportID, ptr, bytes.count)
            appendLog(r == kIOReturnSuccess ? "OUT ✅ \(bytes.count) bytes" : "OUT ❌ \(r)")
        }
    }

    enum Pad: UInt8 {
        case all = 0
        case center = 1
        case left = 2
        case right = 3
    }

    private func checksum(_ bytes: [UInt8]) -> UInt8 {
        // modulo 256 sum
        var s: UInt16 = 0
        for b in bytes { s += UInt16(b) }
        return UInt8(s & 0xFF)
    }

    private func sendCommand(_ dev: IOHIDDevice, _ cmd: [UInt8]) {
        var message = cmd
        message.append(checksum(cmd))        // add checksum byte

        // pad to 32 bytes
        while message.count < 32 { message.append(0x00) }

        message.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: UInt8.self).baseAddress!
            let r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, ptr, message.count)
            if r == kIOReturnSuccess {
                print("⬆️ OUT \(message.count) bytes cmd=\(cmd.map{String(format:"%02X",$0)}.joined(separator:" "))")
            } else {
                print("IOHIDDeviceSetReport failed: \(r)")
            }
        }
    }

    func switchPad(_ dev: IOHIDDevice, pad: Pad, r: UInt8, g: UInt8, b: UInt8) {
        // 0x55 0x06 0xC0 0x02 = "switch pad color"
        // then: pad, R, G, B
        sendCommand(dev, [0x55, 0x06, 0xC0, 0x02, pad.rawValue, r, g, b])
    }

    // Convenience
    func padOff(_ dev: IOHIDDevice, pad: Pad) {
        switchPad(dev, pad: pad, r: 0, g: 0, b: 0)
    }
    
    private func appendLog(_ s: String) {
        log.append(s)
        if log.count > 200 { log.removeFirst(log.count - 200) }
        print(s)
    }

    private func getString(_ dev: IOHIDDevice, _ key: CFString) -> String? {
        IOHIDDeviceGetProperty(dev, key) as? String
    }
    
    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    func hex2(_ v: UInt8) -> String { String(format: "%02X", v) }
    func hexNoSpaces(_ bytes: [UInt8]) -> String { bytes.map { String(format:"%02X", $0) }.joined() }
}

