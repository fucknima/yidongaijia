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

    /// 品牌主色(青绿)来自设计稿 #139A82
    static let brand = Color(red: 0.075, green: 0.604, blue: 0.510)
    static let brandDark = Color(red: 0.051, green: 0.498, blue: 0.439)
    static let brandSoft = Color(red: 0.925, green: 0.973, blue: 0.961) // #ECF8F5
    static let pageBackground = Color(red: 0.957, green: 0.969, blue: 0.973) // #F4F7F8
    static let fieldFill = Color(red: 0.961, green: 0.969, blue: 0.973) // #F5F7F8
    static let videoTop = Color(red: 0.145, green: 0.192, blue: 0.239) // #25313D
    static let videoMid = Color(red: 0.067, green: 0.094, blue: 0.153) // #111827
    static let videoBottom = Color(red: 0.043, green: 0.071, blue: 0.125) // #0B1220

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

    private var canLogin: Bool {
        !model.isLoading &&
        !model.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.password.isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.pageBackground
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        // 品牌区
                        VStack(spacing: 12) {
                            BrandMark()
                                .frame(width: 100, height: 100)
                            Text("爱家直连")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                            Text("移动爱家第三方 iOS 客户端")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 40)

                        // 账号登录卡片
                        VStack(spacing: 14) {
                            Text("账号登录")
                                .font(.system(size: 18, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 2)

                            fieldInput(
                                icon: "person.fill",
                                placeholder: "移动手机号"
                            ) {
                                TextField("移动手机号", text: $model.phone)
                                    .textContentType(.telephoneNumber)
                                    .keyboardType(.phonePad)
                                    .focused($focusedField, equals: .phone)
                            }

                            fieldInput(
                                icon: "lock.fill",
                                placeholder: "移动爱家密码"
                            ) {
                                SecureField("移动爱家密码", text: passwordBinding)
                                    .textContentType(.password)
                                    .focused($focusedField, equals: .password)
                            }

                            Toggle(isOn: $model.rememberLogin) {
                                Text("记住登录信息")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                            }
                            .tint(AppTheme.brand)
                            .padding(.horizontal, 2)
                            .padding(.top, 4)

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
                                        .font(.system(size: 17, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(
                                            canLogin
                                                ? AnyShapeStyle(
                                                    LinearGradient(
                                                        colors: [AppTheme.brand, AppTheme.brandDark],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                : AnyShapeStyle(Color.gray.opacity(0.5))
                                        )
                                )
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canLogin)

                            Text("密码仅保存在本机钥匙串")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.white)
                                .shadow(color: Color(red: 0.059, green: 0.090, blue: 0.078).opacity(0.08), radius: 14, y: 8)
                        )

                        // 本机直连提示
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 30, height: 30)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AppTheme.brand)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("本机直连云端")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                                Text("视频由 iPhone 本机解码，不经过中转服务器")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(AppTheme.brandSoft)
                        )

                        if !model.status.isEmpty, model.hasError {
                            StatusText(model: model)
                                .padding(.top, 2)
                        }
                    }
                    .padding(20)
                }
            }
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

    private func fieldInput<Content: View>(
        icon: String,
        placeholder: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.brandSoft)
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.brand)
            }
            content()
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.fieldFill)
        )
    }
}

