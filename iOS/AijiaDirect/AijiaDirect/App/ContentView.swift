import IJKMediaFramework
import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var model: PlayerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var theme = ThemeStore.shared
    @State private var showingCameraSelection = false

    var body: some View {
        Group {
            if model.shouldShowLogin || (!model.hasSavedLogin && !model.isAuthenticated) {
                LoginView(model: model)
            } else {
                PlayerScreen(model: model)
            }
        }
        .tint(theme.accent.color)
        .preferredColorScheme(theme.appearance.colorScheme)
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
        // Pre-warm the first camera while the user is deciding so the chosen
        // stream starts almost instantly (mirrors the official player).
        if let first = model.cameras.first {
            model.prewarm(for: first)
        }
        showingCameraSelection = true
    }
}

// MARK: - Theme

private enum AppAccent: String, CaseIterable, Identifiable {
    case teal
    case blue
    case indigo
    case purple
    case pink
    case orange
    case green
    case red

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teal: return "青绿"
        case .blue: return "蓝色"
        case .indigo: return "靛蓝"
        case .purple: return "紫色"
        case .pink: return "粉色"
        case .orange: return "橙色"
        case .green: return "绿色"
        case .red: return "红色"
        }
    }

    var color: Color {
        switch self {
        case .teal: return Color(red: 0.11, green: 0.60, blue: 0.53)
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .orange: return .orange
        case .green: return .green
        case .red: return .red
        }
    }
}

private enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    private static let accentKey = "appearance.accent"
    private static let appearanceKey = "appearance.mode"

    @Published var accent: AppAccent {
        didSet {
            UserDefaults.standard.set(accent.rawValue, forKey: Self.accentKey)
            DiagnosticsLogger.shared.info("UI", "用户切换主题色 accent=\(accent.rawValue)")
        }
    }

    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            DiagnosticsLogger.shared.info("UI", "用户切换外观模式 mode=\(appearance.rawValue)")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.accentKey)
        accent = AppAccent(rawValue: saved ?? "") ?? .teal
        let savedAppearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
        appearance = AppAppearance(rawValue: savedAppearance ?? "") ?? .system
        DiagnosticsLogger.shared.info(
            "UI",
            "主题配置已载入 accent=\(accent.rawValue) mode=\(appearance.rawValue)"
        )
    }
}

private enum AppTheme {
    static var accent: Color {
        ThemeStore.shared.accent.color
    }

    static let cardRadius: CGFloat = 16

    static var softAccent: Color { accent.opacity(0.09) }

    static var cardBackground: Color {
        Color(.secondarySystemGroupedBackground)
    }

    static func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(cardBackground)
            )
    }
}

private struct AppMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let icon = appIcon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 100, height: 100)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1.5)
        )
    }

    private var appIcon: UIImage? {
        // Use the matching light/dark artwork explicitly; the asset catalog
        // icon variants are not reliably resolved by UIImage(named:).
        UIImage(named: colorScheme == .dark ? "AppIcon-Dark" : "AppIcon-Light")
    }
}

