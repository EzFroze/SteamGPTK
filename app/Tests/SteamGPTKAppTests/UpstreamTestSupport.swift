import Foundation

// Temporary fixtures shared by the selectively imported upstream regression tests.
func scratchDirectory(_ label: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "steamgptk-\(label)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
