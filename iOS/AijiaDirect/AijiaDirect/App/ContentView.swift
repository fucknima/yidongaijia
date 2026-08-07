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

private final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    private static let accentKey = "appearance.accent"

    @Published var accent: AppAccent {
        didSet {
            UserDefaults.standard.set(accent.rawValue, forKey: Self.accentKey)
            DiagnosticsLogger.shared.info("UI", "用户切换主题色 accent=\(accent.rawValue)")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.accentKey)
        accent = AppAccent(rawValue: saved ?? "") ?? .teal
    }
}

private enum AppTheme {
    static var accent: Color {
        ThemeStore.shared.accent.color
    }

    /// 品牌主色 #139A82(来自 Player.svg)
    static let brand = Color(red: 0.075, green: 0.604, blue: 0.510)
    /// 品牌浅底 #ECF8F5
    static let brandSoft = Color(red: 0.925, green: 0.973, blue: 0.961)

    static let cardRadius: CGFloat = 16

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
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
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
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 14) {
                        AppMark()
                        VStack(spacing: 5) {
                            Text("爱家直连")
                                .font(.title.weight(.bold))
                            Text("登录移动爱家账号，摄像头画面在本机解码")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 44)

                    AppTheme.card {
                        VStack(spacing: 14) {
                            TextField("移动手机号", text: $model.phone)
                                .textContentType(.telephoneNumber)
                                .keyboardType(.phonePad)
                                .focused($focusedField, equals: .phone)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                )

                            SecureField("移动爱家密码", text: passwordBinding)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                )

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
                                    Text(model.isLoading ? "正在登录…" : "登录并播放")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.accent)
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
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingAbout = true
                        } label: {
                            Label("关于", systemImage: "info.circle")
                        }
                        Button {
                            showingDiagnostics = true
                        } label: {
                            Label("诊断日志", systemImage: "doc.text.magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多操作")
                }
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
        }
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
            ZStack {
                // 背景 #F7F8FA
                Color(red: 0.969, green: 0.973, blue: 0.980)
                    .ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // 顶部:标题(23pt Bold)+ 在线状态(13pt)+ 两个圆钮
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(model.cameraName.isEmpty ? "我的摄像头" : model.cameraName)
                                    .font(.system(size: 23, weight: .bold))
                                    .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                                    .frame(height: 28, alignment: .bottomLeading)
                                Text(model.isLoading ? "正在连接云端…" : "在线 · \(model.networkSpeedText)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(red: 0.392, green: 0.455, blue: 0.545))
                                    .padding(.top, 6)
                            }
                            Spacer(minLength: 0)
                            // 设备切换按钮:中心 (315,92) 直径36
                            Button {
                                showingCameraSelection = true
                            } label: {
                                Circle()
                                    .fill(AppTheme.brandSoft)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Image(systemName: "video.badge.plus")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(AppTheme.brand)
                                    )
                            }
                            .buttonStyle(.plain)
                            .frame(width: 36, height: 36)
                            // 更多按钮:中心 (354,92) 直径36
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
                                Button {
                                    showingDiagnostics = true
                                } label: {
                                    Label("诊断日志", systemImage: "doc.text.magnifyingglass")
                                }
                                Button(role: .destructive) {
                                    model.logout()
                                } label: {
                                    Label("退出并返回登录", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            } label: {
                                Circle()
                                    .fill(Color(red: 0.933, green: 0.949, blue: 0.969)) // #EEF2F7
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(Color(red: 0.278, green: 0.333, blue: 0.412)) // #475569
                                    )
                            }
                            .frame(width: 36, height: 36)
                        }
                        .frame(width: 342, height: 64)
                        .padding(.top, 34)
                        .padding(.horizontal, 24)

                        // 视频容器:x=18 y=140 w=354 h=204 r=22
                        LiveVideoPanel(
                            model: model,
                            onFullscreen: { showingFullscreen = true }
                        )
                        .frame(width: 354, height: 204)
                        .padding(.top, 12)
                        .padding(.horizontal, 18)

                        // 三个操作按钮:中心 (70/182/294, 392) 圆直径60
                        HStack(spacing: 0) {
                            RoundActionButton(
                                icon: "camera.fill",
                                title: "截图",
                                isEnabled: model.isPlaying && !model.isRecording
                            ) {
                                model.captureSnapshot()
                            }
                            .frame(width: 112, height: 76)
                            RoundActionButton(
                                icon: model.isRecording ? "stop.fill" : "record.circle",
                                title: model.isRecording ? "停止录像" : "录像",
                                isEnabled: model.isPlaying,
                                tint: model.isRecording ? .red : AppTheme.brand
                            ) {
                                model.toggleRecording()
                            }
                            .frame(width: 112, height: 76)
                            RoundActionButton(
                                icon: "square.grid.2x2.fill",
                                title: "媒体库",
                                isEnabled: true
                            ) {
                                showingMediaLibrary = true
                            }
                            .frame(width: 112, height: 76)
                        }
                        .padding(.top, 14)

                        // 状态条:x=24 y=460 w=342 h=46 r=14
                        HStack(spacing: 0) {
                            Circle()
                                .fill(AppTheme.brand)
                                .frame(width: 10, height: 10)
                                .padding(.leading, 24)
                            Text("直播稳定 · HEVC")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                                .padding(.leading, 14)
                            Spacer(minLength: 0)
                            Button {
                                model.stop()
                            } label: {
                                Text("停止")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.392, green: 0.455, blue: 0.545))
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 22)
                        }
                        .frame(width: 342, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.brandSoft)
                        )
                        .padding(.top, 14)
                        .padding(.horizontal, 24)

                        if !model.status.isEmpty {
                            StatusText(model: model)
                                .padding(.top, 12)
                                .padding(.horizontal, 24)
                        }

                        // 云台卡片:x=24 y=526 w=342 h=190 r=24
                        if model.isAuthenticated {
                            PTZControlPanel(model: model)
                                .frame(width: 342, height: 190)
                                .padding(.top, 16)
                                .padding(.horizontal, 24)

                            // 回放入口:x=24 y=736 w=342 h=64 r=18
                            NavigationLink(
                                destination: HistoryView(model: model),
                                isActive: $showingHistory
                            ) {
                                HStack(spacing: 0) {
                                    ZStack {
                                        Circle()
                                            .fill(AppTheme.brandSoft)
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(AppTheme.brand)
                                    }
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("内存卡回放")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                                            .frame(height: 20, alignment: .bottomLeading)
                                        Text("按日期查看历史录像")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color(red: 0.392, green: 0.455, blue: 0.545))
                                            .padding(.top, 5)
                                    }
                                    .padding(.leading, 16)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.trailing, 20)
                                }
                                .frame(width: 342, height: 64)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(.white)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 10)
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, 24)
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
    }
}

