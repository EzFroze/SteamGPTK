// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation

struct FreeNtdllPatch: Decodable, Sendable {
    struct Range: Decodable, Sendable { let offset: Int; let bytes: String }
    let clean_sha256: String
    let patched_sha256: String
    let ranges: [Range]

    static func bundled() throws -> FreeNtdllPatch {
        guard let url = Bundle.module.url(forResource: "ntdll-sikarugir11", withExtension: "json") else {
            throw StepFailure(step: "Patch Wine", detail: "The Wine 11 detour specification is missing.")
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func apply(to original: Data) throws -> Data {
        if Digest.sha256(of: original) == patched_sha256 { return original }
        guard Digest.sha256(of: original) == clean_sha256 else {
            throw StepFailure(step: "Patch Wine", detail: "Unknown Wine ntdll. No patch was applied.")
        }
        var result = original
        for range in ranges {
            let hex = Array(range.bytes)
            guard hex.count % 2 == 0, range.offset >= 0,
                  range.offset <= result.count, hex.count / 2 <= result.count - range.offset else {
                throw StepFailure(step: "Patch Wine", detail: "The detour is outside the verified Wine file.")
            }
            var bytes: [UInt8] = []
            for i in stride(from: 0, to: hex.count, by: 2) {
                guard let byte = UInt8(String(hex[i...i+1]), radix: 16) else {
                    throw StepFailure(step: "Patch Wine", detail: "The detour specification is invalid.")
                }
                bytes.append(byte)
            }
            result.replaceSubrange(range.offset..<(range.offset + bytes.count), with: bytes)
        }
        guard Digest.sha256(of: result) == patched_sha256 else {
            throw StepFailure(step: "Patch Wine", detail: "The patched Wine checksum did not match; the original was preserved.")
        }
        return result
    }
}
