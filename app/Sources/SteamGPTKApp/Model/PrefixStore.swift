// Logic for Prefix menu, not great, could use some improvements

import Darwin
import Foundation

struct SteamLibrary: Sendable, Hashable {
    let root: URL

    var volume: String?

    var steamapps: URL { root.appending(path: "steamapps") }
    var compatdata: URL { steamapps.appending(path: "compatdata") }

    var displayName: String {
        guard let volume else { return root.lastPathComponent }
        return volume
    }
}

enum PrefixArch: Sendable, Equatable {
    case arm64
    case x86_64
    case i386

    init?(machine: UInt16) {
        switch machine {
        case 0xaa64: self = .arm64
        case 0x8664: self = .x86_64
        case 0x014c: self = .i386
        default: return nil
        }
    }
}

struct WinePrefix: Sendable, Hashable, Identifiable {
    let appID: String
    let name: String?
    let library: SteamLibrary
    let lastUsed: Date?

    var root: URL { library.compatdata.appending(path: appID) }
    var pfx: URL { root.appending(path: "pfx") }

    var id: String { "\(library.root.path(percentEncoded: false))#\(appID)" }

    var title: String { name ?? "App \(appID)" }
}

struct PrefixUsage: Sendable {
    let bytes: Int64
    let profileFiles: Int
}

struct PrefixBackup: Sendable, Hashable, Identifiable {
    let prefix: WinePrefix
    let url: URL
    let taken: Date?
    let bytes: Int64

    var id: String { url.path(percentEncoded: false) }
    var title: String { prefix.title }
}

enum PrefixStore {

