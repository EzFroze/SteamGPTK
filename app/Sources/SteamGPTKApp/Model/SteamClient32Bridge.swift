// SteamGPTK fork modifications, 2026-10-16. Existing component licenses apply.
import Foundation

// The pinned i386 bridge can also be loaded under the name steamclient.dll.
// Disable its .data allocator in that mode: it can overwrite bridge globals.
// This is the same return-NULL change already present in lsteamclient sources.
enum SteamClient32Bridge {
    static let cleanSHA256 = "a6d0e7872bafd7b81efa9d76fca6c374db8c41dcad9e127f01302e693ad54395"
    static let patchedSHA256 = "2cf10ac8d935abc81b4bbc0ee85a5199728c6a60ba3b1e6250cdc3e405fde781"

    static func patched(_ original: Data) throws -> Data {
        let hash = Digest.sha256(of: original)
        if hash == patchedSHA256 { return original }
        guard hash == cleanSHA256 else {
            throw StepFailure(step: "Set up the 32-bit Steam bridge",
                              detail: "Unknown lsteamclient build. No bridge patch was applied.")
        }
        var result = original
        result.replaceSubrange(0xbc40..<0xbc43, with: [0x31, 0xc0, 0xc3])
        guard Digest.sha256(of: result) == patchedSHA256 else {
            throw StepFailure(step: "Set up the 32-bit Steam bridge",
                              detail: "The patched bridge checksum did not match. The original was preserved.")
        }
        return result
    }
}
