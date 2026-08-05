import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var model: PlayerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingCameraSelection = false

    var body: some View {
        Group {
            if model.shouldShowLogin || (!model.hasSavedLogin && !model.isAuthenticated) {
                LoginView(model: model)
            } else {
                PlayerScreen(model: model)
            }
        }
        .onAppear {
            model.autoConnectIfSaved()
            presentCameraSelectionIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                model.handleAppEnteredBackground()
            case .active:
                model.handleAppBecameActive()
            default:
                break
            }
        }
        .onChange(of: model.shouldPresentCameraSelection) { _ in
            presentCameraSelectionIfNeeded()
        }
        .sheet(isPresented: $showingCameraSelection) {
            NavigationView {
                CameraSelectionPage(model: model)
            }
        }
    }

    private func presentCameraSelectionIfNeeded() {
        guard model.shouldPresentCameraSelection, !showingCameraSelection else { return }
        DiagnosticsLogger.shared.info("UI", "收到自动打开摄像头选择页请求，正在弹出选择页")
        model.consumeCameraSelectionPrompt()
        showingCameraSelection = true
    }
}

private struct LoginView: View {
    @ObservedObject var model: PlayerViewModel
    @FocusState private var focusedField: Field?

    private var passwordBinding: Binding<String> {
        Binding(
            get: { model.password },
            set: { newValue in
                if newValue.isEmpty, !model.password.isEmpty {
                    model.password.removeLast()
                } else {
                    model.password = newValue
                }
            }
        )
    }

    private enum Field: Hashable {
        case phone
        case password
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("爱家直连")
                            .font(.largeTitle.weight(.bold))
                        Text("登录后直接查看摄像头，视频在本机解码。")
                            .foregroundStyle(.secondary)
                    }

                    GroupBox {
                        VStack(spacing: 14) {
                            TextField("移动手机号", text: $model.phone)
                                .textContentType(.telephoneNumber)
                                .keyboardType(.phonePad)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .phone)

                            SecureField("移动爱家密码", text: passwordBinding)
                                .textContentType(.password)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .password)

                            Toggle("记住登录信息", isOn: $model.rememberLogin)
                                .font(.subheadline)

                            Button {
                                focusedField = nil
                                model.start()
                            } label: {
                                HStack {
                                    if model.isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(model.isLoading ? "正在登录…" : "登录并播放")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                model.isLoading ||
                                model.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                model.password.isEmpty
                            )
                        }
                    }

                    if !model.status.isEmpty {
                        StatusText(model: model)
                    }

                    Text("密码只保存在本机钥匙串，不会上传到其他服务器。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: DiagnosticsView(model: model)) {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel("诊断日志")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: AboutView()) {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("关于")
                }
                ToolbarItem(placement: .keyboard) {
                    Button("完成") {
                        focusedField = nil
                    }
                }
            }
        }
    }
}

private struct CameraSelectionPage: View {
    @ObservedObject var model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if model.cameras.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("暂无摄像头")
                            .font(.headline)
                        Text("请先登录并读取账号下的摄像头。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(model.cameras) { camera in
                        Button {
                            DiagnosticsLogger.shared.info(
                                "UI",
                                "用户在独立摄像头选择页选择设备 camera=\(DiagnosticsLogger.maskIdentifier(camera.macID))"
                            )
                            model.playCamera(camera)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(camera.name)
                                        .font(.headline)
                                    Text(camera.macID)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.selectedCameraID == camera.macID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("请选择要播放的摄像头")
            }
        }
        .navigationTitle("选择摄像头")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("返回") {
                    DiagnosticsLogger.shared.info("UI", "用户从独立摄像头选择页返回播放页")
                    dismiss()
                }
            }
        }
        .onAppear {
            DiagnosticsLogger.shared.info("UI", "显示独立摄像头选择页 count=\(model.cameras.count)")
        }
    }
}


