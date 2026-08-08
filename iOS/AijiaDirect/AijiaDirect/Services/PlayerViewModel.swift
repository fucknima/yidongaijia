import Combine
import Foundation

#if canImport(Darwin)
import Darwin
#endif
import IJKMediaFramework
import UIKit

@MainActor
final class PlayerViewModel: NSObject, ObservableObject {
    private static let replayRefreshAfterBackgroundThreshold: TimeInterval = 15

    @Published var phone = ""
    @Published var password = ""
    @Published var cameraSelector = ""
    @Published var rememberLogin = true
    @Published private(set) var status = "请输入移动爱家账号"
    @Published private(set) var cameraName = ""
    @Published private(set) var cameras: [AijiaCamera] = []
    @Published private(set) var selectedCameraID = ""
    @Published private(set) var streamURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var hasError = false
    @Published private(set) var hasSavedLogin = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var shouldShowLogin = true
    @Published private(set) var isReplay = false
    @Published private(set) var replayRecording: AijiaRecording?
    @Published private(set) var replayPosition: Float = 0
    @Published private(set) var replayCurrentSecond: Int64 = 0
    @Published private(set) var replayDurationSecond: Int64 = 0
    @Published private(set) var recordings: [AijiaRecording] = []
    @Published private(set) var isLoadingRecordings = false
    @Published private(set) var cloudDays: [Int64] = []
    @Published private(set) var cloudSegments: [AijiaCloudSegment] = []
    @Published private(set) var cloudClips: [AijiaCloudClip] = []
    @Published private(set) var isLoadingCloud = false
    @Published private(set) var isCloudReplay = false
    @Published private(set) var cloudSelectedDay: Int64 = 0
    @Published private(set) var playerViewID = UUID()
    @Published private(set) var networkSpeedText = "-- KB/s"
    @Published private(set) var shouldPresentCameraSelection = false
    @Published private(set) var isRecording = false

    private var api: AijiaAPIClient?
    private var player: IJKFFMoviePlayerController?
    private var prewarmTask: Task<Void, Never>?
    private var prewarmedStream: AijiaStream?
    private var prewarmCameraID = ""
    private var replayPlaybackStartTime: Int64?
    private var replaySeekTask: Task<Void, Never>?
    private var replaySeekGeneration = 0
    private var replayProgressTimer: Timer?
    private var recordingsTask: Task<Void, Never>?
    private var recordingsQueryGeneration = 0
    private var recordingsQueryKey: String?
    private var recordingsLastCompletedAt: Date?
    private var playbackTask: Task<Void, Never>?
    private var replayCleanupTask: Task<Void, Never>?
    private var playbackOperationID = 0
    private weak var inlineSurfaceHost: UIView?
    private weak var fullscreenSurfaceHost: UIView?
    private weak var activeSurfaceHost: UIView?
    private var keepAliveTimer: Timer?
    private var networkSpeedTimer: Timer?
    private var lastNetworkReceivedBytes: UInt64?
    private var lastNetworkSpeedSampleDate: Date?
    private var shouldPlay = false
    private var reconnectInFlight = false
    private var foregroundRefreshInFlight = false
    private var didEnterBackgroundWhilePlaying = false
    private var replayBackgroundedAt: Date?
    private var didUserLogout = false
    private var didAutoConnect = false
    private var isHistoryVisible = false
    private var lastLoggedPlayerState = ""
    private var lastLoggedPlaybackSecond = -10
    private var recordingFileURL: URL?
    private var playbackStateObserver: NSObjectProtocol?
    private var playbackFinishObserver: NSObjectProtocol?
    private var loadStateObserver: NSObjectProtocol?
    private var naturalSizeObserver: NSObjectProtocol?
    private var firstFrameProbeTask: Task<Void, Never>?
    /// Whether the live player has decoded its first frame. Screenshots and
    /// recordings are gated on this: right after a connection the media
    /// pipeline may not have produced a frame yet, and IJK returns an error
    /// (-2) for snapshot/record in that window.
    @Published private(set) var hasFirstFrame = false
    private let logger = DiagnosticsLogger.shared
    private let credentialStore: CredentialStoring
    private let makeAPIClient: (String, String?, String) -> AijiaAPIClient

    init(
        credentialStore: CredentialStoring = CredentialStore.shared,
        makeAPIClient: @escaping (String, String?, String) -> AijiaAPIClient = {
            AijiaAPI(phone: $0, password: $1, cameraSelector: $2)
        }
    ) {
        self.credentialStore = credentialStore
        self.makeAPIClient = makeAPIClient
        super.init()
        if let savedLogin = credentialStore.load() {
            let autoConnectEnabled = credentialStore.isAutoConnectEnabled()
            phone = savedLogin.phone
            password = savedLogin.password
            cameraSelector = savedLogin.cameraSelector
            selectedCameraID = savedLogin.cameraSelector
            cameras = credentialStore.loadCachedCameras()
            hasSavedLogin = true
            shouldShowLogin = !autoConnectEnabled
            didUserLogout = !autoConnectEnabled
            status = autoConnectEnabled ? "已恢复保存的登录信息" : "登录信息已保存，请手动登录"
            logger.info(
                "AUTH",
                "已从钥匙串恢复登录信息 account=\(DiagnosticsLogger.maskPhone(phone)) autoConnect=\(autoConnectEnabled) cachedCameraCount=\(cameras.count)"
            )
        } else {
            logger.info("AUTH", "未找到保存的登录信息")
        }
        registerPlayerObservers()
    }

    deinit {
        let center = NotificationCenter.default
        if let observer = playbackStateObserver {
            center.removeObserver(observer)
        }
        if let observer = playbackFinishObserver {
            center.removeObserver(observer)
        }
        if let observer = loadStateObserver {
            center.removeObserver(observer)
        }
        if let observer = naturalSizeObserver {
            center.removeObserver(observer)
        }
    }

    private func registerPlayerObservers() {
        let center = NotificationCenter.default
        playbackStateObserver = center.addObserver(
            forName: NSNotification.Name("IJKMPMoviePlayerPlaybackStateDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handlePlaybackStateChanged(notification)
            }
        }
        playbackFinishObserver = center.addObserver(
            forName: NSNotification.Name("IJKMPMoviePlayerPlaybackDidFinish"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handlePlaybackFinished(notification)
            }
        }
        loadStateObserver = center.addObserver(
            forName: NSNotification.Name("IJKMPMoviePlayerLoadStateDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleLoadStateChanged(notification)
            }
        }
        naturalSizeObserver = center.addObserver(
            forName: NSNotification.Name("IJKMPMovieNaturalSizeAvailable"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleNaturalSizeAvailable(notification)
            }
        }
    }

    func autoConnectIfSaved() {
        guard hasSavedLogin, !didAutoConnect, !didUserLogout, !password.isEmpty else { return }
        didAutoConnect = true
        logger.info("AUTH", "启动后自动连接")
        start()
    }

