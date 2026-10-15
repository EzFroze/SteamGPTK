import Foundation
import Testing

@testable import SteamGPTKApp

// The real rebuild against a clone of a real prefix, where every other test fakes wineboot.
// Caught My Documents going missing. Skipped without a runner and a prefix to clone.
enum RealPrefixes {
    static var library: SteamLibrary {
        SteamLibrary(root: URL(filePath: NSHomeDirectory())
            .appending(path: "Library/Application Support/Steam"))
    }

    // One prefix per profile shape: steamuser real, steamuser linked, and both real, which is
    // the shape a save was lost from. All three have to come out on the steamuser layout.
    static var candidates: [WinePrefix] {
        let loader = PrefixTools.layout(runner: SupportPaths.currentRunner).unixDir
        guard FileManager.default.fileExists(
            atPath: loader.path(percentEncoded: false)) else { return [] }
        func realDirectory(_ url: URL) -> Bool {
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            return values?.isSymbolicLink != true && values?.isDirectory == true
        }
        var real: WinePrefix?
        var linked: WinePrefix?
        var split: WinePrefix?
        for prefix in PrefixStore.all(libraries: [library]) where !PrefixStore.isInUse(prefix) {
            let users = prefix.pfx.appending(path: "drive_c/users")
            let steamuser = users.appending(path: "steamuser")
            // A prefix Steam has only just laid down holds the profile directory and none of
            // the registry, and every test here reads the registry.
            guard FileManager.default.fileExists(
                atPath: prefix.pfx.appending(path: "user.reg").path(percentEncoded: false)
            ) else { continue }
            guard let values = try? steamuser.resourceValues(
                forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) else { continue }
            if values.isSymbolicLink == true {
                linked = linked ?? prefix
            } else if values.isDirectory == true {
                if realDirectory(users.appending(path: "crossover")) {
                    split = split ?? prefix
                } else {
                    real = real ?? prefix
                }
            }
        }
        return [real, linked, split].compactMap { $0 }
    }
}

@Suite("Real rebuild", .serialized, .enabled(if: !RealPrefixes.candidates.isEmpty))
struct RealRebuildTests {
    private func clone(_ prefix: WinePrefix) throws -> WinePrefix {
        let dir = URL(filePath: NSTemporaryDirectory())
            .appending(path: "realrebuild-\(prefix.appID)-\(UUID().uuidString)")
        let library = SteamLibrary(root: dir)
        try FileManager.default.createDirectory(
            at: library.compatdata, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: prefix.root, to: library.compatdata.appending(path: prefix.appID))
        return WinePrefix(appID: prefix.appID, name: prefix.name, library: library, lastUsed: nil)
    }

    private func inventory(_ pfx: URL) -> (files: [String], links: [String]) {
        let fm = FileManager.default
        let users = pfx.appending(path: "drive_c/users").resolvingSymlinksInPath()
        let base = users.path(percentEncoded: false) + "/"
        var files: [String] = []
        var links: [String] = []
        let walker = fm.enumerator(
            at: users, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        while let entry = walker?.nextObject() as? URL {
            let full = entry.resolvingSymlinksInPath().path(percentEncoded: false)
            let path = full.hasPrefix(base) ? String(full.dropFirst(base.count)) : full
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                links.append(path)
            } else if values?.isDirectory != true {
                files.append(path)
            }
        }
        return (files.sorted(), links.sorted())
    }

    @Test("A real rebuild keeps every profile file and lands on the steamuser layout")
    func realRebuildKeepsBothProfiles() throws {
        for original in RealPrefixes.candidates {
            let prefix = try clone(original)
            defer { try? FileManager.default.removeItem(at: prefix.library.root) }

            let before = inventory(prefix.pfx)
            let registry = try Data(contentsOf: prefix.pfx.appending(path: "user.reg"))

            // No prefix here has one, so a game installed by hand is planted to be found.
            let stray = prefix.pfx.appending(path: "drive_c/Games/Quake/quake.exe")
            try FileManager.default.createDirectory(
                at: stray.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("exe".utf8).write(to: stray)

            try PrefixTools.recreate(prefix)
            let after = inventory(prefix.pfx)

            // Both profile names fold to one directory after a rebuild, as do the documents names
            // and BACKUP, which parks shared saves. That also hides a BACKUP the player made.
            func normalised(_ paths: [String]) -> Set<String> {
                Set(paths.map { path in
                    var parts = path.split(separator: "/").map(String.init)
                    guard !parts.isEmpty else { return path }
                    parts = parts.map { $0.replacing(#/ BACKUP( \d+)?$/#, with: "") }
                    parts[0] = "profile"
                    if parts.count > 1, ["Documents", "My Documents"].contains(parts[1]) {
                        parts[1] = "documents"
                    }
                    return parts.joined(separator: "/")
                })
            }
            #expect(normalised(after.files) == normalised(before.files),
                    "\(prefix.appID) lost profile files")
            #expect(try Data(contentsOf: prefix.pfx.appending(path: "user.reg")) == registry)
            #expect(try Data(contentsOf: stray) == Data("exe".utf8), "\(prefix.appID) lost C:\\Games")

            // Steam resolves a cloud rule under steamuser and CrossOver reads the name it fixes
            // on, so the one has to be the directory and the other the link to it.
            let users = prefix.pfx.appending(path: "drive_c/users")
            let crossover = users.appending(path: "crossover")
            let steamuser = users.appending(path: "steamuser")
            #expect(try FileManager.default.destinationOfSymbolicLink(
                atPath: crossover.path(percentEncoded: false)) == "steamuser")
            #expect((try? steamuser.resourceValues(forKeys: [.isSymbolicLinkKey]))?
                .isSymbolicLink != true)

            // Whichever name holds the files, a game asking for the other one has to arrive.
            let documents = steamuser.appending(path: "Documents")
            let preVista = steamuser.appending(path: "My Documents")
            for name in [documents, preVista] {
                var resolved = ObjCBool(false)
                #expect(FileManager.default.fileExists(
                    atPath: name.path(percentEncoded: false), isDirectory: &resolved))
                #expect(resolved.boolValue)
            }

            // Steam syncs saves from inside the prefix, so no redirected folder may resolve
            // back out to the mac home. Known folders only, the bug was those leading out.
            let inside = prefix.pfx.resolvingSymlinksInPath().path(percentEncoded: false)
            for folder in ["Documents", "My Documents", "Downloads", "Music", "Pictures", "Videos"] {
                let resolved = steamuser.appending(path: folder)
                    .resolvingSymlinksInPath().path(percentEncoded: false)
                #expect(resolved.hasPrefix(inside),
                        "\(prefix.appID) resolves \(folder) to \(resolved)")
            }

            // The windows tree is the fresh one, for the arch the installed runner builds.
            let ntdll = prefix.pfx.appending(path: "drive_c/windows/system32/ntdll.dll")
            #expect(PrefixStore.arch(of: prefix) == PrefixTools.prefixArch())
            #expect(FileManager.default.fileExists(atPath: ntdll.path(percentEncoded: false)))
        }
    }
}