/// 视频容器:x=18 y=140 w=354 h=204 r=22,渐变背景 + LIVE 标签 + 全屏按钮
private struct LiveVideoPanel: View {
    @ObservedObject var model: PlayerViewModel
    let onFullscreen: () -> Void

    var body: some View {
        ZStack {
            // 渐变背景(videoGrad)
            LinearGradient(
                colors: [
                    Color(red: 0.145, green: 0.192, blue: 0.239),  // #25313D
                    Color(red: 0.067, green: 0.094, blue: 0.153),  // #111827
                    Color(red: 0.043, green: 0.071, blue: 0.125),  // #0B1220
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // 有流时叠加播放器
            if model.streamURL != nil, !model.isReplay {
                IJKPlayerView(model: model)
                    .id(model.playerViewID)
                    .frame(width: 354, height: 204)
            }

            // LIVE 标签:30,154,72,28 r=14
            Text("LIVE")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 28)
                .background(Capsule().fill(Color.black.opacity(0.4)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 14)
                .padding(.leading, 12)

            // 全屏按钮:290,292,58,34 r=17
            Button(action: onFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(Color.black.opacity(0.47))
                    )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
        }
        .frame(width: 354, height: 204)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// 圆形操作按钮:圆直径 60,标签 baseline y=438 14pt Semibold
private struct RoundActionButton: View {
    let icon: String
    let title: String
    var isEnabled: Bool = true
    var tint: Color = AppTheme.brand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(.white)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isEnabled ? tint : Color.gray.opacity(0.5))
                    )
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color(red: 0.059, green: 0.090, blue: 0.078) : .secondary)
                    .frame(height: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
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
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
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
        ZStack(alignment: .topTrailing) {
            IJKPlayerView(model: model)
                .id(model.playerViewID)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))

            Text(model.networkSpeedText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Button(action: onFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.35)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
        VStack(spacing: 0) {
            // 标题:baseline y=558,17pt Bold
            HStack(alignment: .firstTextBaseline) {
                Text("云台控制")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                Spacer(minLength: 0)
                Text("按一下移动")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.392, green: 0.455, blue: 0.545))
            }
            .padding(.leading, 18)
            .padding(.trailing, 18)
            .padding(.top, 14)
            .frame(height: 24)

            // 方向键区:相对卡片内坐标
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: 342, height: 190)
                // 上:(195,588) 直径46 → 卡片内中心 (171,62)
                PTZDirectionButton(direction: .up, model: model)
                    .frame(width: 46, height: 46)
                    .position(x: 171, y: 62)
                // 左:(145,636) → (121,110)
                PTZDirectionButton(direction: .left, model: model)
                    .frame(width: 46, height: 46)
                    .position(x: 121, y: 110)
                // 中:(195,636) 直径56 → (171,110)
                Circle()
                    .fill(Color(red: 0.910, green: 0.933, blue: 0.949)) // #E8EEF2
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "camera.metering.center.weighted")
                            .font(.system(size: 17))
                            .foregroundStyle(Color(red: 0.392, green: 0.455, blue: 0.545))
                    )
                    .position(x: 171, y: 110)
                // 右:(245,636) → (221,110)
                PTZDirectionButton(direction: .right, model: model)
                    .frame(width: 46, height: 46)
                    .position(x: 221, y: 110)
                // 下:(195,684) → (171,158)
                PTZDirectionButton(direction: .down, model: model)
                    .frame(width: 46, height: 46)
                    .position(x: 171, y: 158)
            }
            .frame(width: 342, height: 190)
            .disabled(isDisabled)
        }
        .frame(width: 342, height: 190)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white)
                .shadow(color: Color(red: 0.059, green: 0.090, blue: 0.078).opacity(0.08), radius: 14, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct PTZDirectionButton: View {
    let direction: AijiaPTZDirection
    @ObservedObject var model: PlayerViewModel

    var body: some View {
        Button {
            model.controlPTZ(direction)
        } label: {
            Circle()
                .fill(Color(red: 0.941, green: 0.969, blue: 0.961)) // #F0F7F5
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: direction.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.brand)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AppTheme.card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("选择日期")
                            .font(.subheadline.weight(.semibold))
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
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
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

                        ForEach(model.recordings) { recording in
                            Button {
                                model.playRecording(recording)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(AppTheme.accent)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(timeRange(for: recording))
                                            .font(.body.monospacedDigit())
                                        Text("点击播放此片段")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                StatusText(model: model)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
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
    @ObservedObject private var library = MediaLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var previewItem: MediaItem?

    var body: some View {
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
                    ForEach(library.items) { item in
                        Button {
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
                .listStyle(.insetGrouped)
            }
        }
        .tint(theme.accent.color)
        .navigationTitle("媒体库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("完成") {
                    dismiss()
                }
            }
        }
        .sheet(item: $previewItem) { item in
            NavigationView {
                MediaPreviewView(item: item)
            }
        }
        .onAppear {
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
                Text(item.fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(rowDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var rowDetail: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateText = formatter.string(from: item.date)
        let sizeText = item.fileSizeText
        return sizeText.isEmpty ? dateText : "\(dateText) · \(sizeText)"
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
