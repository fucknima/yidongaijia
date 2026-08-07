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
        DiagnosticsLogger.shared.info("UI", "鏀跺埌鑷姩鎵撳紑鎽勫儚澶撮€夋嫨椤佃姹傦紝姝ｅ湪寮瑰嚭閫夋嫨椤?)
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
        case .teal: return "闈掔豢"
        case .blue: return "钃濊壊"
        case .indigo: return "闈涜摑"
        case .purple: return "绱壊"
        case .pink: return "绮夎壊"
        case .orange: return "姗欒壊"
        case .green: return "缁胯壊"
        case .red: return "绾㈣壊"
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
            DiagnosticsLogger.shared.info("UI", "鐢ㄦ埛鍒囨崲涓婚鑹?accent=\(accent.rawValue)")
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

    /// 鍝佺墝涓昏壊 #139A82(鏉ヨ嚜 Player.svg)
    static let brand = Color(red: 0.075, green: 0.604, blue: 0.510)
    /// 鍝佺墝娴呭簳 #ECF8F5
    static let brandSoft = Color(red: 0.925, green: 0.973, blue: 0.961)
    /// 鑳屾櫙 #F7F8FA
    static let pageBackground = AppTheme.pageBackground
    /// 杈撳叆/鎺т欢娴呯伆 #F5F7F8
    static let fieldFill = Color(red: 0.961, green: 0.969, blue: 0.973)
    /// 瑙嗛娓愬彉 top #25313D
    static let videoTop = Color(red: 0.145, green: 0.192, blue: 0.239)
    /// 瑙嗛娓愬彉 mid #111827
    static let videoMid = Color(red: 0.067, green: 0.094, blue: 0.153)
    /// 瑙嗛娓愬彉 bottom #0B1220
    static let videoBottom = Color(red: 0.043, green: 0.071, blue: 0.125)
    /// 娆＄骇鏂囧瓧 #64748B
    static let textSecondary = AppTheme.textSecondary
    /// 涓绘枃瀛?#0F172A
    static let textPrimary = AppTheme.textPrimary

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
                            Text("鐖卞鐩磋繛")
                                .font(.title.weight(.bold))
                            Text("鐧诲綍绉诲姩鐖卞璐﹀彿锛屾憚鍍忓ご鐢婚潰鍦ㄦ湰鏈鸿В鐮?)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 44)

                    AppTheme.card {
                        VStack(spacing: 14) {
                            TextField("绉诲姩鎵嬫満鍙?, text: $model.phone)
                                .textContentType(.telephoneNumber)
                                .keyboardType(.phonePad)
                                .focused($focusedField, equals: .phone)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                )

                            SecureField("绉诲姩鐖卞瀵嗙爜", text: passwordBinding)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                )

                            Toggle("璁颁綇鐧诲綍淇℃伅", isOn: $model.rememberLogin)
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
                                    Text(model.isLoading ? "姝ｅ湪鐧诲綍鈥? : "鐧诲綍骞舵挱鏀?)
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

                    Text("瀵嗙爜鍙繚瀛樺湪鏈満閽ュ寵涓诧紝涓嶄細涓婁紶鍒板叾浠栨湇鍔″櫒銆?)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("鐧诲綍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingAbout = true
                        } label: {
                            Label("鍏充簬", systemImage: "info.circle")
                        }
                        Button {
                            showingDiagnostics = true
                        } label: {
                            Label("璇婃柇鏃ュ織", systemImage: "doc.text.magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("鏇村鎿嶄綔")
                }
                ToolbarItem(placement: .keyboard) {
                    Button("瀹屾垚") {
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
                        Text("鏆傛棤鎽勫儚澶?)
                            .font(.headline)
                        Text("璇峰厛鐧诲綍骞惰鍙栬处鍙蜂笅鐨勬憚鍍忓ご銆?)
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
                                "鐢ㄦ埛鍦ㄧ嫭绔嬫憚鍍忓ご閫夋嫨椤甸€夋嫨璁惧 camera=\(DiagnosticsLogger.maskIdentifier(camera.macID))"
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
                Text("璇烽€夋嫨瑕佹挱鏀剧殑鎽勫儚澶?)
            }
        }
        .listStyle(.insetGrouped)
        .tint(theme.accent.color)
        .navigationTitle("閫夋嫨鎽勫儚澶?)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("杩斿洖") {
                    DiagnosticsLogger.shared.info("UI", "鐢ㄦ埛浠庣嫭绔嬫憚鍍忓ご閫夋嫨椤佃繑鍥炴挱鏀鹃〉")
                    dismiss()
                }
            }
        }
        .onAppear {
            DiagnosticsLogger.shared.info("UI", "鏄剧ず鐙珛鎽勫儚澶撮€夋嫨椤?count=\(model.cameras.count)")
        }
    }
}

private struct CameraSelectionMenuButton: View {
    @ObservedObject var model: PlayerViewModel
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            DiagnosticsLogger.shared.info("UI", "鐢ㄦ埛浠庢洿澶氭搷浣滄墦寮€鐙珛鎽勫儚澶撮€夋嫨椤?)
            isPresented = true
        } label: {
            Label("閫夋嫨鎽勫儚澶?, systemImage: "video.badge.plus")
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
                    Text("鐖卞鐩磋繛")
                        .font(.title3.weight(.bold))
                    Text("鐗堟湰 \(AppVersionInfo.display) (\(AppVersionInfo.build))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            Section("涓婚鑹?) {
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
                        .accessibilityLabel("涓婚鑹瞈(accent.title)")
                    }
                }
                .padding(.vertical, 4)
            }

            Section("椤圭洰浠嬬粛") {
                Text("鐖卞鐩磋繛鏄竴娆剧涓夋柟 iOS 瀹㈡埛绔紝鐩存帴鐧诲綍绉诲姩鐖卞浜戠锛岃鍙栬处鍙蜂笅鎽勫儚澶村苟鍦?iPhone 鏈満瑙ｇ爜鎾斁瀹炴椂涓庡唴瀛樺崱鍥炴斁瑙嗛銆?)
            }

            Section("浣滆€?) {
                HStack {
                    Text("浣滆€?)
                    Spacer()
                    Text("fucknima")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("閭")
                    Spacer()
                    Link("fucknimama@icloud.com", destination: URL(string: "mailto:fucknimama@icloud.com")!)
                        .foregroundStyle(AppTheme.accent)
                }
            }

            Section("浠撳簱鍦板潃") {
                Link("github.com/fucknima/yidongaijia", destination: URL(string: "https://github.com/fucknima/yidongaijia")!)
            }

            Section("寮€婧愯鍙?) {
                Text("鏈」鐩熀浜?MIT License 寮€婧愶紝鍏佽鑷敱浣跨敤銆佷慨鏀逛笌鍒嗗彂銆?)
                Text("Copyright 漏 2026 fucknima")
                    .foregroundStyle(.secondary)
                Link("鏌ョ湅瀹屾暣璁稿彲鍗忚", destination: URL(string: "https://github.com/fucknima/yidongaijia/blob/main/LICENSE")!)
            }

            Section("鍏嶈矗澹版槑") {
                Text("鏈」鐩槸绉诲姩鐖卞鐨勭涓夋柟 iOS 瀹㈡埛绔紝涓嶆槸涓浗绉诲姩銆佺Щ鍔ㄧ埍瀹舵垨鍏跺叧鑱斿叕鍙哥殑瀹樻柟搴旂敤銆丼DK锛屼篃涓嶄唬琛ㄤ笂杩颁换浣曚竴鏂广€傝鍙湪浣犳湁鏉冧娇鐢ㄧ殑璐﹀彿鍜屾憚鍍忓ご涓婅繍琛屻€備簯绔帴鍙ｃ€佺鍚嶈鍒欏拰鏈嶅姟绛栫暐鍙兘鍙樺寲锛涙湰椤圭洰涓嶆彁渚涙垨缁曡繃瀹樻柟鎺堟潈锛屼篃涓嶄繚璇佹帴鍙ｉ暱鏈熺ǔ瀹氥€?)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("鍏充簬")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            DiagnosticsLogger.shared.info("UI", "鏄剧ず鍏充簬椤甸潰")
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
                // 鑳屾櫙 #F7F8FA
                AppTheme.pageBackground
                    .ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // 椤堕儴:鏍囬(23pt Bold)+ 鍦ㄧ嚎鐘舵€?13pt)+ 涓や釜鍦嗛挳
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(model.cameraName.isEmpty ? "鎴戠殑鎽勫儚澶? : model.cameraName)
                                    .font(.system(size: 23, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .frame(height: 28, alignment: .bottomLeading)
                                Text(model.isLoading ? "姝ｅ湪杩炴帴浜戠鈥? : "鍦ㄧ嚎 路 \(model.networkSpeedText)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .padding(.top, 6)
                            }
                            Spacer(minLength: 0)
                            // 璁惧鍒囨崲鎸夐挳:涓績 (315,92) 鐩村緞36
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
                            // 鏇村鎸夐挳:涓績 (354,92) 鐩村緞36
                            Menu {
                                Text("鐗堟湰 \(AppVersionInfo.display)")
                                CameraSelectionMenuButton(
                                    model: model,
                                    isPresented: $showingCameraSelection
                                )
                                Button {
                                    DiagnosticsLogger.shared.info("UI", "鐢ㄦ埛鎵撳紑鍏充簬椤甸潰")
                                    showingAbout = true
                                } label: {
                                    Label("鍏充簬", systemImage: "info.circle")
                                }
                                Button {
                                    showingDiagnostics = true
                                } label: {
                                    Label("璇婃柇鏃ュ織", systemImage: "doc.text.magnifyingglass")
                                }
                                Button(role: .destructive) {
                                    model.logout()
                                } label: {
                                    Label("閫€鍑哄苟杩斿洖鐧诲綍", systemImage: "rectangle.portrait.and.arrow.right")
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

                        // 瑙嗛瀹瑰櫒:x=18 y=140 w=354 h=204 r=22
                        LiveVideoPanel(
                            model: model,
                            onFullscreen: { showingFullscreen = true }
                        )
                        .frame(width: 354, height: 204)
                        .padding(.top, 12)
                        .padding(.horizontal, 18)

                        // 涓変釜鎿嶄綔鎸夐挳:涓績 (70/182/294, 392) 鍦嗙洿寰?0
                        HStack(spacing: 0) {
                            RoundActionButton(
                                icon: "camera.fill",
                                title: "鎴浘",
                                isEnabled: model.isPlaying && !model.isRecording
                            ) {
                                model.captureSnapshot()
                            }
                            .frame(width: 112, height: 76)
                            RoundActionButton(
                                icon: model.isRecording ? "stop.fill" : "record.circle",
                                title: model.isRecording ? "鍋滄褰曞儚" : "褰曞儚",
                                isEnabled: model.isPlaying,
                                tint: model.isRecording ? .red : AppTheme.brand
                            ) {
                                model.toggleRecording()
                            }
                            .frame(width: 112, height: 76)
                            RoundActionButton(
                                icon: "square.grid.2x2.fill",
                                title: "濯掍綋搴?,
                                isEnabled: true
                            ) {
                                showingMediaLibrary = true
                            }
                            .frame(width: 112, height: 76)
                        }
                        .padding(.top, 14)

                        // 鐘舵€佹潯:x=24 y=460 w=342 h=46 r=14
                        HStack(spacing: 0) {
                            Circle()
                                .fill(AppTheme.brand)
                                .frame(width: 10, height: 10)
                                .padding(.leading, 24)
                            Text("鐩存挱绋冲畾 路 HEVC")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.leading, 14)
                            Spacer(minLength: 0)
                            Button {
                                model.stop()
                            } label: {
                                Text("鍋滄")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
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

                        // 浜戝彴鍗＄墖:x=24 y=526 w=342 h=190 r=24
                        if model.isAuthenticated {
                            PTZControlPanel(model: model)
                                .frame(width: 342, height: 190)
                                .padding(.top, 16)
                                .padding(.horizontal, 24)

                            // 鍥炴斁鍏ュ彛:x=24 y=736 w=342 h=64 r=18
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
                                        Text("鍐呭瓨鍗″洖鏀?)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .frame(height: 20, alignment: .bottomLeading)
                                        Text("鎸夋棩鏈熸煡鐪嬪巻鍙插綍鍍?)
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.textSecondary)
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

/// 瑙嗛瀹瑰櫒:x=18 y=140 w=354 h=204 r=22,娓愬彉鑳屾櫙 + LIVE 鏍囩 + 鍏ㄥ睆鎸夐挳
private struct LiveVideoPanel: View {
    @ObservedObject var model: PlayerViewModel
    let onFullscreen: () -> Void

    var body: some View {
        ZStack {
            // 娓愬彉鑳屾櫙(videoGrad)
            LinearGradient(
                colors: [
                    Color(red: 0.145, green: 0.192, blue: 0.239),  // #25313D
                    Color(red: 0.067, green: 0.094, blue: 0.153),  // #111827
                    Color(red: 0.043, green: 0.071, blue: 0.125),  // #0B1220
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // 鏈夋祦鏃跺彔鍔犳挱鏀惧櫒
            if model.streamURL != nil, !model.isReplay {
                IJKPlayerView(model: model)
                    .id(model.playerViewID)
                    .frame(width: 354, height: 204)
            }

            // LIVE 鏍囩:30,154,72,28 r=14
            Text("LIVE")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 28)
                .background(Capsule().fill(Color.black.opacity(0.4)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 14)
                .padding(.leading, 12)

            // 鍏ㄥ睆鎸夐挳:290,292,58,34 r=17
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

/// 鍦嗗舰鎿嶄綔鎸夐挳:鍦嗙洿寰?60,鏍囩 baseline y=438 14pt Semibold
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
                    .foregroundStyle(isEnabled ? AppTheme.textPrimary : .secondary)
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
        if model.hasError { return "閿欒" }
        if model.isLoading { return "杩炴帴涓? }
        if model.isPlaying { return "鐩存挱涓? }
        return "宸插仠姝?
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
            .accessibilityLabel("妯睆鍏ㄥ睆")
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
            .accessibilityLabel("閫€鍑哄叏灞?)
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
                    "灞忓箷鏂瑰悜鍒囨崲澶辫触 orientation=\(interfaceOrientations) error=\(error.localizedDescription)"
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "鏈煡"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "鏈煡"
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
            // 鏍囬:baseline y=558,17pt Bold
            HStack(alignment: .firstTextBaseline) {
                Text("浜戝彴鎺у埗")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: 0)
                Text("鎸変竴涓嬬Щ鍔?)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.leading, 18)
            .padding(.trailing, 18)
            .padding(.top, 14)
            .frame(height: 24)

            // 鏂瑰悜閿尯:鐩稿鍗＄墖鍐呭潗鏍?
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: 342, height: 190)
                // 涓?(195,588) 鐩村緞46 鈫?鍗＄墖鍐呬腑蹇?(171,62)
                PTZDirectionButton(direction: .up, model: model)
                    .frame(width: 46, height: 46)
                    .position(x: 171, y: 62)
                // 宸?(145,636) 鈫?(121,110)
                PTZDirectionButton(direction: .left, model: model)
                    .frame(width: 46, height: 46)
                    .position(x: 121, y: 110)
                // 涓?(195,636) 鐩村緞56 鈫?(171,110)
                Circle()
                    .fill(Color(red: 0.910, green: 0.933, blue: 0.949)) // #E8EEF2
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "camera.metering.center.weighted")
                            .font(.system(size: 17))
                            .foregroundStyle(AppTheme.textSecondary)
                    )
                    .position(x: 171, y: 110)
                // 鍙?(245,636) 鈫?(221,110)
                PTZDirectionButton(direction: .right, model: model)
                    .frame(width: 46, height: 46)
                    .position(x: 221, y: 110)
                // 涓?(195,684) 鈫?(171,158)
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
                .shadow(color: AppTheme.textPrimary.opacity(0.08), radius: 14, y: 8)
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
        .accessibilityLabel("浜戝彴\(direction.title)")
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
                        Text("閫夋嫨鏃ユ湡")
                            .font(.subheadline.weight(.semibold))
                        DatePicker("鏃ユ湡", selection: $selectedDate, displayedComponents: .date)

                        Button {
                            model.loadRecordings(for: selectedDate, force: true)
                            hasLoadedOnce = true
                        } label: {
                            HStack {
                                if model.isLoadingRecordings {
                                    ProgressView()
                                }
                                Text(model.isLoadingRecordings ? "姝ｅ湪鏌ヨ鈥? : "鏌ヨ鍘嗗彶褰曞儚")
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
                        Text("姝ｅ湪鍥炴斁")
                            .font(.headline)
                        PlayerSurface(model: model) {
                            showingFullscreen = true
                        }
                        ReplayControls(model: model)
                        Button(role: .destructive) {
                            model.stopReplay()
                        } label: {
                            Label("鍋滄鍥炴斁", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if model.isLoadingRecordings {
                    ProgressView("姝ｅ湪璇诲彇鍐呭瓨鍗″綍鍍忊€?)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if model.recordings.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "film.stack")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(hasLoadedOnce ? "褰撳ぉ娌℃湁鎵惧埌褰曞儚" : "閫夋嫨鏃ユ湡鍚庢煡璇㈠唴瀛樺崱褰曞儚")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("褰曞儚鐗囨锛圽(model.recordings.count)锛?)
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
                                        Text("鐐瑰嚮鎾斁姝ょ墖娈?)
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
        .navigationTitle("鍐呭瓨鍗″洖鏀?)
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
                    Label("杩斿洖", systemImage: "chevron.left")
                }
                .accessibilityLabel("杩斿洖鎾斁")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingDiagnostics = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel("璇婃柇鏃ュ織")
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
        return "\(formatter.string(from: recording.startDate)) 鈥?\(formatter.string(from: recording.endDate))"
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
                    Label("瀹炴椂璁板綍", systemImage: "dot.radiowaves.left.and.right")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accent)
                    Spacer()
                    Text("\(logger.visibleLines.count) 琛?)
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
                        Text("鏆傛椂娌℃湁璇婃柇鏃ュ織")
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
        .navigationTitle("璇婃柇鏃ュ織")
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.accent.color)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("瀹屾垚") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        logger.visibleLevels = Set(DiagnosticsLogger.Level.allCases)
                    } label: {
                        if logger.visibleLevels == Set(DiagnosticsLogger.Level.allCases) {
                            Label("鏄剧ず鍏ㄩ儴", systemImage: "checkmark")
                        } else {
                            Text("鏄剧ず鍏ㄩ儴")
                        }
                    }
                    Divider()
                    ForEach(DiagnosticsLogger.Level.allCases, id: \.self) { level in
                        Toggle(level.title, isOn: levelBinding(level))
                    }
                } label: {
                    Label("绛涢€?, systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("鏃ュ織绛夌骇绛涢€?)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        guard let url = model.prepareDiagnosticsExport() else { return }
                        diagnosticsURL = url
                        showingShareSheet = true
                    } label: {
                        Label("瀵煎嚭鏃ュ織", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        model.clearDiagnostics()
                    } label: {
                        Label("娓呴櫎鏃ュ織", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("鏃ュ織鎿嶄綔")
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
        return enabled.isEmpty ? "宸查殣钘忓叏閮ㄧ瓑绾? : "宸茬瓫閫夛細\(enabled.joined(separator: "銆?))"
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
                    Text("鏆傛棤鎴浘鎴栧綍鍍?)
                        .font(.headline)
                    Text("鍦ㄧ洿鎾敾闈㈢偣鍑绘埅鍥炬垨褰曞儚锛屽唴瀹逛細淇濆瓨鍦ㄨ繖閲屻€?)
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
                                Label("鍒犻櫎", systemImage: "trash")
                            }
                            Button {
                                presentSystemShare(activityItems: [sharePayload(for: item)])
                            } label: {
                                Label("鍒嗕韩", systemImage: "square.and.arrow.up")
                            }
                            .tint(AppTheme.accent)
                        }
                        .contextMenu {
                            Button {
                                presentSystemShare(activityItems: [sharePayload(for: item)])
                            } label: {
                                Label("鍒嗕韩", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                library.delete(item)
                            } label: {
                                Label("鍒犻櫎", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .tint(theme.accent.color)
        .navigationTitle("濯掍綋搴?)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("瀹屾垚") {
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
        return sizeText.isEmpty ? dateText : "\(dateText) 路 \(sizeText)"
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
                    Text("鏃犳硶璇诲彇鍥剧墖")
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