/// 品牌图标:青绿渐变圆角方块 + 白色摄像头
private struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.090, green: 0.659, blue: 0.545), AppTheme.brandDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "video.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.white)
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
                AppTheme.pageBackground
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 标题行:摄像头名 + 状态
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.cameraName.isEmpty ? "我的摄像头" : model.cameraName)
                                    .font(.system(size: 23, weight: .bold))
                                    .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                                Text(model.isLoading ? "正在连接云端…" : statusSubtitle)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusPill(model: model)
                        }
                        .padding(.top, 8)

                        if model.streamURL != nil, !model.isReplay {
                            // 视频区
                            PlayerSurface(model: model) {
                                showingFullscreen = true
                            }

                            // 操作按钮:截图 / 录像 / 媒体库
                            HStack(spacing: 20) {
                                RoundMediaButton(
                                    icon: "camera.fill",
                                    title: "截图",
                                    isActive: model.isPlaying && !model.isRecording
                                ) {
                                    model.captureSnapshot()
                                }
                                RoundMediaButton(
                                    icon: model.isRecording ? "stop.fill" : "record.circle",
                                    title: model.isRecording ? "停止录像" : "录像",
                                    isActive: model.isPlaying,
                                    activeTint: model.isRecording ? .red : AppTheme.brand
                                ) {
                                    model.toggleRecording()
                                }
                                RoundMediaButton(
                                    icon: "square.grid.2x2.fill",
                                    title: "媒体库",
                                    isActive: true
                                ) {
                                    showingMediaLibrary = true
                                }
                            }
                            .padding(.horizontal, 8)

                            // 状态条
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(AppTheme.brand)
                                    .frame(width: 10, height: 10)
                                Text("直播稳定 · HEVC")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                                Spacer()
                                Button {
                                    model.stop()
                                } label: {
                                    Text("停止")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.brand)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.brandSoft)
                            )
                        } else {
                            // 未播放占位
                            VStack(spacing: 12) {
                                Image(systemName: model.hasError ? "wifi.exclamationmark" : "video")
                                    .font(.system(size: 40))
                                    .foregroundStyle(model.hasError ? .red : AppTheme.brand)
                                Text(model.isLoading ? "正在获取视频地址" : "暂时没有播放画面")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)

                                if !model.isLoading {
                                    Button("重新连接") {
                                        model.start()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(AppTheme.brand)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 56)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(.white)
                            )
                        }

                        if !model.status.isEmpty {
                            StatusText(model: model)
                        }

                        if model.isAuthenticated {
                            // 云台控制卡
                            PTZControlPanel(model: model)

                            // 内存卡回放入口卡
                            NavigationLink(
                                destination: HistoryView(model: model),
                                isActive: $showingHistory
                            ) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(AppTheme.brandSoft)
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(AppTheme.brand)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("内存卡回放")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                                        Text("按日期查看历史录像")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(.white)
                                        .shadow(color: Color(red: 0.059, green: 0.090, blue: 0.078).opacity(0.06), radius: 10, y: 4)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
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

    private var statusSubtitle: String {
        if model.isPlaying {
            return "在线 · \(model.networkSpeedText)"
        }
        if model.hasError { return "连接异常" }
        return "移动爱家摄像头"
    }
}

/// 圆形操作按钮(截图 / 录像 / 媒体库)
private struct RoundMediaButton: View {
    let icon: String
    let title: String
    var isActive: Bool = true
    var activeTint: Color = AppTheme.brand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 60, height: 60)
                        .shadow(color: Color(red: 0.059, green: 0.090, blue: 0.078).opacity(0.08), radius: 8, y: 4)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isActive ? activeTint : .gray.opacity(0.6))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? Color(red: 0.059, green: 0.090, blue: 0.078) : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!isActive)
        .accessibilityLabel(title)
    }
}

private struct StatusPill: View {
    @ObservedObject var model: PlayerViewModel

    private var color: Color {
        if model.hasError { return .red }
        if model.isLoading { return .orange }
        if model.isPlaying { return AppTheme.brand }
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
        ZStack(alignment: .topLeading) {
            IJKPlayerView(model: model)
                .id(model.playerViewID)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            // 左上:LIVE 标签 + 网速
            VStack(alignment: .leading, spacing: 6) {
                Text("LIVE")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.4)))
                Text(model.networkSpeedText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
            }
            .padding(12)