private struct LoginView: View {
    @ObservedObject var model: PlayerViewModel
    @FocusState private var focusedField: Field?
    @State private var showingAbout = false
    @State private var showingDiagnostics = false

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
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Menu {
                        Button {
                            DiagnosticsLogger.shared.info("UI", "用户从登录页打开关于页面")
                            showingAbout = true
                        } label: {
                            Label("关于", systemImage: "info.circle")
                        }
                        Button {
                            DiagnosticsLogger.shared.info("UI", "用户从登录页打开诊断日志")
                            showingDiagnostics = true
                        } label: {
                            Label("诊断日志", systemImage: "doc.text.magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("更多操作")
                }
                .padding(.horizontal, 12)

                Spacer(minLength: 8)

                VStack(spacing: 24) {
                    VStack(spacing: 14) {
                        AppMark()
                        VStack(spacing: 5) {
                            Text("爱家直连")
                                .font(.system(size: 30, weight: .bold))
                            Text("移动爱家第三方 iOS 客户端")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 14) {
                            Text("账号登录")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            LoginField(icon: "person.fill") {
                                TextField("移动手机号", text: $model.phone)
                                    .textContentType(.telephoneNumber)
                                    .keyboardType(.phonePad)
                                    .focused($focusedField, equals: .phone)
                            }

                            LoginField(icon: "lock.fill") {
                                SecureField("移动爱家密码", text: passwordBinding)
                                    .textContentType(.password)
                                    .focused($focusedField, equals: .password)
                            }

                            Toggle("记住登录信息", isOn: $model.rememberLogin)
                                .font(.subheadline)
                                .padding(.horizontal, 2)

                            Button {
                                focusedField = nil
                                model.start()
                            } label: {
                                HStack {
                                    if model.isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(model.isLoading ? "正在登录…" : "登录")
                                        .font(.headline)
                                }
                                .frame(width: 306, height: 48)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppTheme.accent)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(
                                model.isLoading ||
                                model.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                model.password.isEmpty
                            )
                    }
                    .padding(18)
                    .frame(width: 342, height: 280)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(AppTheme.cardBackground)
                    )

                    if !model.status.isEmpty {
                        StatusText(model: model)
                    }

                    Text("密码只保存在本机钥匙串，不会上传到其他服务器。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppTheme.softAccent))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("本机直连云端")
                                .font(.subheadline.weight(.semibold))
                            Text("视频由 iPhone 本机解码，不经过中转服务器")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .frame(width: 342, height: 96)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AppTheme.softAccent)
                    )
                }
                .padding(20)

                Spacer(minLength: 12)
            }
            .background(Color(.systemGroupedBackground))
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("完成") {
                        focusedField = nil
                    }
                }
            }
            .sheet(isPresented: $showingAbout) {
                NavigationView {
                    AboutView()
                }
            }
            .sheet(isPresented: $showingDiagnostics) {
                NavigationView {
                    DiagnosticsView(model: model)
                }
            }
            .onAppear {
                DiagnosticsLogger.shared.info("UI", "显示登录页面")
            }
        }
    }
}

private struct LoginField<Content: View>: View {
    let icon: String
    let content: Content

