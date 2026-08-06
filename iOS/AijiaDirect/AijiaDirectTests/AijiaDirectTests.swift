import XCTest
import UIKit
@testable import AijiaDirect

final class AijiaDirectTests: XCTestCase {
    func testVideoSignatureMatchesKnownVector() {
        let parameters = [
            "time": "2",
            "macId": "A",
            "nonce": "1",
        ]

        XCTAssertEqual(
            AijiaSigning.videoSignature(
                parameters: parameters,
                path: "/dcs/device/getLiveAddress"
            ),
            "7ce189139ad78c666484b579604b08c6"
        )
    }

    func testVideoSignatureIsIndependentOfDictionaryInsertionOrder() {
        let first: [String: String] = [
            "time": "1700000000000",
            "macId": "camera-1",
            "nonce": "1700000000000gs08t",
        ]
        let second: [String: String] = [
            "nonce": "1700000000000gs08t",
            "macId": "camera-1",
            "time": "1700000000000",
        ]

        XCTAssertEqual(
            AijiaSigning.videoSignature(parameters: first, path: "/dcs/device/getLiveAddress"),
            AijiaSigning.videoSignature(parameters: second, path: "/dcs/device/getLiveAddress")
        )
    }

    func testPTZDirectionsUseCapturedProtocolValues() {
        XCTAssertEqual(AijiaPTZDirection.up.apiValue, "1")
        XCTAssertEqual(AijiaPTZDirection.down.apiValue, "2")
        XCTAssertEqual(AijiaPTZDirection.left.apiValue, "3")
        XCTAssertEqual(AijiaPTZDirection.right.apiValue, "4")
    }

    func testRecordingIdentityAndDates() {
        let recording = AijiaRecording(startTime: 1_785_600_000, endTime: 1_785_606_402)
        XCTAssertEqual(recording.id, "1785600000-1785606402")
        XCTAssertEqual(recording.startDate.timeIntervalSince1970, 1_785_600_000, accuracy: 0.001)
        XCTAssertEqual(recording.endDate.timeIntervalSince1970, 1_785_606_402, accuracy: 0.001)
        XCTAssertEqual(recording.playbackStartTime, 1_785_600_001)
        XCTAssertEqual(recording.playbackTimestamp(for: 0), 1_785_600_001)
        XCTAssertEqual(recording.playbackTimestamp(for: 0.5), 1_785_603_201)
        XCTAssertEqual(recording.playbackTimestamp(for: 1), 1_785_606_401)
    }

    func testShortRecordingPlaybackStartStaysInsideInterval() {
        let recording = AijiaRecording(startTime: 100, endTime: 101)
        XCTAssertEqual(recording.playbackStartTime, 100)
        XCTAssertEqual(recording.playbackTimestamp(for: 0.5), 100)
    }

    func testCameraSelectorNormalization() {
        XCTAssertEqual(AijiaSigning.normalized(" Camera-01 "), "camera01")
        XCTAssertEqual(AijiaSigning.normalized("摄像头 1"), "摄像头1")
    }

    func testDiagnosticsHelpersDoNotExposeFullCredentials() {
        XCTAssertEqual(DiagnosticsLogger.maskPhone("13800138000"), "138*****00")
        XCTAssertEqual(
            DiagnosticsLogger.redactedURL(URL(string: "https://example.test/path?token=secret")!),
            "https://example.test/path"
        )
    }

    func testDiagnosticsJSONSummaryOnlyContainsSchema() {
        let payload: [String: Any] = [
            "code": 0,
            "data": [
                "token": "secret-token",
                "flv": "https://example.test/stream?signature=secret",
            ] as [String: Any],
        ]

        let summary = DiagnosticsLogger.jsonSummary(payload)
        XCTAssertTrue(summary.contains("objectKeys=code,data"))
        XCTAssertTrue(summary.contains("dataKeys=flv,token"))
        XCTAssertFalse(summary.contains("secret-token"))
        XCTAssertFalse(summary.contains("signature=secret"))
    }