            // 右下:全屏按钮
            Button(action: onFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 34)
                    .background(Capsule().fill(Color.black.opacity(0.4)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("横屏全屏")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(12)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("云台控制")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                Spacer()
                Text("按一下移动")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                PTZDirectionButton(direction: .up, model: model)

                HStack(spacing: 10) {
                    PTZDirectionButton(direction: .left, model: model)

                    Image(systemName: "camera.metering.center.weighted")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, height: 56)

                    PTZDirectionButton(direction: .right, model: model)
                }

                PTZDirectionButton(direction: .down, model: model)
            }
            .frame(maxWidth: .infinity)
            .disabled(isDisabled)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white)
                .shadow(color: Color(red: 0.059, green: 0.090, blue: 0.078).opacity(0.06), radius: 10, y: 4)
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.brand)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(AppTheme.brandSoft)
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
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 日期选择卡
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("选择日期")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                            DatePicker(
                                "",
                                selection: $selectedDate,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(AppTheme.brand)
                            Text(formattedSelectedDate)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                        }
                        Spacer()
                        Button {
                            model.loadRecordings(for: selectedDate, force: true)
                            hasLoadedOnce = true
                        } label: {
                            HStack {
                                if model.isLoadingRecordings {
                                    ProgressView()
                                        .tint(AppTheme.brand)
                                }
                                Text("查询")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundStyle(AppTheme.brand)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(AppTheme.brandSoft))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isLoadingRecordings || !model.isAuthenticated)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.white)
                            .shadow(color: Color(red: 0.059, green: 0.090, blue: 0.078).opacity(0.06), radius: 10, y: 4)
                    )

                    if model.isReplay, model.streamURL != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("正在回放")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.4)))
                                .padding(.leading, 12)
                                .padding(.top, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .zIndex(1)
                            PlayerSurface(model: model) {
                                showingFullscreen = true
                            }
                            ReplayControls(model: model)
                            Button {
                                model.stopReplay()
                            } label: {
                                Label("停止回放", systemImage: "stop.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(.red)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(.white)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if model.isLoadingRecordings {
                        HStack {
                            ProgressView()
                            Text("正在读取内存卡录像…")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                    } else if model.recordings.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "film.stack")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text(hasLoadedOnce ? "当天没有找到录像" : "选择日期后查询内存卡录像")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("录像片段  \(model.recordings.count)")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                                .padding(.top, 4)

                            ForEach(model.recordings) { recording in
                                Button {
                                    model.playRecording(recording)
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .fill(AppTheme.brandSoft)
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(AppTheme.brand)
                                        }
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(timeRange(for: recording))
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                                            Text(durationText(for: recording))
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                                            .fill(.white)
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
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("内存卡回放")
                    .font(.system(size: 18, weight: .bold))
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    model.stopReplay()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
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

    private var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: selectedDate)
    }

    private func timeRange(for recording: AijiaRecording) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return "\(formatter.string(from: recording.startDate)) – \(formatter.string(from: recording.endDate))"
    }

    private func durationText(for recording: AijiaRecording) -> String {
        let seconds = max(0, recording.endTime - recording.startTime)
        let minutes = seconds / 60
        let remaining = seconds % 60
        return "\(minutes) 分 \(remaining) 秒"
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
    @State private var filter: MediaFilter = .all

    private enum MediaFilter: String, CaseIterable {
        case all = "全部"
        case videos = "录像"

        var title: String { rawValue }
    }

    private var filteredItems: [MediaItem] {
        switch filter {
        case .all:
            return library.items
        case .videos:
            return library.items.filter { $0.kind == .video }
        }
    }

    var body: some View {
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()

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
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        // 分段控制
                        HStack(spacing: 0) {
                            ForEach(MediaFilter.allCases, id: \.self) { item in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        filter = item
                                    }
                                } label: {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(filter == item ? AppTheme.brand : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(filter == item ? .white : .clear)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(red: 0.914, green: 0.933, blue: 0.945)) // #E9EEF1
                        )

                        if filteredItems.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "film")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                                Text("暂无录像")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(filteredItems) { item in
                                Button {
                                    previewItem = item
                                } label: {
                                    MediaLibraryCard(item: item)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        presentSystemShare(activityItems: [item.url as Any])
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

                        // 底部提示
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.brand)
                            Text("长按卡片：分享 / 删除")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppTheme.brandSoft)
                        )
                    }
                    .padding()
                }
            }
        }
        .tint(theme.accent.color)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("媒体库")
                    .font(.system(size: 18, weight: .bold))
            }
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
}

/// 媒体库卡片:左侧缩略图 + 类型/时间/大小
private struct MediaLibraryCard: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 14) {
            thumbnail
                .frame(width: 92, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.kind == .image ? "截图" : "录像")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.059, green: 0.090, blue: 0.078))
                Text(dateText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(item.fileSizeText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
                .shadow(color: Color(red: 0.059, green: 0.090, blue: 0.078).opacity(0.06), radius: 10, y: 4)
        )
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
                LinearGradient(
                    colors: [AppTheme.videoTop, AppTheme.videoBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                    .background(Circle().fill(.white.opacity(0.25)))
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
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
