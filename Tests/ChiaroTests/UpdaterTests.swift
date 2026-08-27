import Testing
@testable import Chiaro

@Suite @MainActor struct UpdaterTests {
    @Test func patchVersionIsNewer() {
        #expect(Updater.isNewer("1.0.1", than: "1.0.0"))
    }

    @Test func minorVersionComparesNumerically() {
        #expect(Updater.isNewer("1.10.0", than: "1.9.0"))
    }

    @Test func majorVersionIsNewer() {
        #expect(Updater.isNewer("2.0.0", than: "1.99.99"))
    }

    @Test func sameVersionIsNotNewer() {
        #expect(!Updater.isNewer("1.0.0", than: "1.0.0"))
    }

    @Test func olderVersionIsNotNewer() {
        #expect(!Updater.isNewer("1.0.0", than: "1.0.1"))
    }
}
