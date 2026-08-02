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
        case verificationCode
        case camera
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("鐖卞鐩磋繛")
                            .font(.largeTitle.weight(.bold))
                        Text("鐧诲綍鍚庣洿鎺ユ煡鐪嬫憚鍍忓ご锛岃棰戝湪鏈満瑙ｇ爜銆?)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox {
                        VStack(spacing: 14) {
                            TextField("绉诲姩鎵嬫満鍙?, text: $model.phone)
                                .textContentType(.telephoneNumber)
                                .keyboardType(.phonePad)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .phone)

                            Picker("鐧诲綍鏂瑰紡", selection: $model.loginMethod) {
                                ForEach(AijiaLoginMethod.allCases) { method in
                                    Text(method.title).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)

                            if model.loginMethod == .password {
                                SecureField("绉诲姩鐖卞瀵嗙爜", text: $model.password)
                                    .textContentType(.password)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .password)
                            } else {
                                HStack(spacing: 8) {
                                    TextField("鐭俊楠岃瘉鐮?, text: $model.verificationCode)
                                        .textContentType(.oneTimeCode)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                        .focused($focusedField, equals: .verificationCode)

                                    Button {
                                        focusedField = nil
                                        model.requestVerificationCode()
                                    } label: {
                                        Text(
                                            model.isSendingVerificationCode
                                                ? "鍙戦€佷腑鈥?
                                                : model.verificationCountdown > 0
                                                    ? "\(model.verificationCountdown)s"
                                                    : "鑾峰彇楠岃瘉鐮?
                                        )
                                        .frame(minWidth: 82)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(
                                        model.isSendingVerificationCode ||
                                        model.verificationCountdown > 0 ||
                                        model.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    )
                                }
                            }

                            TextField("mac_id 鎴栨憚鍍忓ご鍚嶇О锛堝彲閫夛級", text: $model.cameraSelector)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .camera)

                            if model.loginMethod == .password {
                                Toggle("璁颁綇鐧诲綍淇℃伅", isOn: $model.rememberLogin)
                                    .font(.subheadline)
                            } else {
                                Text("鐭俊楠岃瘉鐮佷粎鐢ㄤ簬鏈鐧诲綍锛屼笉浼氫繚瀛樸€?)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                focusedField = nil
                                model.start()
                            } label: {
                                HStack {
                                    if model.isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(
                                        model.isLoading
                                            ? "姝ｅ湪鐧诲綍鈥?
                                            : model.loginMethod == .password
                                                ? "鐧诲綍骞舵挱鏀?
                                                : "楠岃瘉鐮佺櫥褰曞苟鎾斁"
                                    )
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                model.isLoading ||
                                model.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                (model.loginMethod == .password
                                    ? model.password.isEmpty
                                    : model.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            )
                        }
                    }

                    if !model.status.isEmpty {
                        StatusText(model: model)
                    }

                    Text(
                        model.loginMethod == .password
                            ? "瀵嗙爜鍙繚瀛樺湪鏈満閽ュ寵涓诧紝涓嶄細涓婁紶鍒板叾浠栨湇鍔″櫒銆?
                            : "楠岃瘉鐮佺櫥褰曚娇鐢ㄥ畼鏂圭煭淇￠獙璇佹湇鍔★紝楠岃瘉鐮佷笉浼氬啓鍏ユ棩蹇楁垨淇濆瓨鍦ㄦ湰鏈恒€?
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("鐧诲綍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: DiagnosticsView(model: model)) {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel("璇婃柇鏃ュ織")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: UpdateLogView()) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .accessibilityLabel("鏇存柊鏃ュ織")
                }
                ToolbarItem(placement: .keyboard) {
                    Button("瀹屾垚") {
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

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.cameraName.isEmpty ? "鎴戠殑鎽勫儚澶? : model.cameraName)
                                .font(.title2.weight(.semibold))
                            Text(model.isLoading ? "姝ｅ湪杩炴帴浜戠鈥? : "绉诲姩鐖卞鎽勫儚澶?)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle()
                            .fill(model.hasError ? Color.red : (model.isLoading ? Color.orange : Color.green))
                            .frame(width: 10, height: 10)
                    }

                    // HistoryView owns the replay player. Do not keep a
                    // second VLCPlayerView alive behind it.
                    if model.streamURL != nil && !model.isReplay {
                        VLCPlayerView(model: model)
                            .id(model.playerViewID)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        Button(role: .destructive) {
                            model.stop()
                        } label: {
                            Label(model.isReplay ? "鍋滄鍥炴斁" : "鍋滄鎾斁", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: model.hasError ? "wifi.exclamationmark" : "video")
                                .font(.system(size: 42))
                                .foregroundStyle(model.hasError ? .red : .secondary)
                            Text(model.isLoading ? "姝ｅ湪鑾峰彇瑙嗛鍦板潃" : "鏆傛椂娌℃湁鎾斁鐢婚潰")
                                .foregroundStyle(.secondary)

                            if !model.isLoading {
                                Button("閲嶆柊杩炴帴") {
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
                            Label("鍐呭瓨鍗″洖鏀?, systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("鎾斁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingDiagnostics = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel("璇婃柇鏃ュ織")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: UpdateLogView()) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .accessibilityLabel("鏇存柊鏃ュ織")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Text("鐗堟湰 \(AppVersionInfo.display)")
                        Button(role: .destructive) {
                            model.logout()
                        } label: {
                            Label("閫€鍑哄苟杩斿洖鐧诲綍", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("鏇村鎿嶄綔")
                }
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            NavigationView {
                DiagnosticsView(model: model)
            }
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "鏈煡"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "鏈煡"
    }
}

private enum ReleaseNotesCatalog {
    static let all: [ReleaseNote] = [
        ReleaseNote(
            version: "楠岃瘉鐮佺櫥褰曚慨澶?,
            date: "2026-08-02",
            title: "鐭俊楠岃瘉鐮佷細璇濇祦绋?,
            details: [
                "鎸夊畼鏂规櫘閫氱櫥褰曟祦绋嬭皟鐢?authentication/sendMsg锛屽苟琛ラ綈鎵嬫満鍙枫€佽澶囧搧鐗屽拰鏈哄瀷瀛楁銆?,
                "鎸夊畼鏂瑰疄鐜颁娇鐢?AES-128-ECB/PKCS7 鍔犲瘑鐭俊鐧诲綍鎵嬫満鍙枫€?,
                "琛ラ綈 IDMP AppID銆乻ourceId銆佽澶囨爣璇嗐€佸湴鍖哄弬鏁板拰 UNIAUTH_PASSWORD 鐧诲綍瀛楁銆?,
                "鍙戦€侀獙璇佺爜鍚庡鐢ㄥ悓涓€缃戠粶浼氳瘽鍜?Cookie 鐧诲綍锛岄伩鍏?session 鏍￠獙澶辫触銆?,
                "楠岃瘉鐮佷笉浼氫繚瀛樺埌閽ュ寵涓诧紝涔熶笉浼氬啓鍏ヨ瘖鏂棩蹇椼€?
            ]
        ),
        ReleaseNote(
            version: "鍥炴斁璇婃柇淇",
            date: "2026-08-02",
            title: "鍥炴斁璇婃柇闅旂涓庢煡璇㈠幓閲?,
            details: [
                "璇婃柇鏃ュ織鏀逛负鐙珛寮圭獥锛屼笉鍐嶉€氳繃鍥炴斁瀵艰埅鏍堟帹鍏ラ〉闈€?,
                "鎵撳紑銆佸埛鏂板拰鍏抽棴璇婃柇椤典笉浼氬仠姝㈡垨閲嶅缓褰撳墠鍥炴斁鎾斁鍣ㄣ€?,
                "鍥炴斁鏈熼棿蹇界暐椤甸潰鐢熷懡鍛ㄦ湡瑙﹀彂鐨勮嚜鍔ㄥ巻鍙插綍鍍忔煡璇紝閬垮厤閲嶅璇锋眰鍜屾棩蹇楀埛灞忋€?,
                "淇濈暀鎵嬪姩鏌ヨ鍘嗗彶褰曞儚鍔熻兘锛屽苟寤堕暱閲嶅鏌ヨ淇濇姢鏃堕棿銆?
            ]
        ),
        ReleaseNote(
            version: "1.1",
            date: "2026-08-02",
            title: "鍥炴斁涓庤瘖鏂鑸慨澶?,
            details: [
                "淇鍐呭瓨鍗″洖鏀炬椂鎵撳紑璇婃柇椤典細璇仠姝㈠洖鏀惧苟杩斿洖鎾斁椤点€?,
                "鍙湁鏄庣‘杩斿洖鎾斁椤垫垨鐐瑰嚮鍋滄鍥炴斁锛屾墠浼氱粨鏉熷洖鏀句細璇濄€?,
                "淇鍥炴斁椤甸潰瀵艰埅杩囩▼涓殑鎾斁鍣ㄩ噴鏀鹃棶棰樸€?,
                "淇閫€鍑虹櫥褰曞悗閲嶅惎 App 浠嶈嚜鍔ㄨ繘鍏ユ挱鏀鹃〉鐨勯棶棰樸€?,
                "鏂板鐭俊楠岃瘉鐮佺櫥褰曪紝鏀寔鑾峰彇楠岃瘉鐮併€佸€掕鏃跺拰楠岃瘉鐮佺櫥褰曘€?,
                "楠岃瘉鐮佷粎鐢ㄤ簬褰撳墠鐧诲綍锛屼笉浼氫繚瀛樻垨鍐欏叆璇婃柇鏃ュ織銆?,
                "鏋勫缓鐗堟湰鏀逛负姣忔 GitHub Actions 鏋勫缓鑷姩閫掑 0.1銆?
            ]
        ),
        ReleaseNote(
            version: "鍘嗗彶鏋勫缓 speedfix",
            date: "2026-08-02",
            title: "鍥炴斁鍊嶉€熶笌鎾斁鍣ㄧ姸鎬佷慨澶?,
            details: [
                "淇鍊嶉€熻缃鎾斁鍣ㄥ洖璋冭鐩栫殑闂銆?,
                "鍥炴斁鍒囨崲銆佹嫋鍔ㄨ繘搴﹀拰鎾斁鍣ㄩ噸寤烘椂閲嶆柊搴旂敤鍊嶉€熴€?,
                "闄嶄綆鎾斁鍣ㄨ鍥炬洿鏂板鍥炴斁杩涘害鐨勫共鎵般€?
            ]
        ),
        ReleaseNote(
            version: "鍘嗗彶鏋勫缓 replaydiagfix",
            date: "2026-08-02",
            title: "鍥炴斁杩涘害涓庤瘖鏂ǔ瀹氭€т慨澶?,
            details: [
                "闄愬埗鍘嗗彶褰曞儚鏌ヨ閲嶅璇锋眰锛岄伩鍏嶈瘖鏂〉闈㈠嚭鐜板ぇ閲忔棩蹇椼€?,
                "蹇界暐杩囨湡鎾斁鍣ㄥ拰鏃у洖鏀句换鍔＄殑杩涘害鍥炶皟銆?,
                "淇鎷栧姩杩涘害鍚庢挱鏀惧櫒榛戝睆銆佸洖鏀剧姸鎬佷笉鍚屾鍜屼細璇濊繃鏈熼噸璇曢棶棰樸€?
            ]
        ),
        ReleaseNote(
            version: "鍘嗗彶鏋勫缓 v23鈥搗24",
            date: "2026-08-02",
            title: "鍘嗗彶鍥炴斁浜や簰淇",
            details: [
                "鎸夊綍鍍忕墖娈佃捣鐐硅姹傚巻鍙插湴鍧€锛岄伩鍏嶇偣鍑诲綋澶╁洖鏀句粠閿欒鏃堕棿寮€濮嬨€?,
                "澧炲姞鏈嶅姟鍣ㄥ洖鏀惧畾浣嶅拰鎷栧姩杩涘害鐨勬仮澶嶉€昏緫銆?,
                "淇鍥炴斁缁撴潫鍒囧洖鐩存挱鍚庨〉闈㈢姸鎬佸悎骞躲€侀粦灞忓拰鏃犵敾闈㈡彁绀洪棶棰樸€?
            ]
        ),
        ReleaseNote(
            version: "鍘嗗彶鏋勫缓 v21鈥搗22",
            date: "2026-08-02",
            title: "鏃ュ織銆佹枃浠惰闂笌鍓嶅悗鍙颁慨澶?,
            details: [
                "鏀寔瀵煎嚭璇婃柇鏃ュ織锛屽苟鍏佽浠?iPhone 鏂囦欢 App 璁块棶銆?,
                "淇鍥炴斁鍒囨崲鍚庡彴鍐嶅洖鏉ュ悗鍙墿澹伴煶鎴栬鍥句涪澶便€?,
                "澧炲姞鍥炴斁鎾斁鍣ㄥ湪鍓嶅悗鍙板垏鎹㈡椂鐨勬仮澶嶅拰鏃у湴鍧€娓呯悊銆?
            ]
        ),
        ReleaseNote(
            version: "鍘嗗彶鏋勫缓 v19鈥搗20",
            date: "2026-08-02",
        …937 tokens truncated…ote(
            version: "鍘嗗彶鏋勫缓 v3鈥搗4",
            date: "2026-08-02",
            title: "鐩磋繛鎾斁鍩虹鐗?,
            details: [
                "鎵嬫満鐩存帴鐧诲綍绉诲姩鐖卞浜戠锛屼笉缁忚繃涓浆鏈嶅姟鍣ㄣ€?,
                "鑾峰彇瀹炴椂鍦板潃骞跺湪 iPhone 鏈満鐢?MobileVLCKit 瑙ｇ爜鎾斁銆?,
                "鏀寔璐﹀彿涓嬫憚鍍忓ご鍒楄〃鍜屽彲閫夋憚鍍忓ご鍚嶇О/mac_id銆?
            ]
        ),
        ReleaseNote(
            version: "1.0",
            date: "2026-08-02",
            title: "棣栦釜鍙敤鐗堟湰",
            details: [
                "鏁村悎鐧诲綍銆佸疄鏃舵挱鏀俱€佷簯鍙般€佸唴瀛樺崱鍥炴斁鍜岃瘖鏂棩蹇楀姛鑳姐€?,
                "瀵嗙爜淇濆瓨鍒?iOS 閽ュ寵涓诧紝璇婃柇鏃ュ織鏀寔鏂囦欢璁块棶銆?
            ]
        )
    ]
}

private struct UpdateLogView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Label("褰撳墠鐗堟湰", systemImage: "app.badge")
                    Spacer()
                    Text("\(AppVersionInfo.display) (\(AppVersionInfo.build))")
                        .foregroundStyle(.secondary)
                        .font(.subheadline.monospacedDigit())
                }
            }

            Section("淇璁板綍") {
                ForEach(ReleaseNotesCatalog.all) { note in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(note.version.hasPrefix("鍘嗗彶") ? note.version : "鐗堟湰 \(note.version)")
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
        .navigationTitle("鏇存柊鏃ュ織")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReplayControls: View {
    @ObservedObject var model: PlayerViewModel
    @State private var sliderValue = 0.0
    @State private var isEditing = false

    private let rates: [Float] = [0.5, 1.0, 2.0, 3.0, 5.0]

    var body: some View {
        GroupBox {
            VStack(spacing: 8) {
                HStack {
                    Text(formatTime(model.replayCurrentSecond))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(model.replayDurationSecond))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ReplaySeekBar(
                    value: $sliderValue,
                    enabled: !model.isLoading && model.replayDurationSecond > 0,
                    onCommit: { value in
                        model.seekReplay(to: value)
                    },
                    onEditingChanged: { editing in
                        if editing {
                            sliderValue = Double(model.replayPosition)
                        }
                        isEditing = editing
                    }
                )

                HStack {
                    Label("鍐呭瓨鍗″洖鏀?, systemImage: "play.rectangle")
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
        .onAppear {
            sliderValue = Double(model.replayPosition)
        }
        .onChange(of: model.replayPosition) { value in
            if !isEditing {
                sliderValue = Double(value)
            }
        }
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

private struct ReplaySeekBar: View {
    @Binding var value: Double
    let enabled: Bool
    let onCommit: (Double) -> Void
    let onEditingChanged: (Bool) -> Void
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = max(0.0, min(1.0, value))
            let thumbDiameter: CGFloat = 22
            let thumbX = min(max(0, width * progress - thumbDiameter / 2), max(0, width - thumbDiameter))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 6)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, width * progress), height: 6)

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: thumbX)
            }
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard enabled else { return }
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        value = max(0.0, min(1.0, gesture.location.x / width))
                    }
                    .onEnded { gesture in
                        guard enabled else { return }
                        value = max(0.0, min(1.0, gesture.location.x / width))
                        onCommit(value)
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 32)
        .opacity(enabled ? 1 : 0.45)
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
                Text("浜戝彴鎺у埗")
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
        .accessibilityLabel("浜戝彴\(direction.title)")
    }
}

private struct HistoryView: View {
    @ObservedObject var model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var hasLoadedOnce = false
    @State private var showingDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
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
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isLoadingRecordings || !model.isAuthenticated)
                    }
                }

                if model.isReplay, model.streamURL != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("姝ｅ湪鍥炴斁")
                            .font(.headline)
                        VLCPlayerView(model: model)
                            .id(model.playerViewID)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
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
                    Text(hasLoadedOnce ? "褰撳ぉ娌℃湁鎵惧埌褰曞儚" : "閫夋嫨鏃ユ湡鍚庢煡璇㈠唴瀛樺崱褰曞儚")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("褰曞儚鐗囨锛圽(model.recordings.count)锛?)
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
                                        Text("鐐瑰嚮鎾斁姝ょ墖娈?)
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
            guard !hasLoadedOnce, model.isAuthenticated else { return }
            hasLoadedOnce = true
            model.loadRecordings(for: selectedDate)
        }
        .sheet(isPresented: $showingDiagnostics) {
            NavigationView {
                DiagnosticsView(model: model)
            }
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
    @State private var diagnosticsURL: URL?
    @State private var showingShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("瀹炴椂璁板綍", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                Spacer()
                Text("\(logger.visibleLines.count) 琛?)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("瀹屾垚") {
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

