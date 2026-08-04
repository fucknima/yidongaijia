import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var model: PlayerViewModel
    @Environment(\.scenePhase) private var scenePhase

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
    }
}

private struct LoginView: View {
    @ObservedObject var model: PlayerViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case phone
        case password
        case camera
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

                            SecureField("移动爱家密码", text: $model.password)
                                .textContentType(.password)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .password)

                            TextField("mac_id 或摄像头名称（可选）", text: $model.cameraSelector)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .camera)

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
                    NavigationLink(destination: UpdateLogView()) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .accessibilityLabel("更新日志")
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

private struct PlayerScreen: View {
    @ObservedObject var model: PlayerViewModel
    @State private var showingHistory = false
    @State private var showingDiagnostics = false
    @State private var showingFullscreen = false

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
                    NavigationLink(destination: UpdateLogView()) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .accessibilityLabel("更新日志")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Text("版本 \(AppVersionInfo.display)")
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
        ZStack {
            VLCPlayerView(model: model)
                .id(model.playerViewID)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Button(action: onFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("横屏全屏")
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            Label(model.streamSpeedText, systemImage: "arrow.down")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 2)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.clear, in: Capsule())
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityLabel("视频实时拉取速度 \(model.streamSpeedText)")
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

            if model.isReplay {
                VStack {
                    Spacer()
                    ReplayControls(model: model, presentation: .fullscreen)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(2)
            }

            Label(model.streamSpeedText, systemImage: "arrow.down")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 2)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityLabel("视频实时拉取速度 \(model.streamSpeedText)")

            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出全屏")
            .padding()
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

private struct ReleaseNote: Identifiable {
    let version: String
    let date: String
    let title: String
    let details: [String]

    var id: String { "\(version)-\(date)-\(title)" }
}

private enum AppVersionInfo {
    static var display: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
    }
}

private enum ReleaseNotesCatalog {
    static let all: [ReleaseNote] = [
        ReleaseNote(
            version: "回放诊断修复",
            date: "2026-08-02",
            title: "回放诊断隔离与查询去重",
            details: [
                "诊断日志改为独立弹窗，不再通过回放导航栈推入页面。",
                "打开、刷新和关闭诊断页不会停止或重建当前回放播放器。",
                "回放期间忽略页面生命周期触发的自动历史录像查询，避免重复请求和日志刷屏。",
                "保留手动查询历史录像功能，并延长重复查询保护时间。"
            ]
        ),
        ReleaseNote(
            version: "1.1",
            date: "2026-08-02",
            title: "回放与诊断导航修复",
            details: [
                "修复内存卡回放时打开诊断页会误停止回放并返回播放页。",
                "只有明确返回播放页或点击停止回放，才会结束回放会话。",
                "修复回放页面导航过程中的播放器释放问题。",
                "修复退出登录后重启 App 仍自动进入播放页的问题。",
                "构建版本改为每次 GitHub Actions 构建自动递增 0.1。"
            ]
        ),
        ReleaseNote(
            version: "历史构建 speedfix",
            date: "2026-08-02",
            title: "回放倍速与播放器状态修复",
            details: [
                "修复倍速设置被播放器回调覆盖的问题。",
                "回放切换、拖动进度和播放器重建时重新应用倍速。",
                "降低播放器视图更新对回放进度的干扰。"
            ]
        ),
        ReleaseNote(
            version: "历史构建 replaydiagfix",
            date: "2026-08-02",
            title: "回放进度与诊断稳定性修复",
            details: [
                "限制历史录像查询重复请求，避免诊断页面出现大量日志。",
                "忽略过期播放器和旧回放任务的进度回调。",
                "修复拖动进度后播放器黑屏、回放状态不同步和会话过期重试问题。"
            ]
        ),
        ReleaseNote(
            version: "历史构建 v23–v24",
            date: "2026-08-02",
            title: "历史回放交互修复",
            details: [
                "按录像片段起点请求历史地址，避免点击当天回放从错误时间开始。",
                "增加服务器回放定位和拖动进度的恢复逻辑。",
                "修复回放结束切回直播后页面状态合并、黑屏和无画面提示问题。"
            ]
        ),
        ReleaseNote(
            version: "历史构建 v21–v22",
            date: "2026-08-02",
            title: "日志、文件访问与前后台修复",
            details: [
                "支持导出诊断日志，并允许从 iPhone 文件 App 访问。",
                "修复回放切换后台再回来后只剩声音或视图丢失。",
                "增加回放播放器在前后台切换时的恢复和旧地址清理。"
            ]
        ),
        ReleaseNote(
            version: "历史构建 v19–v20",
            date: "2026-08-02",
            title: "进度条与倍速播放",
            details: [
                "增加内存卡回放进度条和时间显示。",
                "增加 0.5x、1x、2x、3x、5x 倍速播放。",
                "拖动进度时使用云端回放定位，避免本地播放器时间与服务器录像不同步。"
            ]
        ),
        ReleaseNote(
            version: "历史构建 v16–v18",
            date: "2026-08-02",
            title: "构建工程与资源整理",
            details: [
                "整理 Xcode 工程、资源目录和 MobileVLCKit 构建所需文件。",
                "修复源码压缩包目录层级，确保 GitHub Actions 能正确解包构建。",
                "补齐深色/浅色 App 图标资源。"
            ]
        ),
        ReleaseNote(
            version: "历史构建 v10–v14",
            date: "2026-08-02",
            title: "登录、播放和页面结构完善",
            details: [
                "登录失败时返回登录界面，并保存账号密码输入内容。",
                "将登录、播放、内存卡回放和诊断日志分成独立页面。",
                "增加摄像头选择、登录状态恢复和播放器错误状态提示。"
            ]
        ),
        ReleaseNote(
            version: "历史构建 v8–v9",
            date: "2026-08-02",
            title: "界面与设备资源优化",
            details: [
                "更换爱家直连 App 图标，并加入浅色/深色图标适配。",
                "优化播放页布局、摄像头状态显示和控制按钮。",
                "增加本机解码播放器视图的挂载与释放处理。"
            ]
        ),
        ReleaseNote(
            version: "历史构建 v7",
            date: "2026-08-02",
            title: "前后台播放恢复",
            details: [
                "应用进入后台时暂停或释放不再可靠的播放状态。",
                "回到前台时重新获取实时地址，避免从几分钟前的缓存位置继续播放。",
                "增加播放保活和实时流恢复状态提示。"
            ]
        ),
        ReleaseNote(
            version: "历史构建 v6",
            date: "2026-08-02",
            title: "云台与内存卡回放",
            details: [
                "增加上下左右云台控制。",
                "按日期获取内存卡录像列表并打开历史录像。",
                "增加历史录像结束后恢复实时流的处理。"
            ]
        ),
        ReleaseNote(
            version: "历史构建 v5",
            date: "2026-08-02",
            title: "诊断日志",
            details: [
                "增加实时日志页面和日志导出。",
                "记录登录、HTTP 请求、播放器状态、保活和错误信息。",
                "对手机号、密码、令牌和签名地址进行脱敏。"
            ]
        ),
        ReleaseNote(
            version: "历史构建 v3–v4",
            date: "2026-08-02",
            title: "直连播放基础版",
            details: [
                "手机直接登录移动爱家云端，不经过中转服务器。",
                "获取实时地址并在 iPhone 本机用 MobileVLCKit 解码播放。",
                "支持账号下摄像头列表和可选摄像头名称/mac_id。"
            ]
        ),
        ReleaseNote(
            version: "1.0",
            date: "2026-08-02",
            title: "首个可用版本",
            details: [
                "整合登录、实时播放、云台、内存卡回放和诊断日志功能。",
                "密码保存到 iOS 钥匙串，诊断日志支持文件访问。"
            ]
        )
    ]
}

