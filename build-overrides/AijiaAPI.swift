import CryptoKit
import Foundation

#if canImport(Darwin)
import Darwin
#endif

struct AijiaCamera: Identifiable {
    let id: String
    let name: String
    let macID: String
    let baseURL: URL
    var jwtoken: String

    init(_ raw: [String: Any]) throws {
        let macID = aijiaStringValue(raw["mac_id"] ?? raw["macId"])
        let fallbackID = aijiaStringValue(raw["device_id"] ?? raw["cmei"] ?? raw["sn"])
        let identity = aijiaStringValue(raw["id"])
        let name = aijiaStringValue(raw["mac_name"] ?? raw["name"])
        let baseString = aijiaStringValue(raw["baseUrl"] ?? raw["base_url"])

        guard !macID.isEmpty, let baseURL = URL(string: baseString) else {
            throw AijiaAPIError.invalidResponse
        }

        self.id = identity.isEmpty ? (fallbackID.isEmpty ? macID : fallbackID) : identity
        self.name = name.isEmpty ? macID : name
        self.macID = macID
        self.baseURL = baseURL
        self.jwtoken = aijiaStringValue(raw["jwtoken"])
    }
}

struct AijiaStream {
    let camera: AijiaCamera
    let url: URL
}

enum AijiaLoginMethod: String, CaseIterable, Identifiable {
    case password
    case smsCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password: return "密码登录"
        case .smsCode: return "验证码登录"
        }
    }
}

enum AijiaPTZDirection: String, CaseIterable, Identifiable {
    case up
    case down
    case left
    case right

    var id: String { rawValue }

    // The official client uses 1=up, 2=down, 3=left and 4=right.
    var apiValue: String {
        switch self {
        case .up: return "1"
        case .down: return "2"
        case .left: return "3"
        case .right: return "4"
        }
    }

    var title: String {
        switch self {
        case .up: return "上"
        case .down: return "下"
        case .left: return "左"
        case .right: return "右"
        }
    }

    var systemImage: String {
        switch self {
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        }
    }
}

struct AijiaRecording: Identifiable, Equatable {
    let startTime: Int64
    let endTime: Int64

    var id: String { "\(startTime)-\(endTime)" }
    var startDate: Date { Date(timeIntervalSince1970: TimeInterval(startTime)) }
    var endDate: Date { Date(timeIntervalSince1970: TimeInterval(endTime)) }

    var playbackStartTime: Int64 {
        guard endTime - startTime > 1 else { return startTime }
        return startTime + 1
    }

    /// Maps the UI position to the actual server-side TF interval returned by
    /// getDeviceTFInfo. The official client sends this timestamp to
    /// playTFLive; VLC itself is not used for seeking.
    func playbackTimestamp(for position: Double) -> Int64 {
        guard endTime - startTime > 1 else { return startTime }

        let duration = endTime - startTime
        let lowerBound = startTime + 1
        let upperBound = max(lowerBound, endTime - 1)
        let clampedPosition = max(0.0, min(1.0, position))
        let candidate = startTime + Int64((Double(duration) * clampedPosition).rounded())
        return min(max(candidate, lowerBound), upperBound)
    }
}

enum AijiaAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case server(action: String, message: String)
    case missingField(action: String, field: String)
    case emptyCameraList
    case cameraNotFound
    case invalidURL
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "云端返回的数据格式无法识别"
        case let .httpStatus(code):
            return "云端 HTTP 错误（\(code)）"
        case let .server(action, message):
            return "\(action)：\(message)"
        case let .missingField(action, field):
            return "\(action)缺少字段 \(field)"
        case .emptyCameraList:
            return "账号下没有可用摄像头"
        case .cameraNotFound:
            return "没有找到指定的摄像头"
        case .invalidURL:
            return "云端返回了无效的播放地址"
        case .sessionExpired:
            return "登录会话已失效"
        }
    }
}

enum AijiaSigning {
    static let videoSignKey = "r8rw4d1kjwqgqqto9dwsq3ew0ip2np1b"