    func testCredentialStoreKeepsExistingMetadataWhenPasswordWriteFails() {
        let suiteName = "AijiaDirectTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("13800138000", forKey: "savedLogin.phone")
        defaults.set("old-camera", forKey: "savedLogin.cameraSelector")
        let passwordStore = StubPasswordStore(password: "old-password", writeResult: false)
        let store = CredentialStore(defaults: defaults, passwordStore: passwordStore)

        XCTAssertFalse(
            store.save(
                phone: "13900139000",
                password: "new-password",
                cameraSelector: "new-camera"
            )
        )
        XCTAssertEqual(store.load()?.phone, "13800138000")
        XCTAssertEqual(store.load()?.password, "old-password")
        XCTAssertEqual(store.load()?.cameraSelector, "old-camera")
    }

    func testCredentialStoreCommitsMetadataAfterPasswordWriteSucceeds() {
        let suiteName = "AijiaDirectTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let passwordStore = StubPasswordStore(writeResult: true)
        let store = CredentialStore(defaults: defaults, passwordStore: passwordStore)

        XCTAssertTrue(
            store.save(
                phone: "13800138000",
                password: "password",
                cameraSelector: "front-door"
            )
        )
        XCTAssertEqual(store.load()?.phone, "13800138000")
        XCTAssertEqual(store.load()?.password, "password")
        XCTAssertEqual(store.load()?.cameraSelector, "front-door")
    }

    @MainActor
    func testPlayerViewModelCanStartWithInjectedDependencies() async {
        let credentialStore = StubCredentialStore()
        let camera = AijiaCamera(
            id: "camera-id",
            name: "Front Door",
            macID: "camera-mac",
            baseURL: URL(string: "https://example.test")!,
            jwtoken: "token"
        )
        let apiClient = StubAijiaAPIClient(
            openStreamResult: .success(
                AijiaStream(
                    camera: camera,
                    url: URL(string: "https://example.test/live.flv")!
                )
            )
        )
        let model = PlayerViewModel(
            credentialStore: credentialStore,
            makeAPIClient: { _, _, _ in apiClient }
        )
        model.phone = " 13800138000 "
        model.password = "password"
        model.cameraSelector = "front-door"

        model.start()
        await waitUntil { model.isAuthenticated || model.hasError }

        XCTAssertEqual(apiClient.openStreamCallCount, 1)
        XCTAssertTrue(model.isAuthenticated)
        XCTAssertFalse(model.hasError)
        XCTAssertEqual(model.cameraName, "Front Door")
        XCTAssertEqual(model.streamURL, URL(string: "https://example.test/live.flv"))
        XCTAssertEqual(credentialStore.savedLogin?.phone, "13800138000")
        XCTAssertEqual(credentialStore.savedLogin?.cameraSelector, "camera-mac")
        model.stop()
    }

    @MainActor
    func testPlayerViewModelSurfacesInjectedClientFailure() async {
        let credentialStore = StubCredentialStore()
        let apiClient = StubAijiaAPIClient(openStreamResult: .failure(StubAPIError.failed))
        let model = PlayerViewModel(
            credentialStore: credentialStore,
            makeAPIClient: { _, _, _ in apiClient }
        )
        model.phone = "13800138000"
        model.password = "password"

        model.start()
        await waitUntil { !model.isLoading }

        XCTAssertEqual(apiClient.openStreamCallCount, 0)
        XCTAssertFalse(model.isAuthenticated)
        XCTAssertTrue(model.hasError)
        XCTAssertTrue(model.shouldShowLogin)
        XCTAssertEqual(credentialStore.saveCallCount, 0)
    }

