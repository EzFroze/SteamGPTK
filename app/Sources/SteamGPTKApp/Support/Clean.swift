import Foundation

enum Clean {

    static let backupSuffix = "steamgptk-orig"

    static func copy(of file: URL) -> URL {
        let backup = file.appendingPathExtension(backupSuffix)
        if FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)) { return backup }
        let previous = file.appendingPathExtension(LegacyInstallation.oldBackupSuffix)
        if FileManager.default.fileExists(atPath: previous.path) { return previous }
        return file
    }
}