    func start(allowCurrentCameraWhenNotRemembered: Bool = false) {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let credentialIsMissing = password.isEmpty
        guard !trimmedPhone.isEmpty, !credentialIsMissing else {
            status = "请填写手机号和密码"
            hasError = true
            logger.warning("AUTH", "登录被阻止，账号或密码为空")
            return
        }

        logger.info("PLAYER", "用户发起连接 account=\(DiagnosticsLogger.maskPhone(trimmedPhone))")
        didUserLogout = false
        let operationID = beginPlaybackOperation()
        cancelRecordingsQuery()
        finishReplayIfNeeded()
        isReplay = false
        resetReplayPlaybackState()
        resetCloudReplayState()
        stopPlaybackOnly()
        let loginPassword = password
        let shouldRememberLogin = rememberLogin
        let selectedCamera = (!shouldRememberLogin && !allowCurrentCameraWhenNotRemembered) ? "" : cameraSelector
        if !shouldRememberLogin {
            credentialStore.clear()
            hasSavedLogin = false
            logger.info(
                "AUTH",
                "用户未选择记住登录，开始登录前清除本地保存信息 account=\(DiagnosticsLogger.maskPhone(trimmedPhone)) useCurrentCamera=\(allowCurrentCameraWhenNotRemembered)"
            )
        }
        let client = makeAPIClient(trimmedPhone, loginPassword, selectedCamera)
        api = client
        shouldPlay = true
        isLoading = true
        isPlaying = false
        hasError = false
        cameraName = ""
        streamURL = nil
        status = selectedCamera.isEmpty ? "正在登录并读取摄像头…" : "正在登录并获取实时地址…"
        shouldPresentCameraSelection = false

        let task = Task(priority: .userInitiated) { [weak self, client, operationID] in
            do {
                try await client.authenticate()
                let availableCameras = try await client.cameras()
                guard let self = self,
                      self.isCurrentPlaybackOperation(operationID),
                      self.shouldPlay,
                      self.api === client else { return }
                cameras = availableCameras
                credentialStore.saveCachedCameras(availableCameras)
                logger.info("PLAYER", "摄像头列表已缓存 count=\(availableCameras.count)")
                isAuthenticated = true
                shouldShowLogin = false

                guard let selected = cameraToPlay(from: availableCameras, selector: selectedCamera) else {
                    isLoading = false
                    isPlaying = false
                    hasError = false
                    status = availableCameras.isEmpty ? "账号下没有摄像头" : "请选择要播放的摄像头"
                    logger.info("PLAYER", "登录成功，已读取摄像头列表但暂未选择设备 count=\(availableCameras.count)")
                    if shouldRememberLogin {
                        if credentialStore.save(
                            phone: trimmedPhone,
                            password: loginPassword,
                            cameraSelector: ""
                        ) {
                            hasSavedLogin = true
                            credentialStore.setAutoConnectEnabled(false)
                            logger.info("AUTH", "登录信息已保存，等待用户选择摄像头 account=\(DiagnosticsLogger.maskPhone(trimmedPhone))")
                        } else {
                            logger.error("AUTH", "登录信息保存失败")
                        }
                    } else {
                        logger.info("AUTH", "用户未选择记住登录，已清除本地登录信息")
                    }
                    if !availableCameras.isEmpty {
                        shouldPresentCameraSelection = true
                        logger.info("UI", "登录完成且未选择摄像头，准备自动打开选择页 count=\(availableCameras.count)")
                    }
                    return
                }

                client.selectCamera(selected)
                cameraSelector = selected.macID
                selectedCameraID = selected.macID

                // Reuse the pre-warmed stream (camera already woken and the
                // live address resolved) so the first frame appears quickly.
                let stream: AijiaStream
                if let warmed = self.prewarmedStream,
                   warmed.camera.macID == selected.macID {
                    stream = warmed
                    self.prewarmedStream = nil
                    self.prewarmCameraID = ""
                    logger.info("PLAYER", "复用预加载实时流 camera=\(DiagnosticsLogger.maskIdentifier(selected.macID))")
                } else {
                    stream = try await client.openStream()
                }

                guard self.isCurrentPlaybackOperation(operationID),
                      self.shouldPlay,
                      self.api === client else { return }
                cameraName = stream.camera.name
                streamURL = stream.url
                isLoading = false
                isPlaying = true
                status = "已连接，正在本机解码"
                hasError = false

                if shouldRememberLogin {
                    if credentialStore.save(
                        phone: trimmedPhone,
                        password: loginPassword,
                        cameraSelector: self.cameraSelector
                    ) {
                        hasSavedLogin = true
                        credentialStore.setAutoConnectEnabled(true)
                        logger.info("AUTH", "登录信息已保存到钥匙串 account=\(DiagnosticsLogger.maskPhone(trimmedPhone))")
                    } else {
                        logger.error("AUTH", "登录信息保存失败")
                    }
                } else {
                    credentialStore.clear()
                    hasSavedLogin = false
                    logger.info("AUTH", "用户关闭记住登录，已清除本地登录信息")
                }

                preparePlayerIfPossible()
                scheduleKeepAlive()
            } catch {
                guard let self = self,
                      self.isCurrentPlaybackOperation(operationID),
                      self.api === client else { return }
                isLoading = false
                isPlaying = false
                hasError = true
                shouldShowLogin = true
                status = error.localizedDescription
                logger.error(
                    "PLAYER",
                    "连接失败 errorType=\(String(describing: type(of: error))) error=\(error.localizedDescription)"
                )
            }
        }
        playbackTask = task
    }

    func playCamera(_ camera: AijiaCamera) {
        logger.info("PLAYER", "用户选择摄像头并准备播放 camera=\(DiagnosticsLogger.maskIdentifier(camera.macID))")
        cameraSelector = camera.macID
        selectedCameraID = camera.macID
        guard rememberLogin, !phone.isEmpty, !password.isEmpty else {
            start(allowCurrentCameraWhenNotRemembered: true)
            return
        }
        _ = credentialStore.save(phone: phone.trimmingCharacters(in: .whitespacesAndNewlines), password: password, cameraSelector: camera.macID)
        credentialStore.setAutoConnectEnabled(true)

        // If this camera is not pre-warmed yet, warm it now; start() will fall
        // back to openStream() if the warm-up has not finished in time.
        if prewarmCameraID != camera.macID {
            prewarm(for: camera)
        }
        start()
    }

    /// Pre-warms the live stream for the camera selection page.
    ///
    /// Mirrors the official player: while the user is deciding, wake the
    /// camera, resolve the live address and (once a camera is picked) hand
    /// the warmed stream to `start()` so the first frame appears quickly.
    func prewarm(for camera: AijiaCamera) {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhone.isEmpty, rememberLogin, !password.isEmpty else { return }
        guard prewarmCameraID != camera.macID else { return }

        prewarmTask?.cancel()
        prewarmCameraID = camera.macID
        prewarmedStream = nil
        logger.info("PLAYER", "预加载摄像头 camera=\(DiagnosticsLogger.maskIdentifier(camera.macID))")

        prewarmTask = Task { [weak self] in
            do {
                let client = self?.makeAPIClient(trimmedPhone, password, "")
                guard let client = client as? AijiaAPI else { return }
                let stream = try await client.prewarmStream()
                try Task.checkCancellation()
                guard let self = self else { return }
                guard self.prewarmCameraID == stream.camera.macID else { return }
                self.prewarmedStream = stream
                self.logger.info("PLAYER", "预加载完成 camera=\(DiagnosticsLogger.maskIdentifier(stream.camera.macID))")
            } catch {
                guard let self = self else { return }
                self.prewarmCameraID = ""
                self.logger.warning("PLAYER", "预加载失败 error=\(error.localizedDescription)")
            }
        }
    }

    /// Clears the pre-warm state (e.g. on logout or stop).
    private func clearPrewarm() {
        prewarmTask?.cancel()
        prewarmTask = nil
        prewarmedStream = nil
        prewarmCameraID = ""
    }

    func consumeCameraSelectionPrompt() {
        guard shouldPresentCameraSelection else { return }
        shouldPresentCameraSelection = false
        logger.info("UI", "已消费自动打开摄像头选择页请求")
    }

    private func cameraToPlay(from availableCameras: [AijiaCamera], selector: String) -> AijiaCamera? {
        guard !availableCameras.isEmpty else { return nil }
        let normalizedSelector = AijiaSigning.normalized(selector)
        guard !normalizedSelector.isEmpty else {
            logger.info("PLAYER", "未指定摄像头，等待用户从列表选择")
            return nil
        }
        return availableCameras.first { camera in
            [camera.macID, camera.name, camera.id]
                .map(AijiaSigning.normalized)
                .contains(normalizedSelector)
        }
    }

    func stop() {
        logger.info("PLAYER", "停止播放")
        shouldPlay = false
        reconnectInFlight = false
        clearPrewarm()
        _ = beginPlaybackOperation()
        cancelRecordingsQuery()
        finishReplayIfNeeded()
        isReplay = false
        resetReplayPlaybackState()
        resetCloudReplayState()
        stopPlaybackOnly()
        api = nil
        streamURL = nil
        cameraName = ""
        isLoading = false
        isPlaying = false
        isAuthenticated = false
        recordings = []
        cameras = []
        selectedCameraID = ""
        isLoadingRecordings = false
        shouldPresentCameraSelection = false
        status = "已停止"
        hasError = false
        if !hasSavedLogin {
            shouldShowLogin = true
        }
    }

    func logout() {
        logger.info("AUTH", "用户退出登录")
        stop()
        // Keep the existing fields and saved credentials so returning to the login
        // screen does not force the user to type the account again.
        credentialStore.setAutoConnectEnabled(false)
        didUserLogout = true
        isAuthenticated = false
        shouldShowLogin = true
        didAutoConnect = true
        status = "请确认账号后重新登录"
    }

    func prepareDiagnosticsExport() -> URL? {
        logger.info("DIAGNOSTICS", "用户请求导出诊断日志")
        do {
            return try logger.export()
        } catch {
            status = "导出日志失败：\(error.localizedDescription)"
            hasError = true
            logger.error("DIAGNOSTICS", "导出诊断日志失败 error=\(error.localizedDescription)")
            return nil
        }
    }

