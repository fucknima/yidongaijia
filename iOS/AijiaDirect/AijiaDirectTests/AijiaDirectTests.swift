import XCTest
@testable import AijiaDirect

final class AijiaDirectTests: XCTestCase {
    func testVideoSignatureMatchesBridgeVector() {
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

    func testOfficialSMSPhoneEncryptionVector() throws {
        XCTAssertEqual(
            try AijiaSigning.officialEncryptedPhone("15706030115"),
            "185160AF37174B4C9A9DBD237443761A"
        )
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
}