    static func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func sha1(_ value: String) -> String {
        Insecure.SHA1.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func videoSignature(parameters: [String: String], path: String) -> String {
        let ordered = parameters.keys.sorted().map { key in
            key + (parameters[key] ?? "")
        }.joined()
        return md5(ordered + path + videoSignKey)
    }

    static func normalized(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

private func aijiaStringValue(_ value: Any?) -> String {
    guard let value = value, !(value is NSNull) else { return "" }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return String(describing: value)
}

final class AijiaAPI {
    private static let baseLoginURL = URL(string: "https://base.hjq.komect.com/base/user/passwdLogin")!
    private static let baseSendVerificationCodeURL = URL(string: "https://base.hjq.komect.com/base/authentication/sendMsg")!
    private static let baseSendVerificationCodeProURL = URL(string: "https://base.hjq.komect.com/base/authentication/sendMsgPro")!
    private static let baseSMSLoginURL = URL(string: "https://base.hjq.komect.com/base/user/uniAuth/smsCodeLogin")!
    private static let videoLoginURL = URL(string: "https://video.komect.com/user/login/loginByHJQToken")!
    private static let cameraListURL = URL(string: "https://video.komect.com/camera/core/api/bind/queryList")!
    private static let cameraTokenURL = URL(string: "https://video.komect.com/camera/auth/getToken")!
    private static let successfulResponseCodes: Set<String> = ["0", "1000000"]

    private let phone: String
    private let password: String?
    private let verificationCode: String?
    private let loginMethod: AijiaLoginMethod
    private let cameraSelector: String
    private let deviceID = UUID().uuidString
    private let session: URLSession
    private let logger = DiagnosticsLogger.shared

    private var hjqToken = ""
    private var passID = ""
    private var videoToken = ""
    private var camera: AijiaCamera?
    private var userSelectedProvCode = ""
    private var userSelectedCityCode = ""

    private let phoneModel = aijiaHardwareModel()
    private let osVersion = aijiaOperatingSystemVersion()

    private init(
        phone: String,
        password: String?,
        verificationCode: String?,
        loginMethod: AijiaLoginMethod,
        cameraSelector: String
    ) {
        self.phone = phone
        self.password = password
        self.verificationCode = verificationCode
        self.loginMethod = loginMethod
        self.cameraSelector = AijiaSigning.normalized(cameraSelector)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration)
        logger.info(
            "API",
            "初始化客户端 account=\(DiagnosticsLogger.maskPhone(phone)) cameraSelector=\(self.cameraSelector.isEmpty ? "<first>" : DiagnosticsLogger.maskIdentifier(self.cameraSelector))"
        )
    }

    convenience init(phone: String, password: String, cameraSelector: String) {
        self.init(
            phone: phone,
            password: password,
            verificationCode: nil,
            loginMethod: .password,
            cameraSelector: cameraSelector
        )
    }

    convenience init(phone: String, verificationCode: String, cameraSelector: String) {
        self.init(
            phone: phone,
            password: nil,
            verificationCode: verificationCode,
            loginMethod: .smsCode,
            cameraSelector: cameraSelector
        )
    }

    convenience init(phone: String, cameraSelector: String) {
        self.init(
            phone: phone,
            password: nil,
            verificationCode: nil,
            loginMethod: .smsCode,
            cameraSelector: cameraSelector
        )
    }

    func requestVerificationCode() async throws {
        logger.info("AUTH", "开始获取短信验证码 account=\(DiagnosticsLogger.maskPhone(phone))")

        let body: [String: Any] = [
            // These are the names used by the official login service. The
            // second alias is accepted by older base-service deployments.
            "userPhone": phone,
            "phoneNumber": phone,
            "optType": "pwLoginNew",
        ]
        do {
            try await sendVerificationCode(to: Self.baseSendVerificationCodeURL, body: body)
        } catch let error as AijiaAPIError {
            let shouldTryProEndpoint: Bool
            switch error {
            case .server(_, _), .httpStatus(404):
                shouldTryProEndpoint = true
            default:
                shouldTryProEndpoint = false
            }
            guard shouldTryProEndpoint else { throw error }
            logger.warning("AUTH", "验证码普通接口未接受请求，尝试官方 Pro 接口")
            try await sendVerificationCode(to: Self.baseSendVerificationCodeProURL, body: body)
        }
        logger.info("AUTH", "短信验证码发送成功")
    }

    private func sendVerificationCode(to endpoint: URL, body: [String: Any]) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        applyClientHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let payload = try await requestJSON(request)
        try requireSuccess(in: payload, action: "获取验证码")
    }

    func openStream() async throws -> AijiaStream {
        logger.info("API", "开始获取实时流")
        var lastError: Error = AijiaAPIError.invalidResponse

        for attempt in 0..<2 {
            do {
                logger.debug("API", "实时流尝试 \(attempt + 1)/2")
                if videoToken.isEmpty {
                    try await loginVideo()
                }
                if camera == nil {
                    camera = try await selectCamera(from: cameraList())
                }

                guard var selectedCamera = camera else {
                    throw AijiaAPIError.emptyCameraList
                }
                if selectedCamera.jwtoken.isEmpty {
                    selectedCamera.jwtoken = try await deviceToken(for: selectedCamera)
                    camera = selectedCamera
                }

                let liveURL = try await liveAddress(for: selectedCamera)
                logger.info(
                    "API",
                    "获取实时流成功 camera=\(DiagnosticsLogger.maskIdentifier(selectedCamera.macID)) url=\(DiagnosticsLogger.redactedURL(liveURL))"
                )
                return AijiaStream(camera: selectedCamera, url: liveURL)
            } catch {
                lastError = error
                logger.error("API", "实时流尝试失败 attempt=\(attempt + 1) error=\(error.localizedDescription)")
                if attempt == 0 {
                    resetSession()
                }
            }
        }

        throw lastError
    }

    func keepAlive() async throws {
        guard let camera = camera, !videoToken.isEmpty, !camera.jwtoken.isEmpty else {
            logger.warning("API", "保活跳过，会话或设备令牌不完整")
            throw AijiaAPIError.sessionExpired
        }

        logger.debug("API", "发送保活 camera=\(DiagnosticsLogger.maskIdentifier(camera.macID))")

        let endpoint = try endpoint(base: camera.baseURL, path: "/dcs/device/keepOpenLiveAddress")
        let timestamp = currentTimestamp()
        var parameters = [
            "macId": camera.macID,
            "nonce": timestamp + "gs08t",
            "time": timestamp,
        ]
        parameters["sign"] = AijiaSigning.videoSignature(
            parameters: parameters,
            path: endpoint.path
        )
        logger.debug(
            "REPLAY",
            "playTFLive request startTime=\(timestamp) nonceDigits=\(parameters["nonce"]?.count ?? 0)"
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        applyClientHeaders(to: &request, timestamp: timestamp)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(videoToken, forHTTPHeaderField: "AuthorizationToken")
        request.setValue(camera.jwtoken, forHTTPHeaderField: "AuthorizationJwtoken")
        request.httpBody = formBody(parameters)

        let payload = try await requestJSON(request)
        try requireSuccess(in: payload, action: "保活")
        logger.debug("API", "保活成功")
    }

    func controlPTZ(direction: AijiaPTZDirection) async throws {
        let camera = try authenticatedCamera()
        let endpoint = try endpoint(base: camera.baseURL, path: "/dcs/device/ptzControl")
        let timestamp = currentTimestamp()
        var parameters = [
            // The captured official client sends one short start request for
            // each tap. It does not send the long-press stop variant here.
            "action": "start",
            "ctrlType": "0",
            "direction": direction.apiValue,
            "macId": camera.macID,
            "nonce": requestNonce(timestamp: timestamp),
            "time": timestamp,
        ]
        parameters["sign"] = AijiaSigning.videoSignature(
            parameters: parameters,
            path: endpoint.path
        )

        let request = signedGET(url: endpoint, parameters: parameters) {
            $0.setValue(videoToken, forHTTPHeaderField: "AuthorizationToken")
            $0.setValue(camera.jwtoken, forHTTPHeaderField: "AuthorizationJwtoken")
        }
        let payload = try await requestJSON(request)
        try requireSuccess(in: payload, action: "云台\(direction.title)转")
        logger.info("PTZ", "云台控制成功 direction=\(direction.rawValue) apiDirection=\(direction.apiValue)")
    }

    func queryRecordings(startTime: Int64, endTime: Int64) async throws -> [AijiaRecording] {
        do {
            return try await queryRecordingsOnce(startTime: startTime, endTime: endTime)
        } catch {
            guard isSessionExpiredError(error) else { throw error }
            logger.warning("API", "历史录像会话已过期，重新登录后重试")
            _ = try await refreshCameraSession()
            return try await queryRecordingsOnce(startTime: startTime, endTime: endTime)
        }
    }

    private func queryRecordingsOnce(startTime: Int64, endTime: Int64) async throws -> [AijiaRecording] {
        let camera = try authenticatedCamera()
        let endpoint = try endpoint(base: camera.baseURL, path: "/dcs/device/getDeviceTFInfo")
        let timestamp = currentTimestamp()
        var parameters = [
            "endTime": String(endTime),
            "macId": camera.macID,
            "nonce": requestNonce(timestamp: timestamp),
            "startTime": String(startTime),
            "time": timestamp,
        ]
        parameters["sign"] = AijiaSigning.videoSignature(
            parameters: parameters,
            path: endpoint.path
        )

        let request = signedFormPOST(url: endpoint, parameters: parameters) {
            $0.setValue(videoToken, forHTTPHeaderField: "AuthorizationToken")
            $0.setValue(camera.jwtoken, forHTTPHeaderField: "AuthorizationJwtoken")
        }
        let payload = try await requestJSON(request)
        let data = try requireData(in: payload, action: "读取历史录像")
        let dictionary = data as? [String: Any]
        let rawList = (dictionary?["record_list"] as? [[String: Any]])
            ?? (dictionary?["recordList"] as? [[String: Any]])
            ?? []
        let recordings = rawList.compactMap { item -> AijiaRecording? in
            guard let start = int64Value(item["start_time"] ?? item["startTime"]),
                  let end = int64Value(item["end_time"] ?? item["endTime"]),
                  end > start else {
                return nil
            }
            return AijiaRecording(startTime: start, endTime: end)
        }
        logger.info("REPLAY", "历史录像查询成功 count=\(recordings.count)")
        return recordings.sorted { $0.startTime < $1.startTime }
    }

    func playRecording(at timestamp: Int64) async throws -> URL {
        do {
            return try await playRecordingOnce(at: timestamp)
        } catch {
            guard isSessionExpiredError(error) else { throw error }
            logger.warning("API", "历史回放会话已过期，重新登录后重试")
            _ = try await refreshCameraSession()
            return try await playRecordingOnce(at: timestamp)
        }
    }

    private func playRecordingOnce(at timestamp: Int64) async throws -> URL {
        let camera = try authenticatedCamera()
        let endpoint = try endpoint(base: camera.baseURL, path: "/dcs/device/playTFLive")

        // The official client allocates the TF playback transfer first. It
        // requests the playback URL, then moves that transfer to startTime.
        // Calling playTFLive before getTFLiveAddress returns business code 1.
        try Task.checkCancellation()
        let replayURL = try await replayAddress(for: camera)
        try Task.checkCancellation()
        logger.debug("REPLAY", "TF replay address preflight complete timestamp=\(timestamp)")

        try await sendPlayRecording(at: timestamp, camera: camera, endpoint: endpoint, action: "打开历史录像")
        return replayURL
    }

    /// Moves an already allocated TF transfer to another timestamp. This is
    /// the official card-replay seek path and intentionally does not request a
    /// new playback address on every drag.
    func seekRecording(at timestamp: Int64) async throws {
        do {
            try await seekRecordingOnce(at: timestamp)
        } catch {
            guard isSessionExpiredError(error) else { throw error }
            logger.warning("API", "历史回放跳转会话已过期，重新登录后重试")
            _ = try await refreshCameraSession()
            try await seekRecordingOnce(at: timestamp)
        }
    }

    private func seekRecordingOnce(at timestamp: Int64) async throws {
        let camera = try authenticatedCamera()
        let endpoint = try endpoint(base: camera.baseURL, path: "/dcs/device/playTFLive")
        try await sendPlayRecording(at: timestamp, camera: camera, endpoint: endpoint, action: "跳转历史录像")
    }

    private func sendPlayRecording(
        at timestamp: Int64,
        camera: AijiaCamera,
        endpoint: URL,
        action: String
    ) async throws {

        let now = currentTimestamp()
        var parameters = [
            "macId": camera.macID,
            "nonce": requestNonce(timestamp: now),
            "startTime": String(timestamp),
            "time": now,
            "userId": phone,
        ]
        parameters["sign"] = AijiaSigning.videoSignature(
            paramet…1150 tokens truncated….isEmpty else {
            throw AijiaAPIError.server(action: "登录", message: "缺少密码")
        }

        let body: [String: Any] = [
            "virtualAuthdata": AijiaSigning.md5(password),
            "authType": "10",
            "userAccount": phone,
            "authdata": AijiaSigning.sha1("fetion.com.cn:" + password),
        ]

        var request = URLRequest(url: Self.baseLoginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (payload, response) = try await requestJSONWithResponse(request)
        try completeBaseLogin(payload: payload, response: response, action: "登录")
        logger.info("API", "基础账号密码登录成功")
    }

    private func loginBaseWithSMS() async throws {
        logger.info("API", "开始短信验证码登录 account=\(DiagnosticsLogger.maskPhone(phone))")
        guard let verificationCode = verificationCode,
              !verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AijiaAPIError.server(action: "登录", message: "缺少短信验证码")
        }

        // The official client exposes validCheckCode on the login service,
        // while older base-service deployments use validateCode/phoneNumber.
        // Login attempts are safe to retry because they do not send another SMS.
        let candidates: [[String: Any]] = [
            ["userAccount": phone, "validateCode": verificationCode, "authType": "10"],
            ["phoneNumber": phone, "validateCode": verificationCode, "authType": "10"],
            ["userPhone": phone, "validCheckCode": verificationCode, "authType": "10"],
        ]

        var lastError: Error?
        for (index, body) in candidates.enumerated() {
            do {
                var request = URLRequest(url: Self.baseSMSLoginURL)
                request.httpMethod = "POST"
                applyClientHeaders(to: &request)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (payload, response) = try await requestJSONWithResponse(request)
                try completeBaseLogin(payload: payload, response: response, action: "验证码登录")
                logger.info("API", "短信验证码登录成功")
                return
            } catch {
                lastError = error
                logger.warning("API", "验证码登录参数方案失败 attempt=\(index + 1) error=\(error.localizedDescription)")
            }
        }

        throw lastError ?? AijiaAPIError.invalidResponse
    }

    private func completeBaseLogin(
        payload: [String: Any],
        response: HTTPURLResponse,
        action: String
    ) throws {
        let data = try requireData(in: payload, action: action)
        guard let dataDictionary = data as? [String: Any] else {
            throw AijiaAPIError.invalidResponse
        }

        let passID = stringValue(dataDictionary["passId"])
        var cookie = ""
        if let header = response.value(forHTTPHeaderField: "Set-Cookie"),
           let firstCookie = header.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first,
           let cookieValue = firstCookie.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true).last {
            cookie = String(cookieValue)
        }

        guard !passID.isEmpty, !cookie.isEmpty else {
            throw AijiaAPIError.server(action: action, message: "没有返回有效会话")
        }

        self.passID = passID
        hjqToken = cookie
        userSelectedProvCode = stringValue(dataDictionary["provCode"])
        userSelectedCityCode = stringValue(dataDictionary["cityCode"])
    }

    private func loginVideo() async throws {
        logger.info("API", "开始视频服务登录")
        if hjqToken.isEmpty || passID.isEmpty {
            try await loginBase()
        }

        let timestamp = currentTimestamp()
        var parameters = [
            "HJQToken": hjqToken,
            "nonce": timestamp + "abcde",
            "passId": passID,
            "time": timestamp,
            "userId": phone,
        ]
        parameters["sign"] = AijiaSigning.videoSignature(
            parameters: parameters,
            path: Self.videoLoginURL.path
        )

        var request = URLRequest(url: Self.videoLoginURL)
        request.httpMethod = "POST"
        applyClientHeaders(to: &request, timestamp: timestamp)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(parameters)

        let payload = try await requestJSON(request)
        let data = try requireData(in: payload, action: "视频登录")
        guard let dataDictionary = data as? [String: Any] else {
            throw AijiaAPIError.invalidResponse
        }

        let token = stringValue(dataDictionary["token"])
        guard !token.isEmpty else {
            throw AijiaAPIError.missingField(action: "视频登录", field: "token")
        }
        videoToken = token
        logger.info("API", "视频服务登录成功 token=present")
    }

    private func cameraList() async throws -> [[String: Any]] {
        guard !videoToken.isEmpty else {
            throw AijiaAPIError.sessionExpired
        }

        let timestamp = currentTimestamp()
        var parameters = [
            "nonce": timestamp + "m5kjt",
            "number": "100",
            "page": "1",
            "time": timestamp,
            "user_id": phone,
        ]
        parameters["sign"] = AijiaSigning.videoSignature(
            parameters: parameters,
            path: Self.cameraListURL.path
        )

        let request = signedGET(url: Self.cameraListURL, parameters: parameters) {
            $0.setValue(videoToken, forHTTPHeaderField: "AuthorizationToken")
        }
        let payload = try await requestJSON(request)
        let data = try requireData(in: payload, action: "读取摄像头列表")

        if let list = data as? [[String: Any]] {
            guard !list.isEmpty else { throw AijiaAPIError.emptyCameraList }
            logger.info("API", "读取摄像头列表成功 count=\(list.count)")
            return list
        }
        if let dictionary = data as? [String: Any], let list = dictionary["list"] as? [[String: Any]] {
            guard !list.isEmpty else { throw AijiaAPIError.emptyCameraList }
            logger.info("API", "读取摄像头列表成功 count=\(list.count)")
            return list
        }
        throw AijiaAPIError.invalidResponse
    }

    private func selectCamera(from records: [[String: Any]]) throws -> AijiaCamera {
        let candidates = try records.map { try AijiaCamera($0) }
        guard !candidates.isEmpty else {
            throw AijiaAPIError.emptyCameraList
        }
        guard !cameraSelector.isEmpty else {
            logger.info("API", "选择第一台摄像头 camera=\(DiagnosticsLogger.maskIdentifier(candidates[0].macID))")
            return candidates[0]
        }

        let match = candidates.first { candidate in
            [candidate.macID, candidate.name, candidate.id]
                .map(AijiaSigning.normalized)
                .contains(cameraSelector)
        }
        guard let match = match else {
            throw AijiaAPIError.cameraNotFound
        }
        logger.info("API", "按选择器匹配摄像头 camera=\(DiagnosticsLogger.maskIdentifier(match.macID))")
        return match
    }

    private func deviceToken(for camera: AijiaCamera) async throws -> String {
        let endpoint = Self.cameraTokenURL
        let timestamp = currentTimestamp()
        let millis = Int64(timestamp) ?? 0
        var parameters = [
            "macId": camera.macID,
            "nonce": String(100_000 + Int(millis % 900_000)),
            "time": timestamp,
        ]
        parameters["sign"] = AijiaSigning.videoSignature(
            parameters: parameters,
            path: endpoint.path
        )

        let request = signedGET(url: endpoint, parameters: parameters) {
            $0.setValue(videoToken, forHTTPHeaderField: "AuthorizationToken")
        }
        let payload = try await requestJSON(request)

        if let data = payload["data"] as? [String: Any] {
            let token = stringValue(data["jwtoken"])
            if !token.isEmpty {
                logger.debug("API", "获取设备令牌成功 camera=\(DiagnosticsLogger.maskIdentifier(camera.macID))")
                return token
            }
        }
        let token = stringValue(payload["jwtoken"])
        if !token.isEmpty {
            logger.debug("API", "获取设备令牌成功 camera=\(DiagnosticsLogger.maskIdentifier(camera.macID))")
            return token
        }

        let message = stringValue(payload["msg"] ?? payload["message"]) 
        throw AijiaAPIError.server(action: "获取设备令牌", message: message.isEmpty ? "未知错误" : message)
    }

    private func liveAddress(for camera: AijiaCamera) async throws -> URL {
        let endpoint = try endpoint(base: camera.baseURL, path: "/dcs/device/getLiveAddress")
        let timestamp = currentTimestamp()
        var parameters = [
            "macId": camera.macID,
            "nonce": timestamp + "gs08t",
            "requestTime": timestamp,
            "time": timestamp,
        ]
        parameters["sign"] = AijiaSigning.videoSignature(
            parameters: parameters,
            path: endpoint.path
        )

        let request = signedGET(url: endpoint, parameters: parameters) {
            $0.setValue(videoToken, forHTTPHeaderField: "AuthorizationToken")
            $0.setValue(camera.jwtoken, forHTTPHeaderField: "AuthorizationJwtoken")
        }
        let payload = try await requestJSON(request)
        let data = try requireData(in: payload, action: "获取实时地址")
        guard let dataDictionary = data as? [String: Any] else {
            throw AijiaAPIError.invalidResponse
        }

        let rawURL = stringValue(dataDictionary["flv"] ?? dataDictionary["liveFlv"])
        guard let url = URL(string: rawURL), !rawURL.isEmpty else {
            throw AijiaAPIError.invalidURL
        }
        logger.debug("API", "实时地址解析成功 url=\(DiagnosticsLogger.redactedURL(url))")
        return url
    }

    private func refreshCameraSession() async throws -> AijiaCamera {
        resetSession()
        try await loginVideo()
        let records = try await cameraList()
        var selectedCamera = try selectCamera(from: records)
        if selectedCamera.jwtoken.isEmpty {
            selectedCamera.jwtoken = try await deviceToken(for: selectedCamera)
        }
        camera = selectedCamera
        logger.info("API", "设备会话刷新成功 camera=\(DiagnosticsLogger.maskIdentifier(selectedCamera.macID))")
        return selectedCamera
    }

    private func isSessionExpiredError(_ error: Error) -> Bool {
        guard let apiError = error as? AijiaAPIError else { return false }
        if case .sessionExpired = apiError {
            return true
        }
        if case let .server(_, message) = apiError {
            let normalized = message.uppercased()
            return normalized.contains("JWT_TOKEN_AUTH_EXPIRE") || normalized.contains("TOKEN_AUTH_EXPIRE")
        }
        return false
    }

    private func resetSession() {
        logger.warning("API", "重置云端会话")
        hjqToken = ""
        passID = ""
        videoToken = ""
        camera = nil
        userSelectedProvCode = ""
        userSelectedCityCode = ""
    }

    private func signedGET(
        url: URL,
        parameters: [String: String],
        customize: (inout URLRequest) -> Void
    ) -> URLRequest {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = parameters.keys.sorted().map {
            URLQueryItem(name: $0, value: parameters[$0])
        }
        var request = URLRequest(url: components.url!)
        applyClientHeaders(to: &request, timestamp: parameters["time"] ?? parameters["requestTime"])
        customize(&request)
        return request
    }

    private func signedFormPOST(
        url: URL,
        parameters: [String: String],
        customize: (inout URLRequest) -> Void
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyClientHeaders(to: &request, timestamp: parameters["time"] ?? parameters["requestTime"])
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        customize(&request)
        request.httpBody = formBody(parameters)
        return request
    }

    private func applyClientHeaders(to request: inout URLRequest, timestamp: String? = nil) {
        let requestTimestamp = timestamp ?? currentTimestamp()
        request.setValue("hejiaqin", forHTTPHeaderField: "AppName")
        request.setValue("hejiaqin", forHTTPHeaderField: "AppKey")
        request.setValue(deviceID, forHTTPHeaderField: "DeviceId")
        request.setValue("IOS", forHTTPHeaderField: "DeviceType")
        request.setValue(phoneModel, forHTTPHeaderField: "PhoneModel")
        request.setValue(osVersion, forHTTPHeaderField: "OsVersion")
        request.setValue(osVersion, forHTTPHeaderField: "OSType")
        request.setValue("WIFI", forHTTPHeaderField: "NetworkType")
        request.setValue("10.8.0", forHTTPHeaderField: "AppVersion")
        request.setValue("6.11.1", forHTTPHeaderField: "Version")
        request.setValue(phone, forHTTPHeaderField: "PhoneNum")
        request.setValue(requestTimestamp, forHTTPHeaderField: "Timestamp")
        request.setValue(userSelectedCityCode, forHTTPHeaderField: "UserSelectedCityCode")
        request.setValue(userSelectedProvCode, forHTTPHeaderField: "UserSelectedProvCode")
        request.setValue(userSelectedCityCode, forHTTPHeaderField: "CityCode")
        request.setValue(userSelectedProvCode, forHTTPHeaderField: "ProvCode")
        request.setValue(userSelectedProvCode, forHTTPHeaderField: "ProviceCode")
        request.setValue("UniApp", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("u=3, i", forHTTPHeaderField: "Priority")
        request.setValue(
            AijiaSigning.md5("\(deviceID)-\(UUID().uuidString)-\(currentTimestamp())"),
            forHTTPHeaderField: "EventSign"
        )
    }

    private func endpoint(base: URL, path: String) throws -> URL {
        let baseString = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: baseString + path) else {
            throw AijiaAPIError.invalidURL
        }
        return url
    }

    private func formBody(_ parameters: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = parameters.keys.sorted().map {
            URLQueryItem(name: $0, value: parameters[$0])
        }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func requestJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (payload, _) = try await requestJSONWithResponse(request)
        return payload
    }

    private func requestJSONWithResponse(_ request: URLRequest) async throws -> ([String: Any], HTTPURLResponse) {
        let endpoint = request.url.map(DiagnosticsLogger.redactedURL) ?? "<unknown>"
        let startedAt = Date()
        logger.debug("HTTP", "请求开始 method=\(request.httpMethod ?? "GET") endpoint=\(endpoint)")

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
            logger.error(
                "HTTP",
                "请求失败 endpoint=\(endpoint) durationMs=\(duration) error=\(error.localizedDescription)"
            )
            throw error
        }
        let data = result.0
        let response = result.1
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("HTTP", "响应不是 HTTP endpoint=\(endpoint)")
            throw AijiaAPIError.invalidResponse
        }
        let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "<none>"
        logger.debug(
            "HTTP",
            "响应收到 status=\(httpResponse.statusCode) endpoint=\(endpoint) bytes=\(data.count) durationMs=\(duration) contentType=\(contentType)"
        )
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AijiaAPIError.httpStatus(httpResponse.statusCode)
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("HTTP", "响应 JSON 格式无法识别 endpoint=\(endpoint)")
            throw AijiaAPIError.invalidResponse
        }
        logger.debug("HTTP", "响应结构 endpoint=\(endpoint) \(DiagnosticsLogger.jsonSummary(payload))")
        return (payload, httpResponse)
    }

    private func requireData(in payload: [String: Any], action: String) throws -> Any {
        try requireSuccess(in: payload, action: action)
        guard let data = payload["data"], !(data is NSNull) else {
            let message = stringValue(payload["msg"] ?? payload["message"])
            throw AijiaAPIError.server(action: action, message: message.isEmpty ? "未知错误" : message)
        }
        return data
    }

    private func requireSuccess(in payload: [String: Any], action: String) throws {
        let codeString = stringValue(payload["code"])
        if !codeString.isEmpty, !Self.successfulResponseCodes.contains(codeString) {
            let message = stringValue(payload["msg"] ?? payload["message"])
            logger.error("API", "\(action)返回业务错误 code=\(codeString) message=\(message)")
            throw AijiaAPIError.server(action: action, message: message.isEmpty ? "错误码 \(codeString)" : message)
        }
    }

    private func stringValue(_ value: Any?) -> String {
        guard let value = value, !(value is NSNull) else { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }

    private func int64Value(_ value: Any?) -> Int64? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }

    private func currentTimestamp() -> String {
        String(Int64(Date().timeIntervalSince1970 * 1000))
    }

    private func requestNonce(timestamp: String) -> String {
        timestamp + String(Int64.random(in: 1_000_000_000...9_999_999_999))
    }
}

private func aijiaHardwareModel() -> String {
#if canImport(Darwin)
    var size: Int = 0
    guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 1 else {
        return "iPhone"
    }

    var machine = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else {
        return "iPhone"
    }
    return String(cString: machine)
#else
    return "iPhone"
#endif
}

private func aijiaOperatingSystemVersion() -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
}