    func clearDiagnostics() {
        logger.info("DIAGNOSTICS", "用户清除诊断日志")
        logger.clear()
        status = "诊断日志已清除"
        hasError = false
    }

    func setHistoryVisible(_ visible: Bool) {
        guard isHistoryVisible != visible else { return }
        isHistoryVisible = visible
        logger.info("UI", visible ? "进入回放页" : "离开回放页")
    }

    func handleAppEnteredBackground() {
        guard shouldPlay, isAuthenticated else { return }
        didEnterBackgroundWhilePlaying = true
        hasError = false
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        if isReplay {
            replaySeekTask?.cancel()
            replaySeekTask = nil
            replaySeekGeneration &+= 1
            replayProgressTimer?.invalidate()
            replayProgressTimer = nil
            player?.pause()
            isPlaying = false
            replayBackgroundedAt = Date()
            status = "应用已进入后台，历史回放已暂停"
        } else {
            replayBackgroundedAt = nil
            status = "应用已进入后台，回前台会刷新实时画面"
        }
        logger.info(
            "PLAYER",
            isReplay ? "应用进入后台，暂停历史回放并保留进度" : "应用进入后台，实时播放将在回前台时刷新"
        )
    }

    func handleAppBecameActive() {
        guard didEnterBackgroundWhilePlaying else { return }
        didEnterBackgroundWhilePlaying = false

        guard shouldPlay, isAuthenticated else { return }
        if isReplay {
            logger.info("REPLAY", "应用回到前台，保留历史回放进度")
            status = "已回到前台，继续历史回放"
            shouldPlay = true
            resumeReplayAfterForeground()
            return
        }

        if isHistoryVisible {
            status = "已回到前台，停留在回放页不自动播放直播"
            logger.info("PLAYER", "回放页可见且未播放回放，跳过前台直播刷新")
            return
        }

        guard streamURL != nil else {
            status = "已回到前台，未启动实时画面"
            logger.info("PLAYER", "回到前台时没有实时流，跳过自动播放")
            return
        }

        refreshLiveAfterForeground()
    }

    func controlPTZ(_ direction: AijiaPTZDirection) {
        guard let client = api, isAuthenticated, !isReplay else {
            status = isReplay ? "历史回放时不能控制云台" : "请先连接摄像头"
            hasError = true
            return
        }

        logger.info("PTZ", "用户请求云台控制 direction=\(direction.rawValue)")
        status = "正在控制云台\(direction.title)…"
        hasError = false
        Task(priority: .userInitiated) { [weak self, client] in
            do {
                try await client.controlPTZ(direction: direction)
                guard let self = self, self.api === client else { return }
                self.status = "云台\(direction.title)控制成功"
                self.hasError = false
            } catch {
                guard let self = self, self.api === client else { return }
                self.status = "云台控制失败：\(error.localizedDescription)"
                self.hasError = true
                self.logger.error(
                    "PTZ",
                    "云台控制失败 direction=\(direction.rawValue) error=\(error.localizedDescription)"
                )
            }
        }
    }