    @MainActor
    func testPlayerSurfaceHostMigrationIsSafeWithoutActivePlayer() {
        // The player surface view is owned by the player instance; before the
        // player exists, mounting hosts must be a no-op that never crashes.
        let model = PlayerViewModel(
            credentialStore: StubCredentialStore(),
            makeAPIClient: { _, _, _ in
                StubAijiaAPIClient(openStreamResult: .failure(StubAPIError.failed))
            }
        )
        let inlineHost = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let fullscreenHost = UIView(frame: CGRect(x: 0, y: 0, width: 844, height: 390))

        model.mountPlayerSurface(in: inlineHost, role: .inline)
        model.layoutPlayerSurface(in: inlineHost)
        XCTAssertTrue(inlineHost.subviews.isEmpty)

        model.mountPlayerSurface(in: fullscreenHost, role: .fullscreen)
        XCTAssertTrue(inlineHost.subviews.isEmpty)
        XCTAssertTrue(fullscreenHost.subviews.isEmpty)

        model.mountPlayerSurface(in: inlineHost, role: .inline)
        model.unmountPlayerSurface(from: fullscreenHost, role: .fullscreen)
        XCTAssertTrue(fullscreenHost.subviews.isEmpty)

        model.mountPlayerSurface(in: fullscreenHost, role: .fullscreen)
        model.unmountPlayerSurface(from: inlineHost, role: .inline)
        model.layoutPlayerSurface(in: fullscreenHost)

        model.unmountPlayerSurface(from: fullscreenHost, role: .fullscreen)
        model.mountPlayerSurface(in: inlineHost, role: .inline)
        model.layoutPlayerSurface(in: inlineHost)
        XCTAssertTrue(inlineHost.subviews.isEmpty)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class StubPasswordStore: PasswordStoring {
    private(set) var password: String?
    var writeResult: Bool

    init(password: String? = nil, writeResult: Bool) {
        self.password = password
        self.writeResult = writeResult
    }

    func read() -> String? {
        password
    }

    func write(_ password: String) -> Bool {
        guard writeResult else { return false }
        self.password = password
        return true
    }

    func clear() {
        password = nil
    }
}

private final class StubCredentialStore: CredentialStoring {
    var loadedLogin: SavedAijiaLogin?
    var autoConnectEnabled = true
    var saveResult = true
    private(set) var savedLogin: SavedAijiaLogin?
    private(set) var saveCallCount = 0

    func load() -> SavedAijiaLogin? {
        loadedLogin
    }

    func isAutoConnectEnabled() -> Bool {
        autoConnectEnabled
    }

    func setAutoConnectEnabled(_ enabled: Bool) {
        autoConnectEnabled = enabled
    }

    func loadCachedCameras() -> [AijiaCamera] {
        []
    }

    func saveCachedCameras(_ cameras: [AijiaCamera]) {}

    func save(phone: String, password: String, cameraSelector: String) -> Bool {
        saveCallCount += 1
        guard saveResult else { return false }
        let login = SavedAijiaLogin(
            phone: phone,
            password: password,
            cameraSelector: cameraSelector
        )
        savedLogin = login
        loadedLogin = login
        return true
    }

    func clear() {
        loadedLogin = nil
        savedLogin = nil
        autoConnectEnabled = false
    }
}

private enum StubAPIError: LocalizedError {
    case failed

    var errorDescription: String? {
        "stub failure"
    }
}

private final class StubAijiaAPIClient: AijiaAPIClient {
    let openStreamResult: Result<AijiaStream, Error>
    private(set) var openStreamCallCount = 0

    init(openStreamResult: Result<AijiaStream, Error>) {
        self.openStreamResult = openStreamResult
    }

    func authenticate() async throws {}

    func cameras() async throws -> [AijiaCamera] {
        [try openStreamResult.get().camera]
    }

    func selectCamera(_ camera: AijiaCamera) {}

    func openStream() async throws -> AijiaStream {
        openStreamCallCount += 1
        return try openStreamResult.get()
    }

    func keepAlive() async throws {}

    func controlPTZ(direction: AijiaPTZDirection) async throws {}

    func queryRecordings(startTime: Int64, endTime: Int64) async throws -> [AijiaRecording] {
        []
    }

    func playRecording(at timestamp: Int64) async throws -> URL {
        URL(string: "https://example.test/replay.flv")!
    }

    func seekRecording(at timestamp: Int64) async throws {}

    func keepReplayAlive() async throws {}

    func stopReplay() async throws {}
}
