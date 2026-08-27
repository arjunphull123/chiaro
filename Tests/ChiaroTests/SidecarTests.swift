import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Chiaro

@Suite struct SidecarTests {
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chiaro-sidecar-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTestJPEG(at url: URL, size: Int = 4) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return }
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let cgImage = context.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }

    @Test func photoStartsNeutralWithNoSidecar() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("plain.jpg")
        makeTestJPEG(at: url)

        let photo = Photo(url: url)
        #expect(photo.edit.isNeutral)
        #expect(!photo.starred)
        #expect(photo.snapshots.isEmpty)
    }

    @Test func writeReadAndRemoveSidecar() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("edited.jpg")
        makeTestJPEG(at: url)
        let besideURL = Sidecar.besideURL(url)

        let photo = Photo(url: url)
        photo.edit.exposure = 0.6
        photo.edit.temp = 12
        photo.starred = true
        photo.snapshots = [Sidecar.Snapshot(name: "v1", date: Date(), edit: photo.edit)]

        #expect(Sidecar.write(for: photo))
        #expect(FileManager.default.fileExists(atPath: besideURL.path))

        let doc = Sidecar.read(for: url)
        #expect(doc?.edit == photo.edit)
        #expect(doc?.starred == true)
        #expect(doc?.versions.count == 1)
        #expect(doc?.versions.first?.name == "v1")

        #expect(Sidecar.lastEditDate(for: url) != nil)

        // A revert to neutral, unstarred, versionless removes the beside-file.
        photo.edit = .neutral
        photo.starred = false
        photo.snapshots = []
        #expect(Sidecar.write(for: photo))
        #expect(!FileManager.default.fileExists(atPath: besideURL.path))
        #expect(Sidecar.lastEditDate(for: url) == nil)
        #expect(Sidecar.read(for: url) == nil)
    }

    @Test func keepsEditsOnMacForCloudPaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloudStorage = home.appendingPathComponent("Library/CloudStorage/Anything/x.jpg")
        let mobileDocs = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/x.jpg")
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("chiaro-sidecar-tests-\(UUID().uuidString)/x.jpg")

        #expect(Sidecar.keepsEditsOnMac(cloudStorage))
        #expect(Sidecar.keepsEditsOnMac(mobileDocs))
        #expect(!Sidecar.keepsEditsOnMac(tempFile))
    }

    @Test func handWrittenMinimalSidecarDecodes() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("manual.jpg")
        makeTestJPEG(at: url)
        let besideURL = Sidecar.besideURL(url)
        try Data(#"{"edit":{"exposure":0.5}}"#.utf8).write(to: besideURL)

        let doc = Sidecar.read(for: url)
        var expected = EditState()
        expected.exposure = 0.5
        #expect(doc?.edit == expected)
        #expect(doc?.starred == false)
    }

    @Test func legacyRatingKeyIsTolerated() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let starredURL = dir.appendingPathComponent("rated.jpg")
        makeTestJPEG(at: starredURL)
        try Data(#"{"rating":2}"#.utf8).write(to: Sidecar.besideURL(starredURL))
        let starredDoc = Sidecar.read(for: starredURL)
        #expect(starredDoc?.starred == true)
        #expect(starredDoc?.edit.isNeutral == true)

        let unratedURL = dir.appendingPathComponent("unrated.jpg")
        makeTestJPEG(at: unratedURL)
        try Data(#"{"rating":0}"#.utf8).write(to: Sidecar.besideURL(unratedURL))
        let unratedDoc = Sidecar.read(for: unratedURL)
        #expect(unratedDoc?.starred == false)
    }
}