    func captureSnapshot() {
        guard let player = player, !isReplay, !isRecording else {
            status = isReplay ? "历史回放时不能截图" : "当前没有可截图的直播画面"
            hasError = true
            return
        }
        // Wait briefly for the first decoded frame instead of failing when the
        // user taps right after connect (IJK returns -2 for thumbnail in that
        // window). The tap itself already gives the pipeline time to settle.
        status = "正在截图…"
        hasError = false
        let targetPlayer = player
        Task { @MainActor [weak self] in
            var image: UIImage?
            for _ in 0..<6 {
                if let frame = targetPlayer.thumbnailImageAtCurrentTime() {
                    image = frame
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard let self = self else { return }
            guard let image = image else {
                self.status = "截图失败，请重试"
                self.hasError = true
                self.logger.warning("MEDIA", "截图失败：无法获取当前帧")
                return
            }
            self.saveSnapshotImage(image)
        }
    }

    private func saveSnapshotImage(_ image: UIImage) {
        let destination = MediaLibrary.uniqueFileURL(
            in: MediaLibrary.capturesDirectory,
            baseName: "Live",
            ext: "png"
        )
        guard let data = image.pngData(),
              (try? data.write(to: destination)) != nil else {
            status = "截图保存失败"
            hasError = true
            logger.warning("MEDIA", "截图保存失败 file=\(destination.lastPathComponent)")
            return
        }

        status = "截图已保存到媒体库"
        hasError = false
        logger.info("MEDIA", "截图已保存 file=\(destination.lastPathComponent)")
        MediaLibrary.shared.reload()
    }

    func toggleRecording() {
        guard streamURL != nil, !isReplay else {
            status = isReplay ? "历史回放时不能录像" : "请先连接摄像头"
            hasError = true
            return
        }

        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard let player = player, !isRecording else { return }
        // Wait briefly for the first decoded frame: starting the C record
        // layer before frames arrive can leave the encoder without input.
        if !hasFirstFrame {
            status = "正在等待画面就绪…"
            logger.debug("MEDIA", "录像等待首帧解码")
        }
        let targetPlayer = player
        Task { @MainActor [weak self] in
            for _ in 0..<6 {
                if self?.hasFirstFrame == true {
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard let self = self, !self.isRecording else { return }
            guard self.hasFirstFrame else {
                self.status = "画面尚未就绪，请稍后再录像"
                self.hasError = true
                self.logger.warning("MEDIA", "录像被拦截：首帧尚未解码")
                return
            }
            self.beginRecording(on: targetPlayer)
        }
    }

    private func beginRecording(on player: IJKFFMoviePlayerController) {
        // IJK tees input packets to the file inside the demuxer thread;
        // playback continues without interruption. The C record layer collects
        // VPS/SPS/PPS from the stream and writes the mp4 header only after the
        // parameter sets are available, so the hvcC/avcC box is valid.
        let destination = MediaLibrary.uniqueFileURL(
            in: MediaLibrary.recordingsDirectory,
            baseName: "Live",
            ext: "mp4"
        )

        let result = player.startRecord(withPath: destination.path)
        guard result == 0 else {
            status = "录像启动失败（错误码 \(result)）"
            hasError = true
            logger.warning("MEDIA", "录像启动失败 result=\(result)")
            return
        }

        recordingFileURL = destination
        isRecording = true
        status = "正在录制直播画面…"
        hasError = false
        logger.info("MEDIA", "开始录像 file=\(destination.lastPathComponent)")

        // Verify that the file is actually being written shortly after start.
        // The mp4 header is written once the stream's VPS/SPS/PPS arrive
        // (typically within one GOP), so give it a couple of GOPs before
        // declaring the recording failed.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self = self,
                  self.isRecording,
                  self.recordingFileURL == destination else { return }
            guard Self.fileExistsAndHasData(destination) else {
                self.logger.warning("MEDIA", "录像未能启动，已取消录制 file=\(destination.lastPathComponent)")
                self.isRecording = false
                self.recordingFileURL = nil
                _ = self.player?.stopRecord()
                try? FileManager.default.removeItem(at: destination)
                self.status = "录像启动失败，请重试"
                self.hasError = true
                return
            }
            self.logger.debug("MEDIA", "录像文件已确认写入 file=\(destination.lastPathComponent)")
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        let fileURL = recordingFileURL
        recordingFileURL = nil
        isRecording = false

        let result = player?.stopRecord() ?? 0

        MediaLibrary.shared.reload()
        if result == 0, let fileURL = fileURL, Self.fileExistsAndHasData(fileURL) {
            status = "录像已保存到媒体库"
            logger.info("MEDIA", "录像已保存 file=\(fileURL.lastPathComponent)")
        } else {
            if let fileURL = fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            status = "录像保存失败，未生成有效文件"
            hasError = true
            logger.warning("MEDIA", "录像保存失败 result=\(result)")
        }
    }

    private static func fileExistsAndHasData(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    /// A stream refresh or reconnect tears down the player, so an in-progress
    /// recording can no longer be finalized. Discard the incomplete file.
    private func discardInterruptedRecording() {
        guard isRecording else { return }
        isRecording = false
        _ = player?.stopRecord()
        if let fileURL = recordingFileURL {
            try? FileManager.default.removeItem(at: fileURL)
            logger.warning("MEDIA", "录像中断，已删除未完成文件 file=\(fileURL.lastPathComponent)")
        }
        recordingFileURL = nil
        MediaLibrary.shared.reload()
    }

    func loadRecordings(for date: Date, force: Bool = false) {
        guard let client = api, isAuthenticated else {
            status = "请先连接摄像头"
            hasError = true
            return
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            status = "无法计算查询日期"
            hasError = true
            return
        }

        let queryKey = "\(ObjectIdentifier(client).hashValue):\(Int64(start.timeIntervalSince1970))"
        if !force {
            if isReplay {
                logger.debug("REPLAY", "回放期间忽略自动历史录像查询")
                return
            }

            if isLoadingRecordings, recordingsQueryKey == queryKey {
                logger.debug("REPLAY", "忽略重复的历史录像查询（请求仍在进行）")
                return
            }

            if recordingsQueryKey == queryKey,
               let completedAt = recordingsLastCompletedAt,
               Date().timeIntervalSince(completedAt) < 10 {
                logger.debug("REPLAY", "忽略重复的历史录像查询（刚刚已完成）")
                return
            }
        }

        recordingsTask?.cancel()
        recordingsTask = nil
        recordingsQueryGeneration &+= 1
        let queryGeneration = recordingsQueryGeneration
        recordingsQueryKey = queryKey
        recordingsLastCompletedAt = nil

        isLoadingRecordings = true
        hasError = false
        recordings = []
        status = "正在读取内存卡录像…"
        logger.info(
            "REPLAY",
            "用户查询历史录像 date=\(ISO8601DateFormatter().string(from: start))"
        )

        let task = Task { [weak self, client, queryGeneration] in
            do {
                let items = try await client.queryRecordings(
                    startTime: Int64(start.timeIntervalSince1970),
                    endTime: Int64(end.timeIntervalSince1970)
                )
                guard let self = self,
                      self.api === client,
                      self.recordingsQueryGeneration == queryGeneration else { return }
                self.recordings = items
                self.recordingsLastCompletedAt = Date()
                self.recordingsTask = nil
                self.isLoadingRecordings = false
                self.hasError = false
                self.status = items.isEmpty ? "这一天没有找到内存卡录像" : "找到 \(items.count) 段录像"
            } catch {
                guard let self = self,
                      self.api === client,
                      self.recordingsQueryGeneration == queryGeneration else { return }
                self.isLoadingRecordings = false
                self.recordingsLastCompletedAt = Date()
                self.recordingsTask = nil
                self.hasError = true
                self.status = "读取历史录像失败：\(error.localizedDescription)"
                self.logger.error("REPLAY", "历史录像查询失败 error=\(error.localizedDescription)")
            }
        }
        recordingsTask = task
    }

    func playRecording(_ recording: AijiaRecording) {
        guard let client = api, isAuthenticated else {
            status = "请先连接摄像头"
            hasError = true
            return
        }

        let replacingReplay = isReplay
        let operationID = beginPlaybackOperation()
        resetReplayPlaybackState()
        replayDurationSecond = max(0, recording.endTime - recording.startTime)
        stopPlaybackOnly()
        streamURL = nil
        isReplay = true
        isLoading = true
        isPlaying = false
        hasError = false
        shouldPlay = true
        replayRecording = recording
        let playbackStartTime = recording.playbackStartTime
        status = "正在打开历史录像…"
        logger.info(
            "REPLAY",
            "用户打开历史录像 start=\(recording.startTime) end=\(recording.endTime)"
        )

        logger.info("REPLAY", "按官方实现从录像区间起点打开 playbackStart=\(playbackStartTime)")

        let task = Task(priority: .userInitiated) { [weak self, client, replacingReplay, recording, playbackStartTime, operationID] in
            if replacingReplay {
                do {
                    try Task.checkCancellation()
                    try await client.stopReplay()
                    try Task.checkCancellation()
                } catch is CancellationError {
                    self?.logger.debug("REPLAY", "切换历史录像前的停止请求已取消")
                    return
                } catch {
                    self?.logger.warning("REPLAY", "切换历史录像前停止旧回放失败 error=\(error.localizedDescription)")
                }
                guard let self = self,
                      self.isCurrentPlaybackOperation(operationID),
                      self.api === client,
                      self.isReplay else { return }
            }

            do {
                try Task.checkCancellation()
                let url = try await client.playRecording(at: playbackStartTime)
                try Task.checkCancellation()
                guard let self = self,
                      self.isCurrentPlaybackOperation(operationID),
                      self.api === client,
                      self.isReplay else { return }
                self.replayRecording = recording
                self.replayPlaybackStartTime = playbackStartTime
                self.replayCurrentSecond = max(0, playbackStartTime - recording.startTime)
                self.replayPosition = recording.endTime > recording.startTime
                    ? Float(Double(self.replayCurrentSecond) / Double(recording.endTime - recording.startTime))
                    : 0
                self.streamURL = url
                self.isLoading = false
                self.isPlaying = true
                self.hasError = false
                self.status = "正在播放内存卡录像"
                self.logger.info("REPLAY", "历史录像打开成功 playbackStart=\(playbackStartTime)")
                self.preparePlayerIfPossible()
                self.scheduleKeepAlive()
            } catch is CancellationError {
                self?.logger.debug("REPLAY", "打开历史录像请求已取消")
            } catch {
                guard let self = self,
                      self.isCurrentPlaybackOperation(operationID),
                      self.api === client,
                      self.isReplay else { return }
                self.isLoading = false
                self.isPlaying = false
                self.isReplay = false
                self.resetReplayPlaybackState()
                self.hasError = true
                self.status = "打开历史录像失败：\(error.localizedDescription)"
                self.logger.error("REPLAY", "打开历史录像失败 error=\(error.localizedDescription)")
            }
        }
        playbackTask = task
    }

    func stopReplay() {
        guard isReplay else { return }
        logger.info("REPLAY", "用户停止历史录像")
        let client = api
        let operationID = beginPlaybackOperation()
        stopPlaybackOnly()
        streamURL = nil
        isReplay = false
        isLoading = false
        isPlaying = false
        hasError = false
        resetReplayPlaybackState()

        guard shouldPlay, isAuthenticated, let client = client else {
            status = "历史录像已停止"
            return
        }

        isLoading = true
        status = "正在恢复实时画面…"
        logger.info("PLAYER", "历史回放结束，立即恢复实时流")

        let task = Task(priority: .userInitiated) { [weak self, client] in
            guard let self = self else { return }

            do {
                try await client.stopReplay()
            } catch {
                self.logger.warning("REPLAY", "停止历史录像请求失败，继续恢复实时流 error=\(error.localizedDescription)")
            }

            guard self.isCurrentPlaybackOperation(operationID), self.shouldPlay else { return }

            do {
                let stream = try await client.openStream()
                guard self.isCurrentPlaybackOperation(operationID),
                      self.shouldPlay,
                      self.api === client,
                      !self.isReplay else { return }
                self.cameraName = stream.camera.name
                self.streamURL = stream.url
                self.isLoading = false
                self.isPlaying = true
                self.hasError = false
                self.status = "已回到实时流，正在本机播放"
                self.logger.info("PLAYER", "历史回放后实时流恢复成功 url=\(DiagnosticsLogger.redactedURL(stream.url))")
                self.preparePlayerIfPossible()
                self.scheduleKeepAlive()
            } catch {
                guard self.isCurrentPlaybackOperation(operationID),
                      self.shouldPlay,
                      self.api === client,
                      !self.isReplay else { return }
                self.isLoading = false
                self.isPlaying = false
                self.hasError = true
                self.status = "恢复实时画面失败：\(error.localizedDescription)"
                self.logger.error("PLAYER", "历史回放后恢复实时流失败 error=\(error.localizedDescription)")
            }
        }
        playbackTask = task
    }

    // MARK: - 云回放(云端录像)

    /// Loads the days (epoch seconds, local midnight) that have cloud
    /// recordings in the last month.
    func loadCloudDays() {
        guard let client = api, isAuthenticated else {
            status = "请先连接摄像头"
            hasError = true
            return
        }
        guard !isLoadingCloud else { return }

        isLoadingCloud = true
        let now = Date()
        let startTime = Int64(now.timeIntervalSince1970 * 1000) - 30 * 86_400 * 1000
        let endTime = Int64(now.timeIntervalSince1970 * 1000)
        logger.info("CLOUD", "读取云录像日历 range=\(startTime)-\(endTime)")

        let task = Task { [weak self, client] in
            do {
                let days = try await client.cloudCalendar(startTime: startTime, endTime: endTime)
                guard let self = self, self.api === client else { return }
                self.cloudDays = days
                self.isLoadingCloud = false
                self.status = days.isEmpty ? "云端没有录像" : "云端有录像的天数：\(days.count)"
                self.logger.info("CLOUD", "云录像日历读取成功 days=\(days)")
            } catch {
                guard let self = self, self.api === client else { return }
                self.isLoadingCloud = false
                self.hasError = true
                self.status = "读取云录像日历失败：\(error.localizedDescription)"
                self.logger.error("CLOUD", "云录像日历读取失败 error=\(error.localizedDescription)")
            }
        }
        playbackTask = task
    }

    /// Opens a cloud session for the selected day and merges its TS segments
    /// into contiguous clips.
    func loadCloudSegments(for day: Int64) {
        guard let client = api, isAuthenticated else {
            status = "请先连接摄像头"
            hasError = true
            return
        }
        guard cloudSelectedDay != day || cloudSegments.isEmpty else { return }

        cloudSelectedDay = day
        cloudClips = []
        cloudSegments = []
        isLoadingCloud = true
        hasError = false
        let dayStartMS = day * 1000
        let dayEndMS = dayStartMS + 86_399_999
        logger.info("CLOUD", "读取云录像分段 day=\(day)")

        let task = Task { [weak self, client, day] in
            do {
                let session = try await client.createCloudPlayback(
                    startTime: dayStartMS,
                    endTime: dayEndMS
                )
                let segments = try await client.cloudPlaylist(url: session.playlistURL)
                let clips = Self.cloudClips(from: segments)
                guard let self = self,
                      self.api === client,
                      self.cloudSelectedDay == day else { return }
                self.cloudSegments = segments
                self.cloudClips = clips
                self.isLoadingCloud = false
                self.status = clips.isEmpty ? "这一天没有云录像" : "找到 \(clips.count) 段云录像"
                self.logger.info("CLOUD", "云录像分段解析成功 day=\(day) segments=\(segments.count) clips=\(clips.count)")
            } catch {
                guard let self = self,
                      self.api === client,
                      self.cloudSelectedDay == day else { return }
                self.isLoadingCloud = false
                self.hasError = true
                self.status = "读取云录像失败：\(error.localizedDescription)"
                self.logger.error("CLOUD", "云录像读取失败 error=\(error.localizedDescription)")
            }
        }
        playbackTask = task
    }

    /// Plays one cloud clip through the IJK player. A dedicated playback
    /// session is opened for the clip window, so the returned m3u8 only
    /// contains that clip's segments and no seeking is needed.
    func playCloudClip(_ clip: AijiaCloudClip) {
        guard let client = api, isAuthenticated else {
            status = "请先连接摄像头"
            hasError = true
            return
        }

        let operationID = beginPlaybackOperation()
        stopPlaybackOnly()
        streamURL = nil
        isReplay = false
        isCloudReplay = true
        isLoading = true
        isPlaying = false
        hasError = false
        shouldPlay = true
        status = "正在打开云回放…"
        logger.info("CLOUD", "播放云录像 clip=\(clip.startTime)-\(clip.endTime)")

        let task = Task(priority: .userInitiated) { [weak self, client, clip, operationID] in
            do {
                try Task.checkCancellation()
                let session = try await client.createCloudPlayback(
                    startTime: clip.startTime,
                    endTime: clip.endTime
                )
                try Task.checkCancellation()
                guard let self = self,
                      self.isCurrentPlaybackOperation(operationID),
                      self.api === client,
                      self.isCloudReplay else { return }
                self.streamURL = session.playlistURL
                self.isLoading = false
                self.isPlaying = true
                self.hasError = false
                self.status = "正在播放云录像"
                self.logger.info("CLOUD", "云回放打开成功 url=\(DiagnosticsLogger.redactedURL(session.playlistURL))")
                self.preparePlayerIfPossible()
            } catch is CancellationError {
                self?.logger.debug("CLOUD", "打开云回放请求已取消")
            } catch {
                guard let self = self,
                      self.isCurrentPlaybackOperation(operationID),
                      self.api === client,
                      self.isCloudReplay else { return }
                self.isLoading = false
                self.isPlaying = false
                self.isCloudReplay = false
                self.hasError = true
                self.status = "打开云回放失败：\(error.localizedDescription)"
                self.logger.error("CLOUD", "打开云回放失败 error=\(error.localizedDescription)")
            }
        }
        playbackTask = task
    }

    func stopCloudReplay() {
        guard isCloudReplay else { return }
        logger.info("CLOUD", "用户停止云回放")
        _ = beginPlaybackOperation()
        stopPlaybackOnly()
        streamURL = nil
        isCloudReplay = false
        isLoading = false
        isPlaying = false
        hasError = false
        status = "云回放已停止"
    }

    func seekReplay(to position: Double) {
        guard isReplay, let client = api, isAuthenticated, let recording = replayRecording else {
            logger.warning("REPLAY", "拖动进度被忽略：当前没有可用的历史录像会话")
            return
        }

        let clampedPosition = max(0.0, min(1.0, position))
        let timestamp = recording.playbackTimestamp(for: clampedPosition)
        replayPosition = Float(clampedPosition)
        replayCurrentSecond = max(0, min(replayDurationSecond, timestamp - recording.startTime))
        replaySeekTask?.cancel()
        replaySeekGeneration &+= 1
        let seekGeneration = replaySeekGeneration
        let operationID = playbackOperationID
        isLoading = true
        isPlaying = false
        hasError = false
        replayProgressTimer?.invalidate()
        replayProgressTimer = nil
        player?.pause()
        status = "正在跳转历史录像…"
        logger.info(
            "REPLAY",
            "用户拖动回放进度 position=\(String(format: "%.4f", clampedPosition)) timestamp=\(timestamp)"
        )

        replaySeekTask = Task(priority: .userInitiated) { [weak self, client, operationID, seekGeneration] in
            do {
                try await client.seekRecording(at: timestamp)
                // Let the server-side transfer settle before restarting the player.
                // Reopening immediately can attach to an empty response and
                // leave the replay view black.
                try await Task.sleep(nanoseconds: 500_000_000)
                guard let self = self,
                      self.api === client,
                      self.isReplay,
                      self.isCurrentPlaybackOperation(operationID),
                      self.replaySeekGeneration == seekGeneration,
                      !Task.isCancelled else { return }
                self.replayPlaybackStartTime = timestamp
                self.restartReplayPlayer()
                self.isLoading = false
                self.isPlaying = true
                self.hasError = false
                self.status = "正在播放内存卡录像"
                self.logger.info("REPLAY", "历史录像跳转成功 timestamp=\(timestamp)")
            } catch is CancellationError {
                self?.logger.debug("REPLAY", "历史录像跳转请求已取消")
            } catch {
                guard let self = self,
                      self.api === client,
                      self.isReplay,
                      self.isCurrentPlaybackOperation(operationID),
                      self.replaySeekGeneration == seekGeneration else { return }
                let committedTimestamp = self.replayPlaybackStartTime ?? recording.playbackStartTime
                let committedSecond = max(0, min(self.replayDurationSecond, committedTimestamp - recording.startTime))
                self.replayCurrentSecond = committedSecond
                self.replayPosition = self.replayDurationSecond > 0
                    ? Float(Double(committedSecond) / Double(self.replayDurationSecond))
                    : 0
                self.player?.play()
                self.scheduleReplayProgressTimer()
                self.isLoading = false
                self.isPlaying = true
                self.hasError = true
                self.status = "历史录像跳转失败：\(error.localizedDescription)"
                self.logger.error("REPLAY", "历史录像跳转失败 timestamp=\(timestamp) error=\(error.localizedDescription)")
            }
        }
    }

    private func restartReplayPlayer() {
        guard isReplay, let streamURL = streamURL else { return }
        replayProgressTimer?.invalidate()
        replayProgressTimer = nil
        logger.debug("REPLAY", "服务器回放定位成功，重启播放器恢复播放")
        // Stop first (fast) before the heavier shutdown; shutdown can block
        // on the demux thread while it is still reading the old stream.
        player?.stop()
        tearDownPlayer()
        // Force SwiftUI to rebuild the surface host so the new player view is
        // freshly attached instead of inheriting a stale render layer.
        playerViewID = UUID()
        preparePlayerIfPossible()
        scheduleReplayProgressTimer()
    }

    func mountPlayerSurface(in hostView: UIView, role: IJKPlayerSurfaceRole) {
        switch role {
        case .inline:
            inlineSurfaceHost = hostView
        case .fullscreen:
            fullscreenSurfaceHost = hostView
        }
        activatePreferredPlayerSurface()
    }

    func layoutPlayerSurface(in hostView: UIView) {
        guard activeSurfaceHost === hostView else { return }
        let targetBounds = hostView.bounds
        guard targetBounds.width > 1, targetBounds.height > 1 else { return }

        if let playerView = player?.view, playerView.superview === hostView,
           playerView.frame != targetBounds {
            UIView.performWithoutAnimation {
                playerView.frame = targetBounds
                playerView.layoutIfNeeded()
            }
        }
    }

    func unmountPlayerSurface(from hostView: UIView, role: IJKPlayerSurfaceRole) {
        switch role {
        case .inline:
            if inlineSurfaceHost === hostView {
                inlineSurfaceHost = nil
            }
        case .fullscreen:
            if fullscreenSurfaceHost === hostView {
                fullscreenSurfaceHost = nil
            }
        }
        activatePreferredPlayerSurface()
    }

    func refreshPlayerView() {
        playerViewID = UUID()
    }

    private func activatePreferredPlayerSurface() {
        guard let hostView = fullscreenSurfaceHost ?? inlineSurfaceHost else {
            if activeSurfaceHost != nil {
                activeSurfaceHost = nil
                logger.debug("PLAYER", "播放器输出面已从宿主移除，播放会话保持运行")
            }
            return
        }

        let hostChanged = activeSurfaceHost !== hostView
        activeSurfaceHost = hostView
        if hostChanged {
            attachPlayerView(to: hostView)
            logger.debug("PLAYER", "播放器输出面已挂载到新宿主")
        }

        layoutPlayerSurface(in: hostView)
        if player == nil {
            preparePlayerIfPossible()
        }
    }

    private func attachPlayerView(to hostView: UIView) {
        guard let playerView = player?.view else { return }
        if playerView.superview !== hostView {
            playerView.removeFromSuperview()
            playerView.frame = hostView.bounds
            playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hostView.insertSubview(playerView, at: 0)
        }
    }

    private func tearDownPlayer() {
        hasFirstFrame = false
        firstFrameProbeTask?.cancel()
        firstFrameProbeTask = nil
        _ = player?.stopRecord()
        player?.shutdown()
        player = nil
    }

    private func preparePlayerIfPossible() {
        guard shouldPlay, let streamURL = streamURL, activeSurfaceHost != nil else { return }

        if let player = player {
            if isReplay {
                scheduleReplayProgressTimer()
            }
            return
        }

        // Mirrors the official ijkplayer configuration: hardware decode plus
        // live-stream friendly buffering (small probe/buffer for fast first
        // frame, keep-alive tolerant). These keys were extracted from the
        // official binary (HYAF3DMixPlayer options).
        guard let options = IJKFFOptions.byDefault() else {
            status = "播放器初始化失败"
            hasError = true
            logger.error("PLAYER", "IJK 播放器初始化失败（无法创建选项）")
            return
        }
        if isCloudReplay {
            // HLS cloud playback: give the playlist/segment fetches a bigger
            // buffer and disable the infinite live buffering mode.
            options.setPlayerOptionIntValue(2000, forKey: "network-caching")
            options.setPlayerOptionIntValue(0, forKey: "infbuf")
        } else {
            options.setPlayerOptionIntValue(300, forKey: "network-caching")
            options.setPlayerOptionIntValue(1, forKey: "infbuf")
        }
        options.setPlayerOptionIntValue(1, forKey: "packet-buffering")
        options.setPlayerOptionIntValue(0, forKey: "flush_packets")
        options.setPlayerOptionIntValue(1000, forKey: "analyzemaxduration")
        options.setPlayerOptionIntValue(1024, forKey: "probesize")
        guard let player = IJKFFMoviePlayerController(contentURL: streamURL, with: options) else {
            status = "播放器初始化失败"
            hasError = true
            logger.error("PLAYER", "IJK 播放器初始化失败 url=\(DiagnosticsLogger.redactedURL(streamURL))")
            return
        }
        player.shouldAutoplay = true
        player.scalingMode = .aspectFit
        self.player = player
        lastLoggedPlayerState = ""
        lastLoggedPlaybackSecond = -10
        logger.info("PLAYER", "开始本机解码 url=\(DiagnosticsLogger.redactedURL(streamURL))")
        if let host = activeSurfaceHost {
            attachPlayerView(to: host)
        }
        // If the player reports playing before the first playback-state
        // notification arrives, treat it as first-frame-ready right away.
        if player.isPlaying() {
            markFirstFrameReady()
        }
        // Live streams with infbuf may never set playbackState/.playing or a
        // loadState Playable bit even though frames are being rendered. Poll
        // for an actual decodable frame as the authoritative signal.
        startFirstFrameProbe(for: player)
        player.prepareToPlay()
        player.play()
        scheduleNetworkSpeedTimer()
        if isReplay {
            scheduleReplayProgressTimer()
        }
    }

    private func scheduleReplayProgressTimer() {
        replayProgressTimer?.invalidate()
        replayProgressTimer = nil
        guard isReplay else { return }

        replayProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            self.updateReplayProgress(from: player)
        }
    }

    private func updateReplayProgress(from currentPlayer: IJKFFMoviePlayerController) {
        guard isReplay,
              !isLoading,
              currentPlayer === player,
              let recording = replayRecording,
              let playbackStartTime = replayPlaybackStartTime else { return }

        let currentMilliseconds = max(0, Int64(currentPlayer.currentPlaybackTime * 1_000))
        let absoluteSecond = playbackStartTime + currentMilliseconds / 1_000
        let relativeSecond = max(0, min(replayDurationSecond, absoluteSecond - recording.startTime))
        if replayCurrentSecond != relativeSecond {
            replayCurrentSecond = relativeSecond
        }
        if replayDurationSecond > 0 {
            let position = Float(Double(relativeSecond) / Double(replayDurationSecond))
            if abs(replayPosition - position) > 0.0005 {
                replayPosition = position
            }
        }
    }

    private func scheduleNetworkSpeedTimer() {
        networkSpeedTimer?.invalidate()
        lastNetworkReceivedBytes = currentNetworkReceivedBytes()
        lastNetworkSpeedSampleDate = Date()
        networkSpeedText = "测速中"
        logger.debug("PLAYER", "已启动 1 秒实时网速采样定时器")
        networkSpeedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateNetworkSpeedText()
            }
        }
    }

    private func updateNetworkSpeedText() {
        guard let receivedBytes = currentNetworkReceivedBytes() else {
            if networkSpeedText != "-- KB/s" {
                networkSpeedText = "-- KB/s"
                logger.warning("PLAYER", "实时网速采样不可用")
            }
            return
        }

        let now = Date()
        guard let previousBytes = lastNetworkReceivedBytes,
              let previousDate = lastNetworkSpeedSampleDate else {
            lastNetworkReceivedBytes = receivedBytes
            lastNetworkSpeedSampleDate = now
            logger.debug("PLAYER", "实时网速采样基线已初始化 bytes=\(receivedBytes)")
            return
        }

        let elapsed = max(now.timeIntervalSince(previousDate), 0.1)
        let deltaBytes = receivedBytes >= previousBytes ? receivedBytes - previousBytes : 0
        let kbps = Double(deltaBytes) / elapsed / 1024.0
        let speedText = kbps >= 1024
            ? String(format: "%.1f MB/s", kbps / 1024)
            : String(format: "%.0f KB/s", kbps)

        lastNetworkReceivedBytes = receivedBytes
        lastNetworkSpeedSampleDate = now
        if networkSpeedText != speedText {
            networkSpeedText = speedText
            logger.debug("PLAYER", "实时拉流网速 speed=\(speedText)")
        }
    }

    private func currentNetworkReceivedBytes() -> UInt64? {
        #if canImport(Darwin)
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            logger.warning("PLAYER", "读取网络接口失败")
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var totalBytes: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }

            let flags = Int32(interface.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP,
                  let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.pointee.ifa_data else {
                continue
            }

            let interfaceData = data.assumingMemoryBound(to: if_data.self).pointee
            totalBytes &+= UInt64(interfaceData.ifi_ibytes)
        }
        return totalBytes
        #else
        logger.warning("PLAYER", "当前平台不支持实时网速采样")
        return nil
        #endif
    }

    private func scheduleKeepAlive() {
        keepAliveTimer?.invalidate()
        logger.debug("PLAYER", "已启动 20 秒保活定时器")
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.runKeepAlive()
        }
    }

