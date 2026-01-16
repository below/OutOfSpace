import Foundation
import CommonCrypto

enum InfShaError: Error, CustomStringConvertible {
    case invalidUID
    case invalidSector

    var description: String {
        switch self {
        case .invalidUID: return "invalid UID (must match ^04[0-9a-f]{12}$)"
        case .invalidSector: return "invalid sector (0-4)"
        }
    }
}

struct InfShaKeyA {
    // Precomputed exactly like the Python:
    // PRE  = format(3 * 5 * 23 * 38844225342798321268237511320137937, "032x")
    // POST = format(3 * 7 * 9985861487287759675192201655940647, "030x")
    private static let preHex  = "0a14fd0507ff4bcd026ba83f0a3b89a9"   // 32 hex chars = 16 bytes
    private static let postHex = "286329204469736e65792032303133"     // 30 hex chars = 15 bytes

    private static let uidRegex = try! NSRegularExpression(pattern: #"^04[0-9a-f]{12}$"#,
                                                           options: [.caseInsensitive])

    /// Compute Key A (12 hex chars / 6 bytes) for the given UID.
    /// - Parameters:
    ///   - uidHex: 7-byte UID as 14 hex chars (must start with "04")
    ///   - sector: validated like the Python reference (0...4), but otherwise unused
    static func calcKeyA(uidHex: String, sector: Int = 0) throws -> String {
        // Validate UID
        let range = NSRange(uidHex.startIndex..<uidHex.endIndex, in: uidHex)
        guard uidRegex.firstMatch(in: uidHex, options: [], range: range) != nil else {
            throw InfShaError.invalidUID
        }

        // Validate sector (matches Python behavior)
        guard (0...4).contains(sector) else {
            throw InfShaError.invalidSector
        }

        // Build 38 bytes: PRE(16) + UID(7) + POST(15)
        guard
            let pre = Data(hex: preHex),
            let uid = Data(hex: uidHex),
            let post = Data(hex: postHex)
        else {
            // Should never happen if constants/UID are correct
            throw InfShaError.invalidUID
        }

        var payload = Data()
        payload.append(pre)
        payload.append(uid)
        payload.append(post)

        // SHA-1 digest (20 bytes)
        let digest = sha1(payload)

        // Key A bytes: digest[3], [2], [1], [0], [7], [6]
        let keyBytes: [UInt8] = [
            digest[3], digest[2], digest[1], digest[0],
            digest[7], digest[6]
        ]

        return Data(keyBytes).hexStringLowercased()
    }

    private static func sha1(_ data: Data) -> [UInt8] {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_SHA1(buf.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash
    }
}

// MARK: - Hex helpers

extension Data {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count % 2 == 0 else { return nil }

        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)

        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            let byteStr = hex[i..<j]
            guard let b = UInt8(byteStr, radix: 16) else { return nil }
            bytes.append(b)
            i = j
        }
        self = Data(bytes)
    }

    func hexStringLowercased() -> String {
        self.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Quick self-test (optional)

func testVectors() throws {
    let vectors: [(String, String)] = [
        ("0456263a873a80", "29564af75805"),
        ("049c0bb2a03784", "c0b423c8e4c2"),
        ("04a0f02a3d2d80", "1e0615823120"),
        ("04b40c12a13780", "2737629f2ebe"),
        ("04d9fb8a763b80", "edb56de8a9fe"),
    ]

    for (uid, expected) in vectors {
        let got = try InfShaKeyA.calcKeyA(uidHex: uid, sector: 0)
        if got != expected {
            print("FAIL uid=\(uid) expected=\(expected) got=\(got)")
        } else {
            print("OK   uid=\(uid) keyA=\(got)")
        }
    }
}

// Example:
 try? testVectors()
