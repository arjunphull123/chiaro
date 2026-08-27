import Testing
import Foundation
@testable import Chiaro

@Suite struct LibraryTests {
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chiaro-library-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func enumeratePhotosDedupesFiltersAndRecurses() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data().write(to: root.appendingPathComponent("a.ARW"))
        try Data().write(to: root.appendingPathComponent("a.JPG"))
        try Data().write(to: root.appendingPathComponent("b.jpg"))
        try Data().write(to: root.appendingPathComponent(".hidden.jpg"))
        try Data().write(to: root.appendingPathComponent("notes.txt"))
        let nested = root.appendingPathComponent("day1/nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("c.jpg"))

        let found = Library.enumeratePhotos(in: root)
        let names = Set(found.map(\.lastPathComponent))

        #expect(found.count == 3)
        #expect(names.contains("a.ARW"))
        #expect(!names.contains("a.JPG")) // RAW+JPEG pair collapses to the RAW
        #expect(names.contains("b.jpg"))
        #expect(names.contains("c.jpg"))
        #expect(!names.contains(".hidden.jpg"))
        #expect(!names.contains("notes.txt"))

        for url in found {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            #expect(!isDir.boolValue)
        }
    }

    @MainActor
    @Test func relativeAndTopFolder() {
        let library = Library()
        let root = URL(fileURLWithPath: "/tmp/chiaro-library-relative-test-\(UUID().uuidString)")
        library.folderURL = root

        let rootPhoto = Photo(url: root.appendingPathComponent("img.jpg"))
        #expect(library.relativeFolder(rootPhoto) == "")
        #expect(library.topFolder(rootPhoto) == nil)

        let nestedPhoto = Photo(url: root.appendingPathComponent("day1/img2.jpg"))
        #expect(library.relativeFolder(nestedPhoto) == "day1")
        #expect(library.topFolder(nestedPhoto) == "day1")

        let deeperPhoto = Photo(url: root.appendingPathComponent("day1/sub/img3.jpg"))
        #expect(library.relativeFolder(deeperPhoto) == "day1/sub")
        #expect(library.topFolder(deeperPhoto) == "day1")
    }
}