    private func runKeepAlive() {
        guard shouldPlay, let client = api else { return }
        let replay = isReplay

        Task { [weak self, client, replay] in
            do {
                if replay {
                    try await client.keepReplayAlive()
                } else {
                    try await client.keepAlive()
                }
            } catch {
                guard let self = self, self.shouldPlay, self.api === client else { return }
                if replay {
                    self.logger.warning("REPLAY", "历史录像保活失败 error=\(error.localizedDescription)")
                    self.status = "历史录像保活失败，请重新打开"
                    self.hasError = true
                } else {
                    self.logger.warning("PLAYER", "保活请求失败 error=\(error.localizedDescription)")
                    await reconnect(client: client)
                }
            }
        }
    }

    private func reconnect(client: AijiaAPIClient) async {
        guard !reconnectInFlight else { return }
        reconnectInFlight = true
        logger.warning("PLAYER", "保活失败，开始重连")
        status = "保活失败，正在重新连接…"
        hasError = false

        do {
            let stream = try await client.openStream()
            guard shouldPlay, api === client else {
                reconnectInFlight = false
                return
            }
            streamURL = stream.url
            cameraName = stream.camera.name
            isReplay = false
            isPlaying = true
            status = "已重连，正在本机解码"
            hasError = false
            logger.info("PLAYER", "重连成功 url=\(DiagnosticsLogger.redactedURL(stream.url))")
            discardInterruptedRecording()
            tearDownPlayer()
            preparePlayerIfPossible()
        } catch {
            guard shouldPlay, api === client else {
                reconnectInFlight = false
                return
            }
            status = "重连失败：\(error.localizedDescription)"
            hasError = true
            logger.error("PLAYER", "重连失败 error=\(error.localizedDescription)")
        }
        reconnectInFlight = false
    }

