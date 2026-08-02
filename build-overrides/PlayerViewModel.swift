import Combine
import Foundation
import MobileVLCKit
import UIKit

@MainActor
final class PlayerViewModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    @Published var phone = ""
    @Published var password = ""
    @Published var loginMethod: AijiaLoginMethod = .password
    @Published var verificationCode = ""
    @Published var cameraSelector = ""
    @Published var rememberLogin = true
    @Published private(set) var status = "请输入移动爱家账号"
    @Published private(set) var cameraName = ""
    @Published private(set) var streamURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var isSendingVerificationCode = false
    @Published private(set) var verificationCountdown = 0
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
    @Published private(set) var replayRate: Float = 1.0
    @Published private(set) var recordings: [AijiaRecording] = []
    @Published private(set) var isLoadingRecordings = false
    @Published private(set) var playerViewID = UUID()

    private var api: AijiaAPI?
    private var player: VLCMediaPlayer?
    private var replayPlaybackStartTime: Int64?
    private var replaySeekTask: Task<Void, Never>?
    private var replaySeekGeneration = 0
    private var replayProgressTimer: Timer?
    private var replayRateVerificationTask: Task<Void, Never>?
    private var replayRateVerificationGeneration = 0
    private var recordingsTask: Task<Void, Never>?
    private var recordingsQueryGeneration = 0
    private var recordingsQueryKey: String?
    private var recordingsLastCompletedAt: Date?
    private var playbackTask: Task<Void, Never>?
    private var verificationRequestTask: Task<Void, Never>?
    private var verificationCountdownTask: Task<Void, Never>?
    private var replayCleanupTask: Task<Void, Never>?
    private var playbackOperationID = 0
    private weak var drawable: UIView?
    private var keepAliveTimer: Timer?
    private var shouldPlay = false
    private var reconnectInFlight = false
    private var foregroundRefreshInFlight = false
    private var didEnterBackgroundWhilePlaying = false
    private var didUserLogout = false
    private var didAutoConnect = false
    private var lastLoggedPlayerState = ""
    private var lastLoggedPlaybackSecond = -10
    private let logger = DiagnosticsLogger.shared
    private let credentialStore = CredentialStore.shared

    override init() {
        super.init()
        if let savedLogin = credentialStore.load() {
            let autoConnectEnabled = credentialStore.isAutoConnectEnabled()
            phone = savedLogin.phone
            password = savedLogin.password
            cameraSelector = savedLogin.cameraSelector
            hasSavedLogin = true
            shouldShowLogin = !autoConnectEnabled
            didUserLogout = !autoConnectEnabled
            status = autoConnectEnabled ? "已恢复保存的登录信息" : "登录信息已保存，请手动登录"
            logger.info(
                "AUTH",
                "已从钥匙串恢复登录信息 account=\(DiagnosticsLogger.maskPhone(phone)) autoConnect=\(autoConnectEnabled)"
            )
        } else {
            logger.info("AUTH", "未找到保存的登录信息")
        }
    }

    func autoConnectIfSaved() {
        guard hasSavedLogin, !didAutoConnect, !didUserLogout, !password.isEmpty else { return }
        didAutoConnect = true
        logger.info("AUTH", "启动后自动连接")
        start()
    }

    func requestVerificationCode() {
        guard loginMethod == .smsCode else { return }

        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhone.isEmpty else {
            status = "请先填写手机号"
            hasError = true
            return
        }
        guard !isSendingVerificationCode, verificationCountdown == 0 else { return }

        verificationRequestTask?.cancel()
        let selectedCamera = cameraSelector
        let client = AijiaAPI(phone: trimmedPhone, cameraSelector: selectedCamera)
        isSendingVerificationCode = true
        hasError = false
        status = "正在发送验证码…"
        logger.info("AUTH", "用户请求短信验证码 account=\(DiagnosticsLogger.maskPhone(trimmedPhone))")

        let task = Task(priority: .userInitiated) { [weak self, client] in
            do {
                try await client.requestVerificationCode()
                guard let self = self else { return }
                self.verificationRequestTask = nil
                self.isSendingVerificationCode = false
                self.verificationCountdown = 60
                self.startVerificationCountdown()
                self.status = "验证码已发送，请查收短信"
                self.hasError = false
            } catch {
                guard let self = self else { return }
                self.verificationRequestTask = nil
                self.isSendingVerificationCode = false
                self.hasError = true
                self.status = "获取验证码失败：\(error.localizedDescription)"
                self.logger.error("AUTH", "获取短信验证码失败 error=\(error.localizedDescription)")
            }
        }
        verificationRequestTask = task
    }

    private func startVerificationCountdown() {
        verificationCountdownTask?.cancel()
        verificationCountdownTask = Task { [weak self] in
            while let self = self, self.verificationCountdown > 0 {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self.verificationCountdown = max(0, self.verificationCountdown - 1)
            }
            self?.verificationCountdownTask = nil
        }
    }

    func start() {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVerificationCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let credentialIsMissing: Bool
        switch loginMethod {
        case .password:
            credentialIsMissing = password.isEmpty
        case .smsCode:
            credentialIsMissing = trimmedVerificationCode.isEmpty
        }
        guard !trimmedPhone.isEmpty, !credentialIsMissing else {
            status = loginMethod == .password ? "请填写手机号和密码" : "请填写手机号和短信验证码"
            hasError = true
            logger.warning("AUTH", "登录被阻止，账号或登录凭据为空 method=\(loginMethod.rawValue)")
            return
        }

        logger.info("PLAYER", "用户发起连接 account=\(DiagnosticsLogger.maskPhone(trimmedPhone))")
        didUserLogout = false
        let operationID = beginPlaybackOperation()
        cancelRecordingsQuery()
        finishReplayIfNeeded()
        isReplay = false
        resetReplayPlaybackState()
        stopPlaybackOnly()
        let loginPassword = password
        let loginCode = trimmedVerificationCode
        let selectedLoginMethod = loginMethod
        let selectedCamera = cameraSelector
        let shouldRememberLogin = rememberLogin
        let client: AijiaAPI
        switch selectedLoginMethod {
        case .password:
            client = AijiaAPI(
                phone: trimmedPhone,
                password: loginPassword,
                cameraSelector: selectedCamera
            )
        case .smsCode:
            client = AijiaAPI(
                phone: trimmedPhone,
                verificationCode: loginCode,
                cameraSelector: selectedCamera
            )
        }
        api = client
        shouldShowLogin = false
        shouldPlay = true
        isLoading = true
        isPlaying = false
        hasError = false
        cameraName = ""
        streamURL = nil
        status = "正在登录并获取实时地址…"

        let task = Task(priority: .userInitiated) { [weak self, client, operationID] in
            do {
                let stream = try await client.openStream()
                guard let self = self,
                      self.isCurrentPlaybackOperation(operationID),
                      self.shouldPlay,
                      self.api === client else { return }
                cameraName = stream.camera.name
                streamURL = stream.url
                isLoading = false
                isPlaying = true
                status = "已连接，正在本机解码"
                hasError = false
                isAuthenticated = true
                shouldShowLogin = false

                if selectedLoginMethod == .password {
                    if shouldRememberLogin {
                        if credentialStore.save(
                            phone: trimmedPhone,
                            password: loginPassword,
                            cameraSelector: selectedCamera
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
                } else {
                    // Never persist the one-time SMS code. Existing password
                    // credentials, if any, are left untouched.
                    verificationCode = ""
                    verificationCountdownTask?.cancel()
                    verificationCountdownTask = nil
                    verificationCountdown = 0
                    logger.info("AUTH", "验证码登录成功，未保存短信验证码")
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

    func stop() {
        logger.info("PLAYER", "停止播放")
        verificationRequestTask?.cancel()
        verificationRequestTask = nil
        verificationCountdownTask?.cancel()
        verificationCountdownTask = nil
        isSendingVerificationCode = false
        verificationCountdown = 0
        shouldPlay = false
        reconnectInFlight = false
        _ = beginPlaybackOperation()
        cancelRecordingsQuery()
        finishReplayIfNeeded()
        isReplay = false
        resetReplayPlaybackState()
        stopPlaybackOnly()
        api = nil
        streamURL = nil
        cameraName = ""
        isLoading = false
        isPlaying = false
        isAuthenticated = false
        recordings = []
        isLoadingRecordings = false
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

    func handleAppEnteredBackground() {
        guard shouldPlay, isAuthenticated else { return }
        didEnterBackgroundWhilePlaying = true
        hasError = false
        if isReplay {
            cancelReplayRateVerification()
            replayProgressTimer?.invalidate()
            replayProgressTimer = nil
            player?.pause()
            isPlaying = false
            status = "应用已进入后台，历史回放已暂停"
        } else {
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
            resumeReplayAfterForeground()
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
            if isLoadingRecordings, recordingsQueryKey == queryKey {
                logger.debug("REPLAY", "忽略重复的历史录像查询（请求仍在进行）")
                return
            }

            if recordingsQueryKey == queryKey,
               let completedAt = recordingsLastCompletedAt,
               Date().timeIntervalSince(completedAt) < 3 {
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
                // Let the server-side transfer settle before rebuilding VLC.
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
        cancelReplayRateVerification()
        replayProgressTimer?.invalidate()
        replayProgressTimer = nil
        logger.debug("REPLAY", "服务器回放定位成功，复用播放器恢复播放")
        if let player = player {
            player.delegate = nil
            player.stop()
            if let drawable = drawable {
                player.drawable = drawable
            }
            player.media = VLCMedia(url: streamURL)
            player.delegate = self
            player.play()
            applyReplayRate(to: player)
            scheduleReplayProgressTimer()
        } else {
            preparePlayerIfPossible()
        }
    }

    func setReplayRate(_ rate: Float) {
        guard isReplay else { return }
        let clampedRate = min(max(rate, 0.5), 5.0)
        cancelReplayRateVerification()
        replayRate = clampedRate
        if let player = player {
            applyReplayRate(to: player)
        } else {
            logger.debug("REPLAY", "播放器尚未创建，待开始输出时应用回放倍速 rate=\(String(format: "%.1f", clampedRate))")
        }
        status = "正在播放内存卡录像"
        logger.info("REPLAY", "用户调整回放倍速 rate=\(String(format: "%.1f", clampedRate))")
    }

    private func applyReplayRate(to player: VLCMediaPlayer) {
        guard isReplay else { return }

        let requestedRate = replayRate
        player.rate = requestedRate
        logger.debug(
            "REPLAY",
            "应用回放倍速 requested=\(String(format: "%.1f", requestedRate)) " +
                "playerRate=\(String(format: "%.1f", player.rate)) " +
                "playing=\(player.isPlaying) seekable=\(player.isSeekable) hasVideoOut=\(player.hasVideoOut)"
        )

        guard player.isPlaying, abs(requestedRate - 1.0) > 0.01 else { return }
        scheduleReplayRateVerification(for: player)
    }

    private func scheduleReplayRateVerification(for player: VLCMediaPlayer) {
        replayRateVerificationTask?.cancel()
        replayRateVerificationTask = nil
        guard isReplay, player.isPlaying, abs(replayRate - 1.0) > 0.01 else { return }

        replayRateVerificationGeneration &+= 1
        let verificationID = replayRateVerificationGeneration
        let operationID = playbackOperationID
        let requestedRate = replayRate
        let baselineMilliseconds = max(0, Int64(player.time.intValue))
        let baselineDate = Date()

        replayRateVerificationTask = Task { [weak self, weak player, operationID, verificationID, requestedRate, baselineMilliseconds, baselineDate] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }

            guard let self = self,
                  let player = player,
                  self.isReplay,
                  self.player === player,
                  self.isCurrentPlaybackOperation(operationID),
                  self.replayRateVerificationGeneration == verificationID,
                  abs(self.replayRate - requestedRate) < 0.01,
                  player.isPlaying,
                  !Task.isCancelled else {
                return
            }

            let elapsed = max(Date().timeIntervalSince(baselineDate), 0.1)
            let deltaMilliseconds = max(0, Int64(player.time.intValue) - baselineMilliseconds)
            guard deltaMilliseconds >= 250 else {
                self.logger.warning(
                    "REPLAY",
                    "倍速验证没有足够的时间进度 requested=\(String(format: "%.1f", requestedRate)) " +
                        "playerRate=\(String(format: "%.1f", player.rate)) " +
                        "seekable=\(player.isSeekable) hasVideoOut=\(player.hasVideoOut)"
                )
                self.replayRateVerificationTask = nil
                return
            }

            let observedRate = Double(deltaMilliseconds) / 1_000.0 / elapsed
            let tolerance = max(0.35, Double(requestedRate) * 0.30)
            self.logger.debug(
                "REPLAY",
                "倍速验证 requested=\(String(format: "%.1f", requestedRate)) " +
                    "observed=\(String(format: "%.2f", observedRate)) " +
                    "playerRate=\(String(format: "%.1f", player.rate)) " +
                    "seekable=\(player.isSeekable) hasVideoOut=\(player.hasVideoOut)"
            )

            if abs(observedRate - Double(requestedRate)) > tolerance {
                player.rate = 1.0
                self.replayRate = 1.0
                self.status = "当前回放流不支持该倍速，已回退到 1x"
                self.logger.warning(
                    "REPLAY",
                    "回放流未按请求倍速播放，已回退到 1x requested=\(String(format: "%.1f", requestedRate)) " +
                        "observed=\(String(format: "%.2f", observedRate))"
                )
            }
            self.replayRateVerificationTask = nil
        }
    }

    private func cancelReplayRateVerification() {
        replayRateVerificationTask?.cancel()
        replayRateVerificationTask = nil
        replayRateVerificationGeneration &+= 1
    }

    func attach(to view: UIView) {
        let viewChanged = drawable !== view
        if viewChanged {
            logger.debug("PLAYER", "播放器视图已挂载")
        }
        drawable = view
        guard viewChanged || player == nil else { return }
        player?.drawable = view
        preparePlayerIfPossible()
    }

    func detach(from view: UIView) {
        guard drawable === view else { return }
        logger.debug("PLAYER", "播放器视图已卸载")
        drawable = nil
        cancelReplayRateVerification()
        replayProgressTimer?.invalidate()
        replayProgressTimer = nil
        player?.delegate = nil
        player?.stop()
        player = nil
    }

    private func preparePlayerIfPossible() {
        guard shouldPlay, let streamURL = streamURL, let drawable = drawable else { return }

        if let player = player {
            player.drawable = drawable
            if isReplay {
                applyReplayRate(to: player)
                scheduleReplayProgressTimer()
            }
            return
        }

        let player = VLCMediaPlayer()
        player.delegate = self
        player.drawable = drawable
        player.media = VLCMedia(url: streamURL)
        self.player = player
        lastLoggedPlayerState = ""
        lastLoggedPlaybackSecond = -10
        logger.info("PLAYER", "开始本机解码 url=\(DiagnosticsLogger.redactedURL(streamURL))")
        player.play()
        if isReplay {
            applyReplayRate(to: player)
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

    private func updateReplayProgress(from currentPlayer: VLCMediaPlayer) {
        guard isReplay,
              !isLoading,
              currentPlayer === player,
              let recording = replayRecording,
              let playbackStartTime = replayPlaybackStartTime else { return }

        let currentMilliseconds = max(0, Int64(currentPlayer.time.intValue))
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

    private func reconnect(client: AijiaAPI) async {
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
            player?.delegate = nil
            player?.stop()
            player = nil
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
        guard isReplay, streamURL != nil else { return }

        if let player = player, let drawable = drawable {
            player.drawable = drawable
            player.play()
            applyReplayRate(to: player)
            isPlaying = true
            hasError = false
            scheduleReplayProgressTimer()
        } else if drawable != nil {
            preparePlayerIfPossible()
            isPlaying = player != nil
        } else {
            // SwiftUI may detach the representable while the app is backgrounded.
            // Force a fresh view so attach(to:) can create a player with a valid drawable.
            playerViewID = UUID()
            isPlaying = false
            logger.debug("REPLAY", "回到前台时播放器视图已卸载，等待重新挂载")
        }

        scheduleKeepAlive()
        logger.info("REPLAY", "回到前台后恢复历史回放播放器")
    }

    private func stopPlaybackOnly() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        cancelReplayRateVerification()
        replayProgressTimer?.invalidate()
        replayProgressTimer = nil
        if player != nil {
            logger.debug("PLAYER", "释放播放器实例")
        }
        player?.delegate = nil
        player?.stop()
        player = nil
    }

    private func resetReplayPlaybackState() {
        cancelReplayRateVerification()
        replaySeekTask?.cancel()
        replaySeekTask = nil
        replayProgressTimer?.invalidate()
        replayProgressTimer = nil
        replayRecording = nil
        replayPlaybackStartTime = nil
        replayPosition = 0
        replayCurrentSecond = 0
        replayDurationSecond = 0
        replayRate = 1.0
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
        cancelReplayRateVerification()
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

    func mediaPlayerStateChanged(_ aNotification: Notification!) {
        guard let currentPlayer = aNotification?.object as? VLCMediaPlayer,
              let activePlayer = player,
              currentPlayer === activePlayer else {
            return
        }

        let state = String(describing: currentPlayer.state)
        guard state != lastLoggedPlayerState else { return }
        lastLoggedPlayerState = state
        logger.info("PLAYER", "VLC 状态变化 state=\(state)")
        if state.lowercased().contains("error") {
            hasError = true
            isPlaying = false
            status = "播放器报告错误"
            logger.error("PLAYER", "VLC 报告播放错误 state=\(state)")
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification!) {
        guard let currentPlayer = aNotification?.object as? VLCMediaPlayer,
              let activePlayer = player,
              currentPlayer === activePlayer else {
            return
        }

        if isReplay {
            updateReplayProgress(from: currentPlayer)
        }

        let second = Int(currentPlayer.time.intValue) / 1_000
        guard second >= 0, second - lastLoggedPlaybackSecond >= 10 else { return }
        lastLoggedPlaybackSecond = second
        logger.debug("PLAYER", "VLC 播放进度 timeSec=\(second)")
    }

    func mediaPlayerPlaying(_ aNotification: Notification!) {
        guard let currentPlayer = aNotification?.object as? VLCMediaPlayer,
              let activePlayer = player,
              currentPlayer === activePlayer else {
            return
        }
        isPlaying = true
        hasError = false
        if isReplay {
            applyReplayRate(to: currentPlayer)
            scheduleReplayProgressTimer()
        }
        logger.info("PLAYER", "VLC 已开始输出视频")
    }

    func mediaPlayerPaused(_ aNotification: Notification!) {
        guard let currentPlayer = aNotification?.object as? VLCMediaPlayer,
              let activePlayer = player,
              currentPlayer === activePlayer else {
            return
        }
        logger.info("PLAYER", "VLC 已暂停")
    }

    func mediaPlayerStopped(_ aNotification: Notification!) {
        guard let currentPlayer = aNotification?.object as? VLCMediaPlayer,
              let activePlayer = player,
              currentPlayer === activePlayer else {
            return
        }
        isPlaying = false
        logger.info("PLAYER", "VLC 已停止")
    }

    func mediaPlayerEncounteredError(_ aNotification: Notification!) {
        guard let currentPlayer = aNotification?.object as? VLCMediaPlayer,
              let activePlayer = player,
              currentPlayer === activePlayer else {
            return
        }
        isPlaying = false
        hasError = true
        status = "播放器报告错误"
        logger.error("PLAYER", "VLC encountered error")
    }
}
