import Testing
import Foundation
import CoreGraphics
import CryptoKit
@testable import Chiaro

@Suite struct RecentCardStoreTests {
    private func makeTestImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func fakePhotoURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("chiaro-recentcard-tests-\(UUID().uuidString)/photo.jpg")
    }

    /// Mirrors RecentCardStore's own digest so a test can find and delete
    /// exactly the files it wrote, without changing the store's visibility.
    private func digest(_ url: URL) -> String {
        SHA256.hash(data: Data(url.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private var recentCardsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chiaro/RecentCards")
    }

    private func removeFiles(for url: URL) {
        let prefix = digest(url)
        let files = (try? FileManager.default.contentsOfDirectory(at: recentCardsDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    @Test func saveThenLoadRoundTripsImageAndFocus() {
        let url = fakePhotoURL()
        defer { removeFiles(for: url) }
        let editDate = Date(timeIntervalSince1970: 1_700_000_000)
        let image = makeTestImage(width: 8, height: 6)
        let focus = CGPoint(x: 0.3, y: 0.7)

        RecentCardStore.save(.init(image: image, focus: focus), for: url, editDate: editDate)
        let loaded = RecentCardStore.load(url, editDate: editDate)

        #expect(loaded != nil)
        #expect(loaded?.image.width == image.width)
        #expect(loaded?.image.height == image.height)
        #expect(abs((loaded?.focus?.x ?? -1) - focus.x) < 0.001)
        #expect(abs((loaded?.focus?.y ?? -1) - focus.y) < 0.001)
    }

    @Test func loadWithDifferentEditDateReturnsNil() {
        let url = fakePhotoURL()
        defer { removeFiles(for: url) }
        let editDate = Date(timeIntervalSince1970: 1_700_000_000)
        let image = makeTestImage(width: 8, height: 6)

        RecentCardStore.save(.init(image: image, focus: nil), for: url, editDate: editDate)
        let mismatched = RecentCardStore.load(url, editDate: editDate.addingTimeInterval(10))
        #expect(mismatched == nil)
    }

    @Test func savingAgainRemovesThePreviousCard() {
        let url = fakePhotoURL()
        defer { removeFiles(for: url) }
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = firstDate.addingTimeInterval(100)

        RecentCardStore.save(.init(image: makeTestImage(width: 8, height: 6), focus: nil), for: url, editDate: firstDate)
        RecentCardStore.save(.init(image: makeTestImage(width: 10, height: 10), focus: nil), for: url, editDate: secondDate)

        #expect(RecentCardStore.load(url, editDate: firstDate) == nil)
        let current = RecentCardStore.load(url, editDate: secondDate)
        #expect(current?.image.width == 10)
        #expect(current?.image.height == 10)
    }
}