    private func refreshLiveAfterForeground() {
        guard !foregroundRefreshInFlight, let client = api else { return }
        let operationID = beginPlaybackOperation()
        foregroundRefreshInFlight = true
        logger.info("PLAYER", "应用回到前台，释放旧实时流并刷新地址")
        stopPlaybackOnly()
        streamURL = nil
        isPlaying = false
        isLoading = true
        hasError = false
        status = "正在刷新实时画面…"

        let task = Task(priority: .userInitiated) { [weak self, client, operationID] in
            defer {
                self?.foregroundRefreshInFlight = false
            }
            do {
                let stream = try await client.openStream()
                guard let self = self,
                      self.isCurrentPlaybackOperation(operationID),
                      self.shouldPlay,
                      self.api === client,
                      !self.isReplay else {
                    return
                }
                self.cameraName = stream.camera.name
                self.streamURL = stream.url
                self.isLoading = false
                self.isPlaying = true
                self.hasError = false
                self.status = "已回到前台，正在本机播放"
                self.logger.info("PLAYER", "回前台刷新实时流成功 url=\(DiagnosticsLogger.redactedURL(stream.url))")
                self.discardInterruptedRecording()
                self.preparePlayerIfPossible()
                self.scheduleKeepAlive()
            } catch {
                guard let self = self,
                      self.isCurrentPlaybackOperation(operationID),
                      self.shouldPlay,
                      self.api === client else {
                    return
                }
                self.isLoading = false
                self.isPlaying = false
                self.hasError = true
                self.status = "回前台刷新失败：\(error.localizedDescription)"
                self.logger.error("PLAYER", "回前台刷新实时流失败 error=\(error.localizedDescription)")
            }
        }
        playbackTask = task
    }