    init(icon: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(AppTheme.softAccent))
            content
        }
        .frame(width: 282, alignment: .leading)
        .frame(width: 306, height: 54)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct CameraSelectionPage: View {
    @ObservedObject var model: PlayerViewModel
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if model.cameras.isEmpty {
                    VStack(spacing: 10) {
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
                                Image(systemName: "web.camera")
                                    .font(.title3)
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(camera.name)
                                        .font(.body.weight(.medium))
                                    Text(camera.macID)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.selectedCameraID == camera.macID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.accent)
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
        .listStyle(.insetGrouped)
        .tint(theme.accent.color)
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
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    AppMark()
                    Text("爱家直连")
                        .font(.title3.weight(.bold))
                    Text("版本 \(AppVersionInfo.display) (\(AppVersionInfo.build))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            Section("主题色") {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                    spacing: 12
                ) {
                    ForEach(AppAccent.allCases) { accent in
                        Button {
                            theme.accent = accent
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(accent.color)
                                        .frame(width: 30, height: 30)
                                    if theme.accent == accent {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                Text(accent.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("主题色\(accent.title)")
                    }
                }
                .padding(.vertical, 4)
            }

            Section("外观模式") {
                Picker("外观模式", selection: $theme.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Label(appearance.title, systemImage: appearance.icon)
                            .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Text("跟随系统会随 iPhone 的浅色或深色模式自动切换。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("项目介绍") {
                Text("爱家直连是一款第三方 iOS 客户端，直接登录移动爱家云端，读取账号下摄像头并在 iPhone 本机解码播放实时与内存卡回放视频。")
            }

            Section("作者") {
                HStack {
                    Text("作者")
                    Spacer()
                    Text("fucknima")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("邮箱")
                    Spacer()
                    Link("fucknimama@icloud.com", destination: URL(string: "mailto:fucknimama@icloud.com")!)
                        .foregroundStyle(AppTheme.accent)
                }
            }

            Section("仓库地址") {
                Link("github.com/fucknima/yidongaijia", destination: URL(string: "https://github.com/fucknima/yidongaijia")!)
            }

            Section("开源许可") {
                Text("本项目基于 MIT License 开源，允许自由使用、修改与分发。")
                Text("Copyright © 2026 fucknima")
                    .foregroundStyle(.secondary)
                Link("查看完整许可协议", destination: URL(string: "https://github.com/fucknima/yidongaijia/blob/main/LICENSE")!)
            }

            Section("免责声明") {
                Text("本项目是移动爱家的第三方 iOS 客户端，不是中国移动、移动爱家或其关联公司的官方应用、SDK，也不代表上述任何一方。请只在你有权使用的账号和摄像头上运行。云端接口、签名规则和服务策略可能变化；本项目不提供或绕过官方授权，也不保证接口长期稳定。")
            }
        }
        .listStyle(.insetGrouped)
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
    @State private var showingMediaLibrary = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.cameraName.isEmpty ? "我的摄像头" : model.cameraName)
                            .font(.system(size: 23, weight: .bold))
                        Text(model.isLoading ? "正在连接云端…" : "在线 · \(model.networkSpeedText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        DiagnosticsLogger.shared.info("UI", "用户从直播顶栏打开摄像头选择页")
                        showingCameraSelection = true
                    } label: {
                        Image(systemName: "web.camera.fill")
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(AppTheme.softAccent))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择摄像头")

                    Menu {
                        Text("版本 \(AppVersionInfo.display)")
                        Button {
                            DiagnosticsLogger.shared.info("UI", "用户从直播顶栏打开诊断日志")
                            showingDiagnostics = true
                        } label: {
                            Label("诊断日志", systemImage: "doc.text.magnifyingglass")
                        }
                        Button {
                            DiagnosticsLogger.shared.info("UI", "用户打开关于页面")
                            showingAbout = true
                        } label: {
                            Label("关于", systemImage: "info.circle")
                        }
                        if model.streamURL != nil {
                            Button(role: .destructive) {
                                DiagnosticsLogger.shared.info("UI", "用户从直播顶栏菜单停止播放")
                                model.stop()
                            } label: {
                                Label("停止直播", systemImage: "stop.fill")
                            }
                        }
                        Button(role: .destructive) {
                            model.logout()
                        } label: {
                            Label("退出并返回登录", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                    }
                    .accessibilityLabel("更多操作")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 16) {
                    // SwiftUI may replace this host during presentation, but
                    // the model keeps one persistent player view throughout.
                    if model.streamURL != nil, !model.isReplay {
                        PlayerSurface(model: model) {
                            showingFullscreen = true
                        }
                        .frame(width: 354, height: 204)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                        ZStack(alignment: .leading) {
                            MediaActionButton(
                                icon: "camera.fill",
                                title: "截图",
                                tint: AppTheme.accent
                            ) {
                                model.captureSnapshot()
                            }
                            .disabled(!model.isPlaying || model.isRecording)
                            .opacity(model.isPlaying && !model.isRecording ? 1 : 0.4)
                            .offset(x: 22)
                            MediaActionButton(
                                icon: model.isRecording ? "stop.fill" : "record.circle",
                                title: model.isRecording ? "停止录像" : "录像",
                                tint: model.isRecording ? .red : AppTheme.accent
                            ) {
                                model.toggleRecording()
                            }
                            .disabled(!model.isPlaying)
                            .opacity(model.isPlaying ? 1 : 0.4)
                            .offset(x: 134)
                            MediaActionButton(
                                icon: "photo.on.rectangle.angled",
                                title: "媒体库",
                                tint: AppTheme.accent
                            ) {
                                DiagnosticsLogger.shared.info("UI", "用户从直播主页打开媒体库")
                                showingMediaLibrary = true
                            }
                            .offset(x: 246)
                        }
                        .frame(width: 354, height: 82, alignment: .leading)

                        HStack(spacing: 8) {
                            Circle()
                                .fill(model.isPlaying ? AppTheme.accent : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(liveStatusText)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .layoutPriority(1)
                            Spacer()
                            Text(model.isPlaying ? "播放中" : "已停止")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 14)
                        .frame(width: 342, height: 46)
                        .foregroundStyle(model.isPlaying ? AppTheme.accent : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.softAccent)
                        )
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: model.hasError ? "wifi.exclamationmark" : "video")
                                .font(.system(size: 40))
                                .foregroundStyle(model.hasError ? .red : AppTheme.accent)
                            Text(model.isLoading ? "正在获取视频地址" : "暂时没有播放画面")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.secondary)

                            if !model.isLoading {
                                Button("重新连接") {
                                    model.start()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.accent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 56)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }

                    if model.isAuthenticated {
                        PTZControlPanel(model: model)

                        NavigationLink(
                            destination: HistoryView(model: model),
                            isActive: $showingHistory
                        ) {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.title3)
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 30)
                                Text("内存卡回放")
                                    .font(.body.weight(.medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .frame(width: 342, height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }
                }
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
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
        .sheet(isPresented: $showingMediaLibrary) {
            NavigationView {
                MediaLibraryView()
            }
        }
        .fullScreenCover(isPresented: $showingFullscreen, onDismiss: {
            ScreenOrientation.restorePortrait()
        }) {
            FullscreenPlayerView(model: model)
        }
        .onAppear {
            DiagnosticsLogger.shared.info("UI", "显示直播主页 camera=\(DiagnosticsLogger.maskIdentifier(model.selectedCameraID))")
        }
    }

    private var liveStatusText: String {
        let status = model.status.trimmingCharacters(in: .whitespacesAndNewlines)
        if !status.isEmpty { return status }
        return model.isPlaying ? "直播稳定 · HEVC" : "直播已暂停"
    }
}

private struct MediaActionButton: View {
    let icon: String
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(width: 60)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct StatusPill: View {
    @ObservedObject var model: PlayerViewModel

    private var color: Color {
        if model.hasError { return .red }
        if model.isLoading { return .orange }
        if model.isPlaying { return AppTheme.accent }
        return .gray
    }

    private var label: String {
        if model.hasError { return "错误" }
        if model.isLoading { return "连接中" }
        if model.isPlaying { return "直播中" }
        return "已停止"
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

private struct PlayerSurface: View {
    @ObservedObject var model: PlayerViewModel
    let onFullscreen: () -> Void

    var body: some View {
        ZStack {
            IJKPlayerView(model: model)
                .id(model.playerViewID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            VStack {
                HStack {
                    Text(model.isReplay ? model.networkSpeedText : "LIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                    Spacer()
                }
                Spacer()
            }
            .padding(12)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: onFullscreen) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
                    .accessibilityLabel("横屏全屏")
                }
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .onAppear {
            DiagnosticsLogger.shared.info(
                "UI",
                "显示播放器浮层 mode=\(model.isReplay ? "replay-speed" : "live-badge")"
            )
        }
    }
}

private struct FullscreenPlayerView: View {
    @ObservedObject var model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var replayControlsVisible = true
    @State private var hideReplayControlsTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            IJKPlayerView(model: model, role: .fullscreen)
                .id(model.playerViewID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleReplayControls()
                }

            Text(model.networkSpeedText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.4)))
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if model.isReplay, replayControlsVisible {
                VStack {
                    Spacer()
                    ReplayControls(model: model, presentation: .fullscreen)
                        .frame(maxWidth: .infinity)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(2)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }
            .buttonStyle(.plain)
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
            if model.isReplay {
                scheduleReplayControlsAutoHide()
            }
        }
        .onChange(of: model.isReplay) { replay in
            replayControlsVisible = true
            if replay {
                scheduleReplayControlsAutoHide()
            } else {
                hideReplayControlsTask?.cancel()
                hideReplayControlsTask = nil
            }
        }
        .onDisappear {
            hideReplayControlsTask?.cancel()
            hideReplayControlsTask = nil
        }
    }

    private func toggleReplayControls() {
        hideReplayControlsTask?.cancel()
        hideReplayControlsTask = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            replayControlsVisible.toggle()
        }
        if replayControlsVisible {
            scheduleReplayControlsAutoHide()
        }
    }

    private func scheduleReplayControlsAutoHide() {
        guard model.isReplay else { return }
        hideReplayControlsTask?.cancel()
        hideReplayControlsTask = nil
        hideReplayControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.replayControlsVisible = false
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
}

private struct PTZControlPanel: View {
    @ObservedObject var model: PlayerViewModel

    private var isDisabled: Bool {
        model.isReplay || model.isLoading || !model.isAuthenticated
    }

    var body: some View {
        VStack(spacing: 2) {
                HStack {
                    Text("云台控制")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("按一下移动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: -2) {
                    PTZDirectionButton(direction: .up, model: model)

                    HStack(spacing: -1) {
                        PTZDirectionButton(direction: .left, model: model)

                        Image(systemName: "camera.metering.center.weighted")
                            .foregroundStyle(.secondary)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color(.tertiarySystemFill)))

                        PTZDirectionButton(direction: .right, model: model)
                    }

                    PTZDirectionButton(direction: .down, model: model)
                }
                .frame(maxWidth: .infinity)
                .disabled(isDisabled)
        }
        .padding(10)
        .frame(width: 342, height: 190)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 46, height: 46)
                .background(
                    Circle().fill(AppTheme.softAccent)
                )
        }
        .buttonStyle(.plain)
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
    @State private var showingDatePicker = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    DiagnosticsLogger.shared.info("UI", "用户从回放顶栏返回直播页")
                    model.stopReplay()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回播放")

                Spacer()
                Text("内存卡回放")
                    .font(.headline)
                Spacer()

                Button {
                    DiagnosticsLogger.shared.info("UI", "用户从回放顶栏打开诊断日志")
                    showingDiagnostics = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("诊断日志")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 16) {
                AppTheme.card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("选择日期")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 12) {
                            Button {
                                DiagnosticsLogger.shared.info("UI", "用户打开回放日期选择器")
                                showingDatePicker = true
                            } label: {
                                HStack(spacing: 8) {
                                    Text(Self.dayFormatter.string(from: selectedDate))
                                        .font(.title3.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Image(systemName: "calendar")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.accent)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                DiagnosticsLogger.shared.info("UI", "用户查询指定日期的内存卡录像")
                                model.loadRecordings(for: selectedDate, force: true)
                                hasLoadedOnce = true
                            } label: {
                                if model.isLoadingRecordings {
                                    ProgressView()
                                } else {
                                    Text("查询")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(AppTheme.accent)
                            .frame(minWidth: 72)
                            .disabled(model.isLoadingRecordings || !model.isAuthenticated)
                        }
                    }
                }

                if model.isReplay, model.streamURL != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("正在回放")
                            .font(.headline)
                        PlayerSurface(model: model) {
                            showingFullscreen = true
                        }
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                        ReplayControls(model: model)
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(role: .destructive) {
                            DiagnosticsLogger.shared.info("UI", "用户点击停止内存卡回放")
                            model.stopReplay()
                        } label: {
                            Label("停止回放", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if model.isLoadingRecordings {
                    ProgressView("正在读取内存卡录像…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if model.recordings.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "film.stack")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(hasLoadedOnce ? "当天没有找到录像" : "选择日期后查询内存卡录像")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("录像片段（\(model.recordings.count)）")
                            .font(.headline)

                        List {
                            ForEach(model.recordings) { recording in
                                Button {
                                    model.playRecording(recording)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "play.fill")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(AppTheme.accent)
                                            .frame(width: 36, height: 36)
                                            .background(Circle().fill(AppTheme.softAccent))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(timeRange(for: recording))
                                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                            Text(durationText(for: recording))
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(AppTheme.cardBackground)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.plain)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                    }
                }

                StatusText(model: model)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
        .onAppear {
            DiagnosticsLogger.shared.info("UI", "显示内存卡回放页面")
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
        .sheet(isPresented: $showingDatePicker) {
            NavigationView {
                DatePicker(
                    "选择回放日期",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("选择日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            DiagnosticsLogger.shared.info(
                                "UI",
                                "用户完成回放日期选择 day=\(Self.dayFormatter.string(from: selectedDate))"
                            )
                            showingDatePicker = false
                        }
                    }
                }
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

    private func durationText(for recording: AijiaRecording) -> String {
        let duration = max(0, Int(recording.endDate.timeIntervalSince(recording.startDate)))
        return "\(duration / 60) 分 \(duration % 60) 秒"
    }
}

private struct DiagnosticsView: View {
    // The diagnostics page only invokes commands on the model. It does not
    // need model-driven redraws while the replay clock is running.
    let model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logger = DiagnosticsLogger.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var diagnosticsURL: URL?
    @State private var showingShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                HStack {
                    Label("实时记录", systemImage: "dot.radiowaves.left.and.right")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accent)
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
        .tint(theme.accent.color)
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
                EmbeddedActivityView(activityItems: [diagnosticsURL])
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

private struct MediaLibraryView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all
        case recordings

        var id: String { rawValue }
        var title: String { self == .all ? "全部" : "录像" }
    }

    @ObservedObject private var library = MediaLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var previewItem: MediaItem?
    @State private var filter: Filter = .all

    private var displayedItems: [MediaItem] {
        switch filter {
        case .all: return library.items
        case .recordings: return library.items.filter { $0.kind == .video }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    DiagnosticsLogger.shared.info("UI", "用户从媒体库顶栏返回直播页")
                    dismiss()
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回直播")
                Spacer()
                Text("媒体库")
                    .font(.headline)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Group {
                if library.items.isEmpty {
                    VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("暂无截图或录像")
                        .font(.headline)
                    Text("在直播画面点击截图或录像，内容会保存在这里。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    List {
                    Section {
                        Picker("媒体类型", selection: $filter) {
                            ForEach(Filter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: filter) { newValue in
                            DiagnosticsLogger.shared.info("UI", "用户切换媒体库筛选 filter=\(newValue.rawValue)")
                        }
                    }

                    Section {
                        if displayedItems.isEmpty {
                            Text("暂无录像")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(displayedItems) { item in
                                Button {
                                    DiagnosticsLogger.shared.info("UI", "用户预览本地媒体 type=\(item.kind.logValue)")
                                    previewItem = item
                                } label: {
                                    MediaLibraryRow(item: item)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        library.delete(item)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    Button {
                                        presentSystemShare(activityItems: [sharePayload(for: item)])
                                    } label: {
                                        Label("分享", systemImage: "square.and.arrow.up")
                                    }
                                    .tint(AppTheme.accent)
                                }
                                .contextMenu {
                                    Button {
                                        presentSystemShare(activityItems: [sharePayload(for: item)])
                                    } label: {
                                        Label("分享", systemImage: "square.and.arrow.up")
                                    }
                                    Button(role: .destructive) {
                                        library.delete(item)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("左滑：分享 / 删除")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("保留现有本机文件管理逻辑")
                        }
                    }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .tint(theme.accent.color)
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
        .sheet(item: $previewItem) { item in
            NavigationView {
                MediaPreviewView(item: item)
            }
        }
        .onAppear {
            DiagnosticsLogger.shared.info("UI", "显示媒体库页面 itemCount=\(library.items.count)")
            library.reload()
        }
    }

    /// Both images and videos are shared as file URLs. QuickLook generates
    /// the preview thumbnail from the file; sharing a UIImage instead can
    /// fall back to a generic white document icon when the image fails to
    /// load or the system preview path is unavailable.
    private func sharePayload(for item: MediaItem) -> Any {
        item.url as Any
    }
}

private struct MediaLibraryRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.kind == .image ? "截图" : "录像")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.fileSizeText.isEmpty {
                    Text(item.fileSizeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.kind {
        case .image:
            if let image = UIImage(contentsOfFile: item.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        case .video:
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            )
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: item.date)
    }
}

private struct MediaPreviewView: View {
    let item: MediaItem

    var body: some View {
        Group {
            switch item.kind {
            case .image:
                if let image = UIImage(contentsOfFile: item.url.path) {
                    ScrollView {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                } else {
                    Text("无法读取图片")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .video:
                // IJK plays local HEVC/TS recordings that AVPlayer may reject.
                IJKLocalPlayerView(url: item.url)
                    .ignoresSafeArea()
            }
        }
        .background(Color.black)
        .navigationTitle(item.fileName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Minimal IJK-backed local video player for media library previews.
/// The preview uses its own player instance so the live player keeps playing.
private struct IJKLocalPlayerView: UIViewRepresentable {
    let url: URL

    final class Coordinator {
        weak var player: IJKFFMoviePlayerController?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let hostView = UIView()
        hostView.backgroundColor = .black
        guard let options = IJKFFOptions.byDefault(),
              let player = IJKFFMoviePlayerController(contentURL: url, with: options),
              let playerView = player.view else {
            return hostView
        }
        player.scalingMode = .aspectFit
        playerView.frame = hostView.bounds
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostView.addSubview(playerView)
        player.prepareToPlay()
        player.play()
        context.coordinator.player = player
        return hostView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.player?.view.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.player?.shutdown()
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    @Binding var isPresented: Bool

    final class Coordinator {
        var presented = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard isPresented, !context.coordinator.presented else { return }

        // Defer until the container view controller is attached to the window
        // hierarchy; presenting immediately leaves the share panel invisible.
        context.coordinator.presented = true
        DispatchQueue.main.async { [weak controller] in
            guard let controller = controller, controller.presentedViewController == nil else {
                context.coordinator.presented = false
                return
            }
            let activity = UIActivityViewController(
                activityItems: activityItems,
                applicationActivities: nil
            )
            activity.completionWithItemsHandler = { _, _, _, _ in
                context.coordinator.presented = false
                isPresented = false
            }
            controller.present(activity, animated: true)
        }
    }
}

/// Presents the system share sheet from the topmost presented view
/// controller. Sharing through SwiftUI sheets is unreliable on some iOS
/// versions (blank panel on first presentation), and presenting from the root
/// controller silently fails while another sheet (the media library itself)
/// is on screen, so we walk the presentation chain instead.
private func presentSystemShare(activityItems: [Any]) {
    guard let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene }).first,
        var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
        return
    }
    while let presented = top.presentedViewController {
        top = presented
    }
    guard top.presentedViewController == nil else { return }
    let activity = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    // Keep a strong reference until the deferred presentation runs; a weak
    // capture would be released before the menu dismiss animation finishes.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        guard top.presentedViewController == nil else { return }
        top.present(activity, animated: true)
    }
}

/// Embeds a UIActivityViewController directly as sheet content. This works on
/// some iOS versions for plain documents and keeps the diagnostics export
/// flow unchanged from the original working build.
private struct EmbeddedActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