private struct UpdateLogView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Label("当前版本", systemImage: "app.badge")
                    Spacer()
                    Text("\(AppVersionInfo.display) (\(AppVersionInfo.build))")
                        .foregroundStyle(.secondary)
                        .font(.subheadline.monospacedDigit())
                }
            }

            Section("修复记录") {
                ForEach(ReleaseNotesCatalog.all) { note in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(note.version.hasPrefix("历史") ? note.version : "版本 \(note.version)")
                                .font(.headline)
                            Spacer()
                            Text(note.date)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Text(note.title)
                            .font(.subheadline.weight(.semibold))

                        ForEach(note.details, id: \.self) { detail in
                            Label(detail, systemImage: "checkmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("更新日志")
        .navigationBarTitleDisplayMode(.inline)
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

    private var controlsContent: some View {
        VStack(spacing: presentation == .fullscreen ? 6 : 8) {
            HStack {
                Text(formatTime(model.replayCurrentSecond))
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
                            HStack(spacing: 12) {
                                Button {
                                    model.playRecording(recording)
                                } label: {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    model.playRecording(recording)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(timeRange(for: recording))
                                            .font(.body.monospacedDigit())
                                        Text("点击播放此片段")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .buttonStyle(.plain)
                                Button {
                                    if model.downloadManager.recordingID == recording.id {
                                        model.cancelRecordingDownload()
                                    } else {
                                        model.downloadRecording(recording)
                                    }
                                } label: {
                                    Image(systemName: model.downloadManager.recordingID == recording.id ? "xmark.circle" : "arrow.down.circle")
                                        .font(.title2)
                                }
                                .disabled(
                                    model.isLoading ||
                                    (model.downloadManager.isDownloading && model.downloadManager.recordingID != recording.id)
                                )
                                .accessibilityLabel(model.downloadManager.recordingID == recording.id ? "取消下载" : "下载此录像到手机")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }

                if model.downloadManager.isDownloading || !model.downloadManager.stateText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(model.downloadManager.stateText, systemImage: "arrow.down.circle.fill")
                            Spacer()
                            Text(model.downloadManager.progress, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                        }
                        ProgressView(value: model.downloadManager.progress)
                        Text(ByteCountFormatter.string(fromByteCount: model.downloadManager.downloadedBytes, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Label(model.downloadManager.downloadSpeedText, systemImage: "speedometer")
                                .font(.caption.monospacedDigit())
                            Spacer()
                            if model.downloadManager.isDownloading {
                                Button("取消并删除", role: .destructive) {
                                    model.cancelRecordingDownload()
                                }
                            } else if model.downloadManager.savedURL != nil {
                                Button("删除文件", role: .destructive) {
                                    model.downloadManager.deleteSavedFile()
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
            guard !hasLoadedOnce, model.isAuthenticated else { return }
            hasLoadedOnce = true
            model.loadRecordings(for: selectedDate)
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
            HStack {
                Label("实时记录", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                Spacer()
                Text("\(logger.visibleLines.count) 行")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
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