    private func resumeReplayAfterForeground() {
        let backgroundedAt = replayBackgroundedAt
        replayBackgroundedAt = nil
        guard isReplay, streamURL != nil else { return }

        if let backgroundedAt = backgroundedAt,
           Date().timeIntervalSince(backgroundedAt) < Self.replayRefreshAfterBackgroundThreshold {
            if let player = player {
                if let host = activeSurfaceHost {
                    attachPlayerView(to: host)
                }
                player.play()
                isPlaying = true
                hasError = false
                scheduleReplayProgressTimer()
            } else if activeSurfaceHost != nil {
                preparePlayerIfPossible()
                isPlaying = player != nil
            } else {
                // SwiftUI may detach the representable while the app is backgrounded.
                // Force a fresh host so mountPlayerSurface(in:role:) can resume output.
                playerViewID = UUID()
                isPlaying = false
                logger.debug("REPLAY", "回到前台时播放器视图已卸载，等待重新挂载")
            }

            scheduleKeepAlive()
            logger.info("REPLAY", "回到前台后恢复历史回放播放器")
            return
        }

        refreshReplaySessionAfterBackground()
    }

    private func refreshReplaySessionAfterBackground() {
        guard isReplay, let recording = replayRecording, let client = api else { return }

        replaySeekTask?.cancel()
        replaySeekTask = nil
        replaySeekGeneration &+= 1
        let operationID = playbackOperationID
        let resumeTimestamp = currentReplayAbsoluteSecond()
        logger.info("REPLAY", "回放切后台超过阈值，重新建立回放会话 timestamp=\(resumeTimestamp)")
        status = "正在恢复历史回放…"
        isLoading = true
        isPlaying = false
        hasError = false
        replayProgressTimer?.invalidate()
        replayProgressTimer = nil
        player?.pause()

        let task = Task(priority: .userInitiated) { [weak self, client, operationID, resumeTimestamp] in
            guard let self = self else { return }

            do {
                try? await client.stopReplay()
                try Task.checkCancellation()
                let url = try await client.playRecording(at: resumeTimestamp)
                try Task.checkCancellation()
                guard self.isCurrentPlaybackOperation(operationID),
                      self.isReplay,
                      self.api === client else { return }

                self.streamURL = url
                self.replayPlaybackStartTime = resumeTimestamp
                self.replayCurrentSecond = max(0, min(self.replayDurationSecond, resumeTimestamp - recording.startTime))
                self.replayPosition = self.replayDurationSecond > 0
                    ? Float(Double(self.replayCurrentSecond) / Double(self.replayDurationSecond))
                    : 0
                self.stopPlaybackOnly()
                self.playerViewID = UUID()
                self.preparePlayerIfPossible()
                self.isLoading = false
                self.isPlaying = self.player != nil
                self.hasError = false
                self.status = "正在播放内存卡录像"
                self.logger.info("REPLAY", "重新建立历史回放会话成功 url=\(DiagnosticsLogger.redactedURL(url))")
                self.scheduleKeepAlive()
            } catch is CancellationError {
                self.logger.debug("REPLAY", "恢复历史回放请求已取消")
            } catch {
                guard self.isCurrentPlaybackOperation(operationID),
                      self.isReplay else { return }
                self.isLoading = false
                self.hasError = true
                self.status = "恢复历史回放失败：\(error.localizedDescription)"
                self.logger.error("REPLAY", "恢复历史回放失败 error=\(error.localizedDescription)")
            }
        }
        playbackTask = task
    }

    private func currentReplayAbsoluteSecond() -> Int64 {
        guard let recording = replayRecording else { return 0 }
        let lowerBound = recording.playbackStartTime
        let upperBound = max(lowerBound, recording.endTime - 1)
        let relativeSecond: Int64
        if let player = player, player.isPlaying() {
            let milliseconds = max(0, Int64(player.currentPlaybackTime * 1_000))
            let absolute = (replayPlaybackStartTime ?? recording.playbackStartTime) + milliseconds / 1_000
            relativeSecond = max(0, min(replayDurationSecond, absolute - recording.startTime))
        } else {
            relativeSecond = max(0, min(replayDurationSecond, replayCurrentSecond))
        }
        let absolute = recording.startTime + relativeSecond
        return min(max(absolute, lowerBound), upperBound)
    }

    private func stopPlaybackOnly() {
        discardInterruptedRecording()
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        networkSpeedTimer?.invalidate()
        networkSpeedTimer = nil
        lastNetworkReceivedBytes = nil
        lastNetworkSpeedSampleDate = nil
        networkSpeedText = "-- KB/s"
        replayProgressTimer?.invalidate()
        replayProgressTimer = nil
        if player != nil {
            logger.debug("PLAYER", "释放播放器实例")
        }
        tearDownPlayer()
    }

    private func resetReplayPlaybackState() {
        replaySeekTask?.cancel()
        replaySeekTask = nil
        replayBackgroundedAt = nil
        replayProgressTimer?.invalidate()
        replayProgressTimer = nil
        replayRecording = nil
        replayPlaybackStartTime = nil
        replayPosition = 0
        replayCurrentSecond = 0
        replayDurationSecond = 0
    }