private struct CameraSelectionMenuButton: View {
    @ObservedObject var model: PlayerViewModel
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            DiagnosticsLogger.shared.info("UI", "用户从更多操作打开独立摄像头选择页")
            isPresented = true
        } label: {
            Label("选择摄像头", systemImage: "video.badge.plus")
        }
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section("项目介绍") {
                Text("爱家直连是一款第三方 iOS 客户端，直接登录移动爱家云端，读取账号下摄像头并在 iPhone 本机解码播放实时与内存卡回放视频。")
            }
            Section("版本") {
                HStack {
                    Text("当前版本")
                    Spacer()
                    Text("\(AppVersionInfo.display) (\(AppVersionInfo.build))")
                        .foregroundStyle(.secondary)
                }
            }
            Section("仓库地址") {
                Link("github.com/fucknima/yidongaijia", destination: URL(string: "https://github.com/fucknima/yidongaijia")!)
            }
            Section("作者") {
                Text("fucknima")
                Text("99715422@qq.com")
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            DiagnosticsLogger.shared.info("UI", "显示关于页面")
        }
    }
}

private struct PlayerScreen: View {
    @ObservedObject var model: PlayerViewModel
    @State private var showingHistory = false
    @State private var showingDiagnostics = false
    @State private var showingFullscreen = false
    @State private var showingAbout = false
    @State private var showingCameraSelection = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.cameraName.isEmpty ? "我的摄像头" : model.cameraName)
                                .font(.title2.weight(.semibold))
                            Text(model.isLoading ? "正在连接云端…" : "移动爱家摄像头")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle()
                            .fill(model.hasError ? Color.red : (model.isLoading ? Color.orange : Color.green))
                            .frame(width: 10, height: 10)
                    }

                    // SwiftUI may replace this host during presentation, but
                    // the model keeps one persistent VLC drawable throughout.
                    if model.streamURL != nil, !model.isReplay {
                        PlayerSurface(model: model) {
                            showingFullscreen = true
                        }

                        Button(role: .destructive) {
                            model.stop()
                        } label: {
                            Label(model.isReplay ? "停止回放" : "停止播放", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: model.hasError ? "wifi.exclamationmark" : "video")
                                .font(.system(size: 42))
                                .foregroundStyle(model.hasError ? .red : .secondary)
                            Text(model.isLoading ? "正在获取视频地址" : "暂时没有播放画面")
                                .foregroundStyle(.secondary)

                            if !model.isLoading {
                                Button("重新连接") {
                                    model.start()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 64)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    StatusText(model: model)

                    if model.isAuthenticated {
                        PTZControlPanel(model: model)

                        NavigationLink(
                            destination: HistoryView(model: model),
                            isActive: $showingHistory
                        ) {
                            Label("内存卡回放", systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("播放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingDiagnostics = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel("诊断日志")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Text("版本 \(AppVersionInfo.display)")
                        CameraSelectionMenuButton(
                            model: model,
                            isPresented: $showingCameraSelection
                        )
                        Button {
                            DiagnosticsLogger.shared.info("UI", "用户打开关于页面")
                            showingAbout = true
                        } label: {
                            Label("关于", systemImage: "info.circle")
                        }
                        Button(role: .destructive) {
                            model.logout()
                        } label: {
                            Label("退出并返回登录", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多操作")
                }
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            NavigationView {
                DiagnosticsView(model: model)
            }
        }
        .sheet(isPresented: $showingAbout) {
            NavigationView {
                AboutView()
            }
        }
        .sheet(isPresented: $showingCameraSelection) {
            NavigationView {
                CameraSelectionPage(model: model)
            }
        }
        .fullScreenCover(isPresented: $showingFullscreen, onDismiss: {
            ScreenOrientation.restorePortrait()
        }) {
            FullscreenPlayerView(model: model)
        }
    }
}

private struct PlayerSurface: View {
    @ObservedObject var model: PlayerViewModel
    let onFullscreen: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VLCPlayerView(model: model)
                .id(model.playerViewID)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Text(model.networkSpeedText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.clear)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Button(action: onFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .frame(width: 68, height: 68)
            .contentShape(Rectangle())
            .accessibilityLabel("横屏全屏")
            .padding(4)
        }
    }
}

private struct FullscreenPlayerView: View {
    @ObservedObject var model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            VLCPlayerView(model: model, role: .fullscreen)
                .id(model.playerViewID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea()

            Text(model.networkSpeedText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.clear)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if model.isReplay {
                VStack {
                    Spacer()
                    ReplayControls(model: model, presentation: .fullscreen)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(2)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .frame(width: 72, height: 72)
            .contentShape(Rectangle())
            .accessibilityLabel("退出全屏")
            .padding(4)
        }
        .statusBar(hidden: true)
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.async {
                ScreenOrientation.lockLandscape()
            }
        }
    }
}

private enum ScreenOrientation {
    static func lockLandscape() {
        request(.landscape, deviceOrientation: .landscapeRight)
    }

    static func restorePortrait() {
        request(.portrait, deviceOrientation: .portrait)
    }

    private static func request(
        _ interfaceOrientations: UIInterfaceOrientationMask,
        deviceOrientation: UIInterfaceOrientation
    ) {
        AijiaDirectAppDelegate.supportedOrientations = interfaceOrientations
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return
        }

        if #available(iOS 16.0, *) {
            scene.windows.first(where: { $0.isKeyWindow })?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: interfaceOrientations)) { error in
                DiagnosticsLogger.shared.warning(
                    "UI",
                    "屏幕方向切换失败 orientation=\(interfaceOrientations) error=\(error.localizedDescription)"
                )
            }
        } else {
            UIDevice.current.setValue(deviceOrientation.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

private struct StatusText: View {
    @ObservedObject var model: PlayerViewModel

    var body: some View {
        Text(model.status)
            .font(.footnote)
            .foregroundStyle(model.hasError ? .red : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum AppVersionInfo {
    static var display: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
    }
}

private enum ReplayControlsPresentation: Equatable {
    case inline
    case fullscreen
}

private struct ReplayControls: View {
    @ObservedObject var model: PlayerViewModel
    let presentation: ReplayControlsPresentation
    @State private var sliderValue = 0.0
    @State private var isEditing = false

    private let rates: [Float] = [0.5, 1.0, 2.0, 3.0, 5.0]

    init(
        model: PlayerViewModel,
        presentation: ReplayControlsPresentation = .inline
    ) {
        self.model = model
        self.presentation = presentation
    }

    var body: some View {
        Group {
            if presentation == .fullscreen {
                controlsContent
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 10)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                GroupBox {
                    controlsContent
                }
            }
        }
        .onAppear {
            sliderValue = Double(model.replayPosition)
        }
        .onChange(of: model.replayPosition) { value in
            if !isEditing {
                sliderValue = Double(value)
            }
        }
    }

    private var displaySecond: Int64 {
        isEditing ? previewSecond : model.replayCurrentSecond
    }

    private var previewSecond: Int64 {
        guard model.replayDurationSecond > 0 else { return 0 }
        return max(0, min(model.replayDurationSecond, Int64((Double(model.replayDurationSecond) * sliderValue).rounded())))
    }

    private var controlsContent: some View {
        VStack(spacing: presentation == .fullscreen ? 6 : 8) {
            HStack {
                Text(formatTime(displaySecond))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(secondaryForegroundColor)
                Spacer()
                Text(formatTime(model.replayDurationSecond))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(secondaryForegroundColor)
            }

            Slider(
                value: $sliderValue,
                in: 0...1,
                onEditingChanged: { editing in
                    isEditing = editing
                    if editing {
                        sliderValue = Double(model.replayPosition)
                    } else {
                        model.seekReplay(to: sliderValue)
                    }
                }
            )
            .disabled(model.isLoading || model.replayDurationSecond <= 0)

            HStack {
                Label("内存卡回放", systemImage: "play.rectangle")
                    .font(.subheadline)
                Spacer()
                Menu {
                    ForEach(rates, id: \.self) { rate in
                        Button {
                            model.setReplayRate(rate)
                        } label: {
                            if abs(model.replayRate - rate) < 0.01 {
                                Label(rateLabel(rate), systemImage: "checkmark")
                            } else {
                                Text(rateLabel(rate))
                            }
                        }
                    }
                } label: {
                    Label(rateLabel(model.replayRate), systemImage: "speedometer")
                }
                .disabled(model.isLoading)
            }
        }
    }

    private var secondaryForegroundColor: Color {
        presentation == .fullscreen ? .white.opacity(0.78) : .secondary
    }

    private func formatTime(_ seconds: Int64) -> String {
        guard seconds >= 0 else { return "00:00" }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%02lld:%02lld:%02lld", hours, minutes, remainingSeconds)
        }
        return String(format: "%02lld:%02lld", minutes, remainingSeconds)
    }

    private func rateLabel(_ rate: Float) -> String {
        if abs(rate.rounded() - rate) < 0.01 {
            return String(format: "%.0fx", rate)
        }
        return String(format: "%.1fx", rate)
    }
}

private struct PTZControlPanel: View {
    @ObservedObject var model: PlayerViewModel

    private var isDisabled: Bool {
        model.isReplay || model.isLoading || !model.isAuthenticated
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 10) {
                Text("云台控制")
                    .font(.headline)

                PTZDirectionButton(direction: .up, model: model)

                HStack(spacing: 12) {
                    PTZDirectionButton(direction: .left, model: model)

                    Image(systemName: "camera.metering.center.weighted")
                        .foregroundStyle(.secondary)
                        .frame(width: 58, height: 42)

                    PTZDirectionButton(direction: .right, model: model)
                }

                PTZDirectionButton(direction: .down, model: model)

            }
            .frame(maxWidth: .infinity)
            .disabled(isDisabled)
        }
    }
}

private struct PTZDirectionButton: View {
    let direction: AijiaPTZDirection
    @ObservedObject var model: PlayerViewModel

    var body: some View {
        Button {
            model.controlPTZ(direction)
        } label: {
            Image(systemName: direction.systemImage)
                .frame(width: 58, height: 42)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("云台\(direction.title)")
    }
}

private struct HistoryView: View {
    @ObservedObject var model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var hasLoadedOnce = false
    @State private var showingDiagnostics = false
    @State private var showingFullscreen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("日期", selection: $selectedDate, displayedComponents: .date)

                        Button {
                            model.loadRecordings(for: selectedDate, force: true)
                            hasLoadedOnce = true
                        } label: {
                            HStack {
                                if model.isLoadingRecordings {
                                    ProgressView()
                                }
                                Text(model.isLoadingRecordings ? "正在查询…" : "查询历史录像")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isLoadingRecordings || !model.isAuthenticated)
                    }
                }

                if model.isReplay, model.streamURL != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("正在回放")
                            .font(.headline)
                        PlayerSurface(model: model) {
                            showingFullscreen = true
                        }
                        ReplayControls(model: model)
                        Button(role: .destructive) {
                            model.stopReplay()
                        } label: {
                            Label("停止回放", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if model.isLoadingRecordings {
                    ProgressView("正在读取内存卡录像…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if model.recordings.isEmpty {
                    Text(hasLoadedOnce ? "当天没有找到录像" : "选择日期后查询内存卡录像")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("录像片段（\(model.recordings.count)）")
                            .font(.headline)

                        ForEach(model.recordings) { recording in
                            Button {
                                model.playRecording(recording)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(timeRange(for: recording))
                                            .font(.body.monospacedDigit())
                                        Text("点击播放此片段")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }

                StatusText(model: model)
            }
            .padding()
        }
        .navigationTitle("内存卡回放")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    // Only an explicit return to the live page ends replay.
                    // Pushing DiagnosticsView must leave the replay session alive.
                    model.stopReplay()
                    dismiss()
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .accessibilityLabel("返回播放")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingDiagnostics = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel("诊断日志")
            }
        }
        .onAppear {
            model.setHistoryVisible(true)
            guard !hasLoadedOnce, model.isAuthenticated else { return }
            hasLoadedOnce = true
            model.loadRecordings(for: selectedDate)
        }
        .onDisappear {
            model.setHistoryVisible(false)
        }
        .sheet(isPresented: $showingDiagnostics) {
            NavigationView {
                DiagnosticsView(model: model)
            }
        }
        .fullScreenCover(isPresented: $showingFullscreen, onDismiss: {
            ScreenOrientation.restorePortrait()
        }) {
            FullscreenPlayerView(model: model)
        }
    }

    private func timeRange(for recording: AijiaRecording) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return "\(formatter.string(from: recording.startDate)) – \(formatter.string(from: recording.endDate))"
    }
}

private struct DiagnosticsView: View {
    // The diagnostics page only invokes commands on the model. It does not
    // need model-driven redraws while the replay clock is running.
    let model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logger = DiagnosticsLogger.shared
    @State private var diagnosticsURL: URL?
    @State private var showingShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                HStack {
                    Label("实时记录", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("\(logger.visibleLines.count) 行")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if logger.visibleLevels.count != DiagnosticsLogger.Level.allCases.count {
                    HStack {
                        Text(filterSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    if logger.visibleLines.isEmpty {
                        Text("暂时没有诊断日志")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(logger.visibleLines.enumerated()), id: \.offset) { entry in
                                Text(entry.element)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("log-bottom")
                }
                .background(Color(.systemGroupedBackground))
                .onAppear {
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: logger.visibleLines.last ?? "") { _ in
                    scrollToBottom(proxy, animated: true)
                }
            }
        }
        .navigationTitle("诊断日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("完成") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        logger.visibleLevels = Set(DiagnosticsLogger.Level.allCases)
                    } label: {
                        if logger.visibleLevels == Set(DiagnosticsLogger.Level.allCases) {
                            Label("显示全部", systemImage: "checkmark")
                        } else {
                            Text("显示全部")
                        }
                    }
                    Divider()
                    ForEach(DiagnosticsLogger.Level.allCases, id: \.self) { level in
                        Toggle(level.title, isOn: levelBinding(level))
                    }
                } label: {
                    Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("日志等级筛选")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        guard let url = model.prepareDiagnosticsExport() else { return }
                        diagnosticsURL = url
                        showingShareSheet = true
                    } label: {
                        Label("导出日志", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        model.clearDiagnostics()
                    } label: {
                        Label("清除日志", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("日志操作")
            }
        }
        .sheet(isPresented: $showingShareSheet, onDismiss: {
            diagnosticsURL = nil
        }) {
            if let diagnosticsURL = diagnosticsURL {
                ActivityView(activityItems: [diagnosticsURL])
            }
        }
    }

    private func levelBinding(_ level: DiagnosticsLogger.Level) -> Binding<Bool> {
        Binding(
            get: { logger.visibleLevels.contains(level) },
            set: { isOn in
                if isOn {
                    logger.visibleLevels.insert(level)
                } else {
                    logger.visibleLevels.remove(level)
                }
            }
        )
    }

    private var filterSummary: String {
        let enabled = DiagnosticsLogger.Level.allCases
            .filter { logger.visibleLevels.contains($0) }
            .map(\.title)
        return enabled.isEmpty ? "已隐藏全部等级" : "已筛选：\(enabled.joined(separator: "、"))"
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("log-bottom", anchor: .bottom)
            }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