    static func libraries(vdf: URL = SupportPaths.Steam.libraryFoldersVDF) -> [SteamLibrary] {
        guard let text = try? String(contentsOf: vdf, encoding: .utf8) else {
            return [library(at: SupportPaths.Steam.userData)]
        }

        var roots: [URL] = []
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\"").map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard fields.count >= 2, fields[0] == "path" else { continue }
            roots.append(URL(filePath: fields[1]))
        }

        if roots.isEmpty { roots = [SupportPaths.Steam.userData] }

        var seen: Set<String> = []
        return roots.compactMap { root in
            guard seen.insert(root.path(percentEncoded: false)).inserted else { return nil }
            return library(at: root)
        }
    }

    static func library(at root: URL) -> SteamLibrary {
        SteamLibrary(root: root, volume: volumeName(of: root))
    }

    static func volumeName(of root: URL) -> String? {
        guard
            let values = try? root.resourceValues(forKeys: [.volumeNameKey, .volumeIsRootFileSystemKey]),
            values.volumeIsRootFileSystem != true,
            let name = values.volumeName
        else { return nil }
        return name
    }

    // Every appid under compatdata that actually has a prefix.
    static func all(libraries: [SteamLibrary] = PrefixStore.libraries()) -> [WinePrefix] {
        var found: [WinePrefix] = []
        for library in libraries {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: library.compatdata,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for entry in entries {
                let appID = entry.lastPathComponent
                let pfx = entry.appending(path: "pfx")
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: pfx.path(percentEncoded: false), isDirectory: &isDirectory),
                    isDirectory.boolValue
                else { continue }

                found.append(
                    WinePrefix(
                        appID: appID,
                        name: appName(appID: appID, in: library),
                        library: library,
                        lastUsed: (try? pfx.resourceValues(forKeys: [.contentModificationDateKey]))?
                            .contentModificationDate
                    )
                )
            }
        }

        return found.sorted {
            ($0.lastUsed ?? .distantPast, $0.appID) > ($1.lastUsed ?? .distantPast, $1.appID)
        }
    }

    static func appName(appID: String, in library: SteamLibrary) -> String? {
        manifestValue("name", appID: appID, in: library)
    }

    static func installDirectory(of prefix: WinePrefix) -> URL? {
        guard let folder = manifestValue("installdir", appID: prefix.appID, in: prefix.library)
        else { return nil }
        let url = prefix.library.steamapps.appending(path: "common").appending(path: folder)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    private static func manifestValue(_ key: String, appID: String, in library: SteamLibrary) -> String? {
        let manifest = library.steamapps.appending(path: "appmanifest_\(appID).acf")
        guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            // Steam escapes \" \\ \n and \t inside quoted values.
            let fields = line.matches(of: #/"((?:[^"\\]|\\.)*)"/#)
                .map {
                    String($0.1).replacing(#/\\(.)/#) { escape -> String in
                        switch escape.1 {
                        case "n": "\n"
                        case "t": "\t"
                        case "\\", "\"": String(escape.1)
                        default: String(escape.0)
                        }
                    }
                }
            if fields.count >= 2, fields[0] == key { return fields[1] }
        }
        return nil
    }

    static let backupPrefix = "pfx.previous"

    static func backupClock() -> DateFormatter {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "yyyyMMdd-HHmmss"
        return clock
    }

    static func backupDate(of backup: URL) -> Date? {
        let name = backup.lastPathComponent
        guard name.hasPrefix("\(backupPrefix)-") else { return nil }
        let stamp = name.dropFirst(backupPrefix.count + 1).prefix(15)
        return backupClock().date(from: String(stamp))
    }

    static func backupDetails(of prefix: WinePrefix) -> [PrefixBackup] {
        backups(of: prefix).map { url in
            PrefixBackup(
                prefix: prefix,
                url: url,
                taken: backupDate(of: url),
                bytes: directoryBytes(url)
            )
        }
    }

    static func backups(of prefix: WinePrefix) -> [URL] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: prefix.root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries
            .filter { $0.lastPathComponent.hasPrefix(backupPrefix) }
            .filter { entry in
                var isDirectory: ObjCBool = false
                let found = fm.fileExists(
                    atPath: entry.path(percentEncoded: false), isDirectory: &isDirectory)
                return found && isDirectory.boolValue
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func usage(of prefix: WinePrefix) -> PrefixUsage {
        let bytes = directoryBytes(prefix.pfx)

        var files = 0
        let users = prefix.pfx.appending(path: "drive_c/users").path(percentEncoded: false)
        if let out = try? Shell.check("/usr/bin/find", [users, "-type", "f"]) {
            files = out.split(separator: "\n").filter { !$0.isEmpty }.count
        }

        return PrefixUsage(bytes: bytes, profileFiles: files)
    }

    static func directoryBytes(_ url: URL) -> Int64 {
        guard let out = try? Shell.check("/usr/bin/du", ["-sk", url.path(percentEncoded: false)]),
            let kb = Int64(out.split(separator: "\t").first?.trimmingCharacters(in: .whitespaces) ?? "")
        else { return 0 }
        return kb * 1024
    }


    static func arch(of prefix: WinePrefix) -> PrefixArch? {
        let dll = prefix.pfx.appending(path: "drive_c/windows/system32/ntdll.dll")
        guard let handle = try? FileHandle(forReadingFrom: dll) else { return nil }
        defer { try? handle.close() }

        guard let dos = try? handle.read(upToCount: 0x40), dos.count == 0x40 else { return nil }
        let lfanew = dos.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0x3c, as: UInt32.self))
        }
        do { try handle.seek(toOffset: UInt64(lfanew)) } catch { return nil }

        guard let head = try? handle.read(upToCount: 6), head.count == 6,
            Array(head.prefix(4)) == [0x50, 0x45, 0x00, 0x00]
        else { return nil }

        return PrefixArch(
            machine: head.withUnsafeBytes {
                UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt16.self))
            }
        )
    }

    static var serverRoot: URL { URL(filePath: "/tmp/.wine-\(getuid())") }

    static func serverDirectory(of prefix: WinePrefix, root: URL = serverRoot) -> URL? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: prefix.pfx.path(percentEncoded: false)
            ),
            let device = attributes[.systemNumber] as? Int,
            let inode = attributes[.systemFileNumber] as? Int
        else { return nil }

        return root.appending(
            path: "server-\(String(device, radix: 16))-\(String(inode, radix: 16))")
    }

    static func isInUse(
        _ prefix: WinePrefix, root: URL = serverRoot, lsof: String = "/usr/sbin/lsof",
        drainTimeout: DispatchTimeInterval = .seconds(2)
    ) -> Bool {
        let lock = open(lockPath(of: prefix), O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        if lock >= 0 {
            defer { PrefixClaim(fd: lock).release() }
            guard locked(lock) else { return true }
        } else if errno != ENOENT {
            return true
        }
        return serverIsBusy(prefix, root: root, lsof: lsof, drainTimeout: drainTimeout)
    }

    // A launch takes this lock while it sets the prefix up. Holding it stops a launch from
    // starting partway through a rebuild/delete.
    static func claim(
        _ prefix: WinePrefix, root: URL = serverRoot, lsof: String = "/usr/sbin/lsof",
        drainTimeout: DispatchTimeInterval = .seconds(2)
    ) -> PrefixClaim? {
        let lock = open(lockPath(of: prefix), O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else {
            guard errno == ENOENT,
                !serverIsBusy(prefix, root: root, lsof: lsof, drainTimeout: drainTimeout)
            else { return nil }
            return PrefixClaim(fd: -1)
        }
        guard locked(lock), !serverIsBusy(prefix, root: root, lsof: lsof, drainTimeout: drainTimeout)
        else {
            PrefixClaim(fd: lock).release()
            return nil
        }
        return PrefixClaim(fd: lock)
    }

    private static func lockPath(of prefix: WinePrefix) -> String {
        prefix.root.appending(path: ".steamgptk-prefix.lock").path(percentEncoded: false)
    }

    private static func locked(_ fd: Int32) -> Bool {
        var info = stat()
        return fstat(fd, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
            && flock(fd, LOCK_EX | LOCK_NB) == 0
    }

    private static func serverIsBusy(
        _ prefix: WinePrefix, root: URL, lsof: String, drainTimeout: DispatchTimeInterval
    ) -> Bool {
        guard let dir = serverDirectory(of: prefix, root: root),
            FileManager.default.fileExists(atPath: dir.path(percentEncoded: false))
        else { return false }

        guard let result = try? Shell.run(
            lsof, ["-t", "+D", dir.path(percentEncoded: false)], drainTimeout: drainTimeout)
        else { return true }

        if !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }

        return result.outputLost || !result.stderr.isEmpty
    }
}

struct PrefixClaim {
    fileprivate let fd: Int32

    func release() {
        if fd >= 0 {
            _ = flock(fd, LOCK_UN)
            close(fd)
        }
    }
}