    private func resetCloudReplayState() {
        cloudDays = []
        cloudSegments = []
        cloudClips = []
        cloudSelectedDay = 0
        isLoadingCloud = false
        isCloudReplay = false
    }

    /// Merges adjacent cloud TS segments into contiguous clips. A gap larger
    /// than 15 seconds starts a new clip.
    private static func cloudClips(from segments: [AijiaCloudSegment]) -> [AijiaCloudClip] {
        var clips: [AijiaCloudClip] = []
        var currentStart: Int64?
        var currentEnd: Int64 = 0

        for segment in segments {
            guard let epoch = cloudSegmentStartTime(segment) else { continue }
            let startMS = epoch * 1000
            let endMS = startMS + Int64(segment.duration * 1000)

            if let start = currentStart, startMS - currentEnd <= 15_000 {
                currentEnd = max(currentEnd, endMS)
            } else {
                if let start = currentStart {
                    clips.append(AijiaCloudClip(startTime: start, endTime: currentEnd))
                }
                currentStart = startMS
                currentEnd = endMS
            }
        }
        if let start = currentStart {
            clips.append(AijiaCloudClip(startTime: start, endTime: currentEnd))
        }
        return clips
    }

    /// Extracts the segment start epoch (seconds) from its URL path:
    /// https://playback01-.../playback/{macId}/{epoch}.ts
    private static func cloudSegmentStartTime(_ segment: AijiaCloudSegment) -> Int64? {
        guard let fileName = segment.url.pathComponents.last else { return nil }
        let epochText = fileName.replacingOccurrences(of: ".ts", with: "")
        guard let epoch = Int64(epochText) else { return nil }
        return epoch
    }

    private func cancelRecordingsQuery() {
        recordingsTask?.cancel()
        recordingsTask = nil
        recordingsQueryGeneration &+= 1
        recordingsQueryKey = nil
        recordingsLastCompletedAt = nil
        isLoadingRecordings = false
    }

    private func beginPlaybackOperation() -> Int {
        playbackTask?.cancel()
        playbackTask = nil
        replayCleanupTask?.cancel()
        replayCleanupTask = nil
        replaySeekTask?.cancel()
        replaySeekTask = nil
        replaySeekGeneration &+= 1
        playbackOperationID &+= 1
        playerViewID = UUID()
        return playbackOperationID
    }

    private func isCurrentPlaybackOperation(_ operationID: Int) -> Bool {
        operationID == playbackOperationID
    }

    private func finishReplayIfNeeded() {
        guard isReplay, let client = api else { return }
        replayCleanupTask?.cancel()
        replayCleanupTask = Task { [weak self, client] in
            do {
                try await client.stopReplay()
            } catch {
                self?.logger.warning("REPLAY", "停止历史录像请求失败 error=\(error.localizedDescription)")
            }
        }
    }

    private func handlePlaybackStateChanged(_ notification: Notification) {
        guard let currentPlayer = notification.object as? IJKFFMoviePlayerController,
              currentPlayer === player else { return }

        let stateText = String(currentPlayer.playbackState.rawValue)
        if stateText != lastLoggedPlayerState {
            lastLoggedPlayerState = stateText
            logger.info("PLAYER", "IJK 状态变化 state=\(stateText)")
        }

        switch currentPlayer.playbackState {
        case .playing:
            isPlaying = true
            hasError = false
            markFirstFrameReady()
            if isReplay {
                scheduleReplayProgressTimer()
            }
            logger.info("PLAYER", "IJK 已开始输出视频")
        case .paused:
            logger.info("PLAYER", "IJK 已暂停")
        case .stopped:
            if shouldPlay {
                isPlaying = false
            }
            logger.info("PLAYER", "IJK 已停止")
        default:
            break
        }
    }

    private func handlePlaybackFinished(_ notification: Notification) {
        guard let currentPlayer = notification.object as? IJKFFMoviePlayerController,
              currentPlayer === player else { return }

        let reason = (notification.userInfo?[IJKMPMoviePlayerPlaybackDidFinishReasonUserInfoKey] as? NSNumber)?.intValue
        let userInfoText = notification.userInfo?.map { "\($0.key)=\($0.value)" }.joined(separator: " ") ?? "<none>"
        logger.info("PLAYER", "IJK 播放结束 reason=\(reason ?? -1) info=\(userInfoText)")

        if reason == IJKMPMovieFinishReason.playbackError.rawValue {
            isPlaying = false
            hasError = true
            status = isCloudReplay ? "云回放播放错误" : "播放器报告错误，正在重试…"
            logger.error("PLAYER", "IJK 播放错误 info=\(userInfoText)")
            if isCloudReplay {
                isCloudReplay = false
            } else {
                scheduleRetryPlay()
            }
        } else if reason == IJKMPMovieFinishReason.playbackEnded.rawValue, isCloudReplay {
            isPlaying = false
            status = "云回放已结束"
            logger.info("CLOUD", "云回放播放到结尾")
        }
    }

    /// Auto-retries playback after a transient player error, mirroring the
    /// official tryToReplayTimerAction behaviour. Bound to one retry so a
    /// persistent failure surfaces to the user instead of looping forever.
    private func scheduleRetryPlay() {
        guard shouldPlay, !isReplay, !isCloudReplay else { return }
        guard !reconnectInFlight else { return }
        reconnectInFlight = true
        logger.info("PLAYER", "安排播放自动重试")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self = self else { return }
            self.reconnectInFlight = false
            guard self.shouldPlay, self.api != nil, !self.isReplay else { return }
            self.logger.info("PLAYER", "播放自动重试中")
            self.start(allowCurrentCameraWhenNotRemembered: true)
        }
    }

    private func handleLoadStateChanged(_ notification: Notification) {
        guard let currentPlayer = notification.object as? IJKFFMoviePlayerController,
              currentPlayer === player else { return }
        let rawState = currentPlayer.loadState.rawValue
        logger.info("PLAYER", "IJK 加载状态变化 loadState=\(rawState)")

        // Playable/PlaythroughOK means the demuxer/decode pipeline has data
        // ready to render. Live streams with infbuf may stay in a state that
        // does not surface these bits, so this is only an auxiliary signal;
        // the authoritative first-frame signals are naturalSize notification
        // and the thumbnail probe.
        let frameReady = rawState & (IJKMPMovieLoadState.playable.rawValue | IJKMPMovieLoadState.playthroughOK.rawValue) != 0
        if frameReady {
            markFirstFrameReady()
        }
    }

    /// Fired by IJK once the video dimensions are known, i.e. the first frame
    /// has been decoded. This is the most direct "first frame ready" signal.
    private func handleNaturalSizeAvailable(_ notification: Notification) {
        guard let currentPlayer = notification.object as? IJKFFMoviePlayerController,
              currentPlayer === player else { return }
        let size = currentPlayer.naturalSize
        logger.info("PLAYER", "IJK 视频尺寸就绪 size=\(size.width)x\(size.height)")
        if size.width > 0, size.height > 0 {
            markFirstFrameReady()
        }
    }

    /// Records that the live player has decoded its first frame. Screenshots
    /// and recordings are gated on this: right after a connection the media
    /// pipeline may not have produced a frame yet, and IJK returns an error
    /// (-2) for snapshot/record in that window.
    private func markFirstFrameReady() {
        guard !hasFirstFrame else { return }
        hasFirstFrame = true
        firstFrameProbeTask?.cancel()
        firstFrameProbeTask = nil
        logger.info("MEDIA", "首帧已就绪，允许截图与录像")
    }

    /// Polls the player for an actual decodable frame. Live streams with
    /// infbuf may keep playbackState/loadState away from the "ready" bits even
    /// while rendering, so the only reliable signal is whether IJK can return
    /// a thumbnail (the exact operation snapshot uses). Stops once ready or
    /// after a generous timeout so a dead stream still releases the probe.
    private func startFirstFrameProbe(for player: IJKFFMoviePlayerController) {
        firstFrameProbeTask?.cancel()
        firstFrameProbeTask = Task { @MainActor [weak self] in
            var attempts = 0
            while attempts < 30 {
                guard let self = self else { return }
                guard self.player === player else { return }
                if self.hasFirstFrame { return }
                // thumbnailImageAtCurrentTime is a synchronous decode; only
                // probe while the pipeline looks active to avoid busy work.
                if player.thumbnailImageAtCurrentTime() != nil {
                    self.markFirstFrameReady()
                    return
                }
                attempts += 1
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            self?.logger.warning("MEDIA", "首帧探测超时，未获得可解码帧")
        }
    }
}
