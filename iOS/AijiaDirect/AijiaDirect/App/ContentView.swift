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

    /// 品牌主色 #139A82(来自 Player.svg),深浅模式通用
    static let brand = Color(red: 0.075, green: 0.604, blue: 0.510)
    /// 品牌渐变 #17A88B → #0D7F70(Login logo)
    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.090, green: 0.659, blue: 0.545), Color(red: 0.051, green: 0.498, blue: 0.439)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// 品牌浅底 #ECF8F5
    static let brandSoft = Color(red: 0.925, green: 0.973, blue: 0.961)
    /// 背景 #F7F8FA
    static let pageBackground = Color(red: 0.969, green: 0.973, blue: 0.980)
    /// 输入/控件浅灰 #F5F7F8
    static let fieldFill = Color(red: 0.961, green: 0.969, blue: 0.973)
    /// 输入/控件浅灰:浅 #F5F7F8 / 深 #202730
    static let fieldFillAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.125, green: 0.153, blue: 0.188, alpha: 1)   // #202730
                : UIColor(red: 0.961, green: 0.969, blue: 0.973, alpha: 1)   // #F5F7F8
        })
    /// 输入图标圆:浅 #E7F7F3 / 深 #1A342E
    static let inputIconFillAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.204, blue: 0.180, alpha: 1)   // #1A342E
                : UIColor(red: 0.906, green: 0.969, blue: 0.953, alpha: 1)   // #E7F7F3
        })
    /// 视频渐变 top #25313D
    static let videoTop = Color(red: 0.145, green: 0.192, blue: 0.239)
    /// 视频渐变 mid #111827
    static let videoMid = Color(red: 0.067, green: 0.094, blue: 0.153)
    /// 视频渐变 bottom #0B1220
    static let videoBottom = Color(red: 0.043, green: 0.071, blue: 0.125)
    /// 次级文字 #64748B
    static let textSecondary = Color(red: 0.392, green: 0.455, blue: 0.545)
    /// 主文字 #0F172A
    static let textPrimary = Color(red: 0.059, green: 0.090, blue: 0.078)

    // MARK: - 深色模式动态颜色

    /// 主文字:浅 #0F172A / 深 #E8EDF2
    static let textPrimaryAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.910, green: 0.929, blue: 0.949, alpha: 1)   // #E8EDF2
                : UIColor(red: 0.059, green: 0.090, blue: 0.078, alpha: 1)   // #0F172A
        })
    /// 次级文字:浅 #64748B / 深 #94A3B8
    static let textSecondaryAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.580, green: 0.639, blue: 0.722, alpha: 1)   // #94A3B8
                : UIColor(red: 0.392, green: 0.455, blue: 0.545, alpha: 1)   // #64748B
        })
    /// 页面背景:浅 #F7F8FA / 深 #101418
    static let pageBackgroundAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.063, green: 0.078, blue: 0.094, alpha: 1)   // #101418
                : UIColor(red: 0.969, green: 0.973, blue: 0.980, alpha: 1)   // #F7F8FA
        })
    /// 卡片:浅 #FFFFFF / 深 #1B222C
    static let cardFillAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.106, green: 0.133, blue: 0.173, alpha: 1)   // #1B222C
                : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
        })
    /// 品牌浅底:浅 #ECF8F5 / 深 #1A342E
    static let brandSoftAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.204, blue: 0.180, alpha: 1)   // #1A342E
                : UIColor(red: 0.925, green: 0.973, blue: 0.961, alpha: 1)   // #ECF8F5
        })
    /// 更多按钮底:浅 #EEF2F7 / 深 #262E39
    static let iconMoreFillAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.149, green: 0.180, blue: 0.224, alpha: 1)   // #262E39
                : UIColor(red: 0.933, green: 0.949, blue: 0.969, alpha: 1)   // #EEF2F7
        })
    /// 更多按钮图标:浅 #475569 / 深 #C7D2E0
    static let iconMoreFGAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.780, green: 0.824, blue: 0.878, alpha: 1)   // #C7D2E0
                : UIColor(red: 0.278, green: 0.333, blue: 0.412, alpha: 1)   // #475569
        })
    /// 云台方向按钮底:浅 #F0F7F5 / 深 #1D372F
    static let ptzDirFillAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.114, green: 0.216, blue: 0.184, alpha: 1)   // #1D372F
                : UIColor(red: 0.941, green: 0.969, blue: 0.961, alpha: 1)   // #F0F7F5
        })
    /// 云台中心按钮底:浅 #E8EEF2 / 深 #2A333D
    static let ptzMidFillAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.165, green: 0.200, blue: 0.239, alpha: 1)   // #2A333D
                : UIColor(red: 0.910, green: 0.933, blue: 0.949, alpha: 1)   // #E8EEF2
        })
    /// 分段控件底:浅 #E9EEF1 / 深 #232B34
    static let segFillAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.137, green: 0.169, blue: 0.204, alpha: 1)   // #232B34
                : UIColor(red: 0.914, green: 0.933, blue: 0.945, alpha: 1)   // #E9EEF1
        })
    /// 时间轴轨道:浅 #D9E1E6 / 深 #2B3440
    static let sliderTrackAdaptive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.169, green: 0.204, blue: 0.251, alpha: 1)   // #2B3440
                : UIColor(red: 0.851, green: 0.882, blue: 0.902, alpha: 1)   // #D9E1E6
        })
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
            ZStack {
                AppTheme.pageBackgroundAdaptive
                    .ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Logo:x=145 y=104 w=100 h=100 r=28 品牌渐变
                        ZStack {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(AppTheme.brandGradient)
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.white, lineWidth: 5)
                                    .frame(width: 50, height: 33)
                                Path { path in
                                    path.move(to: CGPoint(x: 25, y: -8.5))
                                    path.addLine(to: CGPoint(x: 41, y: -17.5))
                                    path.addLine(to: CGPoint(x: 41, y: 18.5))
                                    path.closeSubpath()
                                }
                                .fill(.white)
                            }
                            .frame(width: 50, height: 33)
                        }
                        .frame(width: 100, height: 100)
                        .padding(.top, 57)

                        // 标题:baseline y=235 30pt Bold
                        Text("爱家直连")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimaryAdaptive)
                            .frame(height: 38)
                            .padding(.top, 8)

                        // 副标题:baseline y=265 15pt
                        Text("移动爱家第三方 iOS 客户端")
                            .font(.system(size: 15))
                            .foregroundStyle(AppTheme.textSecondaryAdaptive)
                            .frame(height: 20)
                            .padding(.top, 8)

                        // 登录卡片:24,310,342,280 r=24
                        VStack(spacing: 0) {
                            // "账号登录" baseline y=342 18pt Bold
                            Text("账号登录")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimaryAdaptive)
                                .frame(width: 306, height: 22, alignment: .leading)
                                .padding(.top, 20)

                            // 手机号:42,366,306,54 r=14
                            HStack(spacing: 0) {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.inputIconFillAdaptive) // #E7F7F3 / 深色 #1A342E
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AppTheme.brand)
                                }
                                .frame(width: 30, height: 30)
                                TextField("移动手机号", text: $model.phone)
                                    .textContentType(.telephoneNumber)
                                    .keyboardType(.phonePad)
                                    .focused($focusedField, equals: .phone)
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppTheme.textPrimaryAdaptive)
                                    .tint(AppTheme.brand)
                                    .padding(.leading, 26)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.leading, 26)
                            .frame(width: 306, height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.fieldFillAdaptive)
                            )
                            .padding(.top, 22)

                            // 密码:42,432,306,54 r=14
                            HStack(spacing: 0) {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.inputIconFillAdaptive) // #E7F7F3 / 深色 #1A342E
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AppTheme.brand)
                                }
                                .frame(width: 30, height: 30)
                                SecureField("移动爱家密码", text: passwordBinding)
                                    .textContentType(.password)
                                    .focused($focusedField, equals: .password)
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppTheme.textPrimaryAdaptive)
                                    .tint(AppTheme.brand)
                                    .padding(.leading, 26)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.leading, 26)
                            .frame(width: 306, height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.fieldFillAdaptive)
                            )
                            .padding(.top, 12)

                            // 记住登录信息:baseline y=522 15pt,开关(290,503,48,28)
                            HStack(spacing: 0) {
                                Text("记住登录信息")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(AppTheme.textPrimaryAdaptive)
                                Spacer(minLength: 0)
                                Button {
                                    model.rememberLogin.toggle()
                                } label: {
                                    ZStack(alignment: model.rememberLogin ? .trailing : .leading) {
                                        Capsule()
                                            .fill(model.rememberLogin ? AppTheme.brand : Color(red: 0.851, green: 0.882, blue: 0.902))
                                            .frame(width: 48, height: 28)
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 22, height: 22)
                                            .padding(3)
                                    }
                                    .frame(width: 48, height: 28)
                                }
                                .buttonStyle(.plain)
                                .animation(.easeOut(duration: 0.15), value: model.rememberLogin)
                            }
                            .frame(width: 306)
                            .padding(.top, 24)

                            // 登录按钮:42,542,306,48 r=14
                            Button {
                                focusedField = nil
                                model.start()
                            } label: {
                                ZStack {
                                    if model.isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text("登录")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(.white)
                                        .opacity(model.isLoading ? 0 : 1)
                                }
                                .frame(width: 306, height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppTheme.brand)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(
                                model.isLoading ||
                                model.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                model.password.isEmpty
                            )
                            .padding(.top, 22)
                        }
                        .frame(width: 342, height: 280)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(AppTheme.cardFillAdaptive)
                                .shadow(color: Color(red: 0.059, green: 0.090, blue: 0.078).opacity(0.08), radius: 14, y: 8)
                        )
                        .padding(.top, 42)

                        if !model.status.isEmpty {
                            StatusText(model: model)
                                .padding(.top, 12)
                                .padding(.horizontal, 24)
                        }

                        // 安全提示:baseline y=635 13pt
                        Text("密码仅保存在本机钥匙串")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondaryAdaptive)
                            .padding(.top, 24)

                        // 本机直连提示卡:24,682,342,96 r=20
                        HStack(spacing: 0) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.cardFillAdaptive)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.brand)
                            }
                            .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("本机直连云端")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppTheme.textPrimaryAdaptive)
                                    .frame(height: 20)
                                Text("视频由 iPhone 本机解码，不经过中转服务器")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textSecondaryAdaptive)
                                    .padding(.top, 6)
                            }
                            .padding(.leading, 26)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 28)
                        .frame(width: 342, height: 96)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(AppTheme.brandSoftAdaptive)
                        )
                        .padding(.top, 20)
                    }
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        focusedField = nil
                    }
                }
            }
        }
        // 右上 ⋯ 菜单:中心 (342,80) 直径36
        .overlay(alignment: .topTrailing) {
            Menu {
                Text("版本 \(AppVersionInfo.display)")
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
                Circle()
                    .fill(AppTheme.iconMoreFillAdaptive)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.iconMoreFGAdaptive)
                    )
            }
            .padding(.top, 62)
            .padding(.trailing, 18)
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
                // 背景 #F7F8FA / 深色 #101418
                AppTheme.pageBackgroundAdaptive
                    .ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // 顶部:标题(23pt Bold)+ 在线状态(13pt)+ 两个圆钮
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(model.cameraName.isEmpty ? "我的摄像头" : model.cameraName)
                                    .font(.system(size: 23, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimaryAdaptive)
                                    .frame(height: 28, alignment: .bottomLeading)
                                Text(model.isLoading ? "正在连接云端…" : "在线 · \(model.networkSpeedText)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textSecondaryAdaptive)
                                    .padding(.top, 6)
                            }
                            Spacer(minLength: 0)
                            // 设备切换按钮:中心 (315,92) 直径36
                            Button {
                                showingCameraSelection = true
                            } label: {
                                Circle()
                                    .fill(AppTheme.brandSoftAdaptive)
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
                                    .fill(AppTheme.iconMoreFillAdaptive) // #EEF2F7 / 深色 #262E39
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(AppTheme.iconMoreFGAdaptive) // #475569 / 深色 #C7D2E0
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
                                .foregroundStyle(AppTheme.textPrimaryAdaptive)
                                .padding(.leading, 14)
                            Spacer(minLength: 0)
                            Button {
                                model.stop()
                            } label: {
                                Text("停止")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.textSecondaryAdaptive)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 22)
                        }
                        .frame(width: 342, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.brandSoftAdaptive)
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
                                            .fill(AppTheme.brandSoftAdaptive)
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(AppTheme.brand)
                                    }
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("内存卡回放")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(AppTheme.textPrimaryAdaptive)
                                            .frame(height: 20, alignment: .bottomLeading)
                                        Text("按日期查看历史录像")
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.textSecondaryAdaptive)
                                            .padding(.top, 5)
                                    }
                                    .padding(.leading, 16)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.textSecondaryAdaptive)
                                        .padding(.trailing, 20)
                                }
                                .frame(width: 342, height: 64)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(AppTheme.cardFillAdaptive)
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
                    .fill(AppTheme.cardFillAdaptive)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isEnabled ? tint : Color.gray.opacity(0.5))
                    )
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isEnabled ? AppTheme.textPrimaryAdaptive : .secondary)
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
                    .foregroundStyle(AppTheme.textPrimaryAdaptive)
                Spacer(minLength: 0)
                Text("按一下移动")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondaryAdaptive)
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
                    .fill(AppTheme.ptzMidFillAdaptive) // #E8EEF2 / 深色 #2A333D
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "camera.metering.center.weighted")
                            .font(.system(size: 17))
                            .foregroundStyle(AppTheme.textSecondaryAdaptive)
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
                .fill(AppTheme.cardFillAdaptive)
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
                .fill(AppTheme.ptzDirFillAdaptive) // #F0F7F5 / 深色 #1D372F
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
    @State private var showingDatePicker = false

    var body: some View {
        ZStack {
            AppTheme.pageBackgroundAdaptive
                .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 日期卡:24,124,342,116 r=22
                    VStack(spacing: 0) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("选择日期")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimaryAdaptive)
                                    .frame(height: 20)
                                Button {
                                    showingDatePicker = true
                                } label: {
                                    Text(formattedDate)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimaryAdaptive)
                                        .frame(height: 26, alignment: .bottomLeading)
                                        .padding(.top, 8)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("选择日期")
                            }
                            Spacer(minLength: 0)
                            // 查询按钮:274,161,72,34 r=17
                            Button {
                                model.loadRecordings(for: selectedDate, force: true)
                                hasLoadedOnce = true
                            } label: {
                                ZStack {
                                    if model.isLoadingRecordings {
                                        ProgressView()
                                            .tint(AppTheme.brand)
                                    }
                                    Text("查询")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(AppTheme.brand)
                                        .opacity(model.isLoadingRecordings ? 0 : 1)
                                }
                                .frame(width: 72, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .fill(AppTheme.brandSoftAdaptive)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isLoadingRecordings || !model.isAuthenticated)
                        }
                        .frame(width: 294, height: 56)
                        .padding(.top, 28)
                        .padding(.leading, 18)
                        .padding(.trailing, 30)
                    }
                    .frame(width: 342, height: 116)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(AppTheme.cardFillAdaptive)
                            .shadow(color: Color(red: 0.059, green: 0.090, blue: 0.078).opacity(0.08), radius: 14, y: 8)
                    )
                    .padding(.top, 36)
                    .padding(.horizontal, 24)

                    // 回放画面:24,260,342,193 r=20(仅在回放中)
                    if model.isReplay, model.streamURL != nil {
                        VStack(spacing: 0) {
                            ZStack {
                                LinearGradient(
                                    colors: [AppTheme.videoTop, AppTheme.videoMid, AppTheme.videoBottom],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                IJKPlayerView(model: model)
                                    .id(model.playerViewID)
                                    .frame(width: 342, height: 193)
                                // "正在回放" baseline y=288 12pt Bold
                                Text("正在回放")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.top, 14)
                                    .padding(.leading, 18)
                                // 播放按钮:(195,356) r=30
                                Button {
                                    model.stopReplay()
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.8))
                                            .frame(width: 60, height: 60)
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(AppTheme.textPrimary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(width: 342, height: 193)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                            // 时间:14:32:05 baseline y=481 12pt
                            HStack(spacing: 0) {
                                Text(formatClock(model.replayCurrentSecond))
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.textSecondaryAdaptive)
                                Spacer(minLength: 0)
                                Text(formatClock(model.replayDurationSecond))
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.textSecondaryAdaptive)
                            }
                            .frame(width: 330)
                            .padding(.top, 12)

                            // 时间轴:x=30 y=493 w=330 h=5 轨道 + 进度 + 圆点
                            GeometryReader { proxy in
                                let trackWidth: CGFloat = 330
                                let thumb = max(0.0, min(1.0, Double(model.replayPosition)))
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(AppTheme.sliderTrackAdaptive)
                                        .frame(width: trackWidth, height: 5)
                                    Capsule()
                                        .fill(AppTheme.brand)
                                        .frame(width: trackWidth * CGFloat(thumb), height: 5)
                                    Circle()
                                        .fill(AppTheme.brand)
                                        .frame(width: 14, height: 14)
                                        .offset(x: trackWidth * CGFloat(thumb) - 7)
                                }
                                .frame(width: 330, height: 14)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let ratio = min(max(value.location.x / 330, 0), 1)
                                            model.seekReplay(to: Double(ratio))
                                        }
                                )
                            }
                            .frame(width: 330, height: 14)
                            .padding(.top, 10)
                        }
                        .padding(.top, 20)
                        .padding(.horizontal, 24)
                    }

                    if model.isLoadingRecordings {
                        ProgressView("正在读取内存卡录像…")
                            .tint(AppTheme.brand)
                            .frame(width: 342, alignment: .center)
                            .padding(.top, 40)
                    } else if model.recordings.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "film.stack")
                                .font(.system(size: 30))
                                .foregroundStyle(AppTheme.textSecondaryAdaptive)
                            Text(hasLoadedOnce ? "当天没有找到录像" : "选择日期后查询内存卡录像")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.textSecondaryAdaptive)
                        }
                        .frame(width: 342)
                        .padding(.top, 40)
                    } else {
                        // "录像片段  12" baseline y=540 17pt Bold
                        Text("录像片段  \(model.recordings.count)")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimaryAdaptive)
                            .frame(width: 342, height: 22, alignment: .leading)
                            .padding(.top, 28)

                        // 录像行:24,562 起 342×68 r=17,步进 82
                        VStack(spacing: 14) {
                            ForEach(model.recordings) { recording in
                                Button {
                                    model.playRecording(recording)
                                } label: {
                                    HStack(spacing: 0) {
                                        ZStack {
                                            Circle()
                                                .fill(AppTheme.brandSoftAdaptive)
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(AppTheme.brand)
                                        }
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(timeRange(for: recording))
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(AppTheme.textPrimaryAdaptive)
                                                .frame(height: 20, alignment: .bottomLeading)
                                            Text(durationText(for: recording))
                                                .font(.system(size: 12))
                                                .foregroundStyle(AppTheme.textSecondaryAdaptive)
                                                .padding(.top, 6)
                                        }
                                        .padding(.leading, 32)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppTheme.textSecondaryAdaptive)
                                            .padding(.trailing, 20)
                                    }
                                    .frame(width: 342, height: 68)
                                    .background(
                                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                                            .fill(AppTheme.cardFillAdaptive)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 14)
                    }

                    if !model.status.isEmpty {
                        StatusText(model: model)
                            .padding(.top, 12)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
        // 返回 ‹:x=26 baseline y=88 30pt
        .overlay(alignment: .topLeading) {
            Button {
                model.stopReplay()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimaryAdaptive)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .padding(.top, 50)
            .padding(.leading, 8)
            .contextMenu {
                Button {
                    showingDiagnostics = true
                } label: {
                    Label("诊断日志", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        // 标题"内存卡回放" x=195 baseline y=88 18pt Bold
        .overlay(alignment: .top) {
            Text("内存卡回放")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.textPrimaryAdaptive)
                .frame(width: 200, height: 40)
                .padding(.top, 52)
        }
        .onAppear {
            model.setHistoryVisible(true)
            guard !hasLoadedOnce, model.isAuthenticated else { return }
            hasLoadedOnce = true
            model.loadRecordings(for: selectedDate)
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationView {
                VStack(spacing: 0) {
                    DatePicker(
                        "选择日期",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(AppTheme.brand)
                    .padding(20)
                    Button("确定") {
                        showingDatePicker = false
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 306, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.brand)
                    )
                    .padding(.bottom, 24)
                }
                .navigationTitle("选择日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") {
                            showingDatePicker = false
                        }
                    }
                }
            }
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

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: selectedDate)
    }

    private func formatClock(_ seconds: Int64) -> String {
        guard seconds >= 0 else { return "00:00:00" }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remaining = seconds % 60
        return String(format: "%02lld:%02lld:%02lld", hours, minutes, remaining)
    }

    private func durationText(for recording: AijiaRecording) -> String {
        let seconds = max(0, recording.endTime - recording.startTime)
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes) 分 \(remainder) 秒"
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
        case video = "录像"
    }

    private var visibleItems: [MediaItem] {
        switch filter {
        case .all: return library.items
        case .video: return library.items.filter { $0.kind == .video }
        }
    }

    var body: some View {
        ZStack {
            AppTheme.pageBackgroundAdaptive
                .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 分段控件:24,120,342,42 r=12;选中块:28,124,164,34 r=10
                    HStack(spacing: 0) {
                        ForEach(MediaFilter.allCases, id: \.self) { f in
                            Button {
                                filter = f
                            } label: {
                                Text(f.rawValue)
                                    .font(.system(size: 14, weight: f == filter ? .bold : .semibold))
                                    .foregroundStyle(f == filter ? AppTheme.textPrimaryAdaptive : AppTheme.textSecondaryAdaptive)
                                    .frame(width: 164, height: 34)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(f == filter ? AppTheme.cardFillAdaptive : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .animation(.easeOut(duration: 0.15), value: filter)
                        }
                    }
                    .frame(width: 342, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.segFillAdaptive)
                    )
                    .padding(.top, 32)
                    .padding(.horizontal, 24)

                    if visibleItems.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 30))
                                .foregroundStyle(AppTheme.textSecondaryAdaptive)
                            Text("暂无截图或录像")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimaryAdaptive)
                            Text("在直播画面点击截图或录像，内容会保存在这里。")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textSecondaryAdaptive)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 342)
                        .padding(.top, 60)
                    } else {
                        // 媒体卡:24,184 起 342×110 r=20,步进 128
                        VStack(spacing: 18) {
                            ForEach(visibleItems) { item in
                                Button {
                                    previewItem = item
                                } label: {
                                    MediaLibraryCard(item: item)
                                }
                                .buttonStyle(.plain)
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
                        .padding(.top, 24)
                        .padding(.horizontal, 24)
                    }

                    // 底部提示:24,720,342,72 r=18
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("左滑：分享 / 删除")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimaryAdaptive)
                                .frame(height: 18, alignment: .bottomLeading)
                            Text("保留现有本机文件管理逻辑")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textSecondaryAdaptive)
                                .padding(.top, 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 18)
                    .frame(width: 342, height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppTheme.brandSoftAdaptive)
                    )
                    .padding(.top, 24)
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
        // "完成" x=26 baseline y=88 15pt Semibold
        .overlay(alignment: .topLeading) {
            Button("完成") {
                dismiss()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimaryAdaptive)
            .frame(width: 60, height: 40)
            .padding(.top, 50)
            .padding(.leading, 8)
        }
        // 标题"媒体库" x=195 baseline y=88 18pt Bold
        .overlay(alignment: .top) {
            Text("媒体库")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.textPrimaryAdaptive)
                .frame(width: 200, height: 40)
                .padding(.top, 52)
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

/// 媒体卡片:x=24 w=342 h=110 r=20,缩略图 w=92 h=82 r=15
private struct MediaLibraryCard: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 0) {
            thumbnail
                .frame(width: 92, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(item.kind == .image ? "截图" : "录像")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimaryAdaptive)
                    .frame(height: 20, alignment: .bottomLeading)
                Text(dateText)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondaryAdaptive)
                    .padding(.top, 10)
                Text(item.fileSizeText)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondaryAdaptive)
                    .padding(.top, 4)
            }
            .padding(.leading, 18)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondaryAdaptive)
                .padding(.trailing, 20)
        }
        .frame(width: 342, height: 110)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.cardFillAdaptive)
                .shadow(color: Color(red: 0.059, green: 0.090, blue: 0.078).opacity(0.08), radius: 14, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                    colors: [AppTheme.videoTop, AppTheme.videoMid, AppTheme.videoBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(AppTheme.fieldFillAdaptive)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(AppTheme.textSecondaryAdaptive)
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
