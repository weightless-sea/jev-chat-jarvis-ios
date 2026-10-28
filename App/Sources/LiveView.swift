import SwiftUI
import ReplayKit
import PhotosUI
import UIKit

// MARK: - 直播模式
//
// 与剪贴板路径的差别只在「输入」：不再长按复制，而是广播扩展持续录屏 + 本地 OCR，
// 把「对方最新一条 + 前文」自动喂给同一条 JevPipeline。
// 本页职责：① 放系统的广播开始按钮；② 实时展示识别结果；③ 前台时自动分析；
// ④ 自检（合成/相册截图走同一条 OCR 路径，不开广播也能验证识别质量）。

struct LiveView: View {
    @EnvironmentObject private var store: ConfigStore

    private func L(_ zh: String, _ en: String) -> String {
        jevLocalized(store.language, zh: zh, en: en)
    }

    @State private var snapshot: LiveSnapshot?
    /// 默认关：隐私口径（README/审核话术）承诺「只有你触发分析时文本才出设备」，
    /// 自动分析是显式 opt-in，避免默认静默把 OCR 文本发往模型端点烧 token。
    @State private var autoAnalyze = false
    @State private var analysis: Analysis?
    @State private var analyzing = false
    @State private var lastAnalyzed = ""
    @State private var notice: String?

    // 自检
    @State private var debugLines: [LiveLine] = []
    @State private var debugImage: UIImage?
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        NavigationView {
            Form {
                listenSection
                if let snap = snapshot, JevLiveStore.isFresh(snap) {
                    conversationSection(snap)
                }
                suggestSection
                selfTestSection
            }
            .navigationTitle(L("直播", "Live"))
            .navigationViewStyle(.stack)
            .onAppear { JevLiveStore.setAppLiveVisible(true) }
            .onDisappear { JevLiveStore.setAppLiveVisible(false) }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                tick()
            }
            .onChange(of: pickedItem) { item in
                // 相册自检：选中的截图走与广播扩展同一条识别+解析路径。
                // loadTransferable 偶发返回 nil（iCloud 未下载等），如实提示，不给假结果。
                guard let item else { return }
                Task { @MainActor in
                    defer { pickedItem = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let img = UIImage(data: data), let cg = img.cgImage else {
                        notice = L("这张图读不出来，换一张试试。", "Couldn't read that image; try another one.")
                        return
                    }
                    debugImage = img
                    debugLines = LiveOCREngine.recognize(cgImage: cg)
                }
            }
        }
    }

    // MARK: 监听

    private var listenSection: some View {
        Section {
            HStack {
                Image(systemName: JevLiveStore.isActionable ? "dot.radiowaves.left.and.right" : "circle.dashed")
                    .foregroundColor(isLive ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLive ? L("监听中", "Listening") : L("未在监听", "Not listening"))
                        .font(.callout.weight(.semibold))
                    if let snap = snapshot, isLive {
                        Text(snap.frameCount == 0
                             ? L("广播已启动 · 等待第一帧识别…", "Broadcast started · waiting for the first frame…")
                             : L("画面变化 \(snap.changedAt.formatted(date: .omitted, time: .standard)) · 已识别 \(snap.frameCount) 帧",
                                 "Last change \(snap.changedAt.formatted(date: .omitted, time: .standard)) · \(snap.frameCount) frames read"))
                            .font(.caption2).foregroundColor(.secondary)
                    } else {
                        Text(L("点下面按钮 → 选「Jev 直播」→ 开始广播",
                               "Tap the button below → pick \"Jev Live\" → Start Broadcast"))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            // 系统广播按钮：点它弹系统面板（列出本 App 的广播扩展），这一步必须真人点。
            // 两条 2026-09/10 排查定案，写死在这里防止后人再查一遍：
            //   · 模拟器上面板永远不弹——系统不支持广播扩展，只有真机能走通；
            //   · iOS 26 起合成事件（XCUITest 坐标点击/无障碍激活/私有 buttonPressed:）
            //     不触发系统面板，必须真实用户触摸。自动化只能断言到「按钮存在」为止。
            BroadcastPickerView()
                .frame(width: 64, height: 44)
                .frame(maxWidth: .infinity)
            Text(L("开始后切到任意聊天 App，这里会持续识别屏幕上的对话（每 2 秒一次，纯本地 OCR，只有拿去生成回复的对话文本会发给你自己配的模型）。状态栏会出现系统的紫色录屏指示，停止就在控制中心或回到这里点按钮。",
                   "After starting, switch to any chat app. This page keeps reading the conversation on screen (every 2 s, on-device OCR only; only the text you send for a reply goes to the model you configured). iOS shows the purple recording indicator the whole time — stop from Control Center or tap the button again here."))
                .font(.caption).foregroundColor(.secondary)
        } header: {
            Text(L("屏幕监听", "Screen listening"))
        }
    }

    private var isLive: Bool {
        guard let snap = snapshot else { return false }
        return JevLiveStore.isFresh(snap)
    }

    // MARK: 实时对话

    private func conversationSection(_ snap: LiveSnapshot) -> some View {
        Section {
            if snap.lines.isEmpty {
                // 会话门控：非聊天画面只发心跳、不产生识别内容（README/LIVE_MODE 有说明）
                Text(L("当前画面不像聊天界面，不产生识别内容；切回聊天自动恢复。",
                       "This screen doesn't look like a chat, so nothing is recognized. Switch back to a chat to resume."))
                    .font(.caption).foregroundColor(.secondary)
            }
            ForEach(Array(snap.lines.suffix(8).enumerated()), id: \.offset) { _, line in
                HStack {
                    if line.side == .me { Spacer(minLength: 40) }
                    Text(line.text)
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(bubbleColor(line.side))
                        .foregroundColor(line.side == .system ? .secondary : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    if line.side != .me { Spacer(minLength: 40) }
                }
            }
            if let latest = snap.latestIncoming {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill").font(.caption).foregroundColor(.accentColor)
                    Text(L("待回：\(latest)", "To reply: \(latest)"))
                        .font(.callout.weight(.medium)).lineLimit(3)
                }
            }
        } header: {
            Text(L("识别结果", "Recognized"))
        }
    }

    private func bubbleColor(_ side: LiveLine.Side) -> Color {
        switch side {
        case .me: return Color.accentColor.opacity(0.15)
        case .them: return Color(.secondarySystemBackground)
        case .system: return .clear
        }
    }

    // MARK: 建议

    private var suggestSection: some View {
        Section {
            Toggle(L("对方有新消息时自动分析", "Auto-analyze when they send new messages"), isOn: $autoAnalyze)
            if analyzing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L("生成中…", "Generating…")).font(.callout).foregroundColor(.secondary)
                }
            }
            if let a = analysis {
                ForEach(a.candidates) { c in
                    Button {
                        UIPasteboard.general.string = c.text
                        notice = L("已复制「\(c.tone)」候选，去输入框粘贴发送",
                                   "Copied the \"\(c.tone)\" suggestion. Paste it in the chat to send")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.text).font(.callout).foregroundColor(.primary)
                            Text(c.tone + (c.prob.map { String(format: " · %.0f%%", $0 * 100) } ?? ""))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if !a.notices.isEmpty {
                    Text(a.notices.joined(separator: "；")).font(.caption).foregroundColor(.orange)
                }
            }
            if let notice {
                Text(notice).font(.caption).foregroundColor(.secondary)
            }
        } header: {
            Text(L("建议", "Suggestions"))
        } footer: {
            Text(L("自动分析默认关闭、且只在 App 前台时运行；锁屏或切走后由键盘接管——切到 Jev 键盘点「读屏幕分析」即可，同样免复制。",
                   "Auto-analyze is off by default and runs only while the app is in the foreground; otherwise the keyboard takes over — switch to the Jev keyboard and tap \"Read screen\"."))
        }
    }

    // MARK: 自检

    private var selfTestSection: some View {
        Section {
            Button {
                let img = LiveDebugFixtures.makeFakeChat()
                debugImage = img
                debugLines = LiveOCREngine.recognize(cgImage: img.cgImage!)
            } label: {
                Label(L("合成示例截图自检", "Self-test with a synthetic screenshot"), systemImage: "photo.artframe")
            }
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Label(L("从相册选聊天截图识别", "Pick a chat screenshot from Photos"), systemImage: "photo.on.rectangle")
            }
            if let debugImage {
                // 把喂给 OCR 的原图摆出来，和下面的识别结果对照看左右归属/清洗对不对
                Image(uiImage: debugImage)
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 240)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("debugImage")
            }
            if !debugLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(debugLines.enumerated()), id: \.offset) { _, line in
                        Text("\(tag(line.side)) \(line.text)").font(.caption).monospaced()
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(L("自检（不开启广播也能验证 OCR）", "Self-test (validates OCR without broadcasting)"))
        }
    }

    private func tag(_ side: LiveLine.Side) -> String {
        switch side {
        case .them: return L("[对方]", "[them]")
        case .me: return L("[我]", "[me]")
        case .system: return L("[系统]", "[system]")
        }
    }

    // MARK: 轮询 + 自动分析

    private func tick() {
        // 续期「直播页在前台」标记（扩展按 5 秒时效读取，秒级续期；退后台自然过期）
        JevLiveStore.setAppLiveVisible(true)
        let snap = JevLiveStore.load()
        snapshot = snap
        guard autoAnalyze, !analyzing,
              let snap, JevLiveStore.isFresh(snap),
              let latest = snap.latestIncoming else { return }
        guard latest != lastAnalyzed else { return }
        // 防抖看 changedAt（画面内容最后一次变化）：对方连发三条会生成三次、白烧前两次的 token
        guard Date().timeIntervalSince(snap.changedAt) > 2.5 else { return }
        analyze(latest: latest, context: snap.contextText)
    }

    private func analyze(latest: String, context: String?) {
        analyzing = true
        lastAnalyzed = latest
        notice = nil
        let pipeline = JevPipeline(cfg: store.config)
        Task { @MainActor in
            let result = await pipeline.analyze(message: latest, context: context)
            analysis = result
            analyzing = false
            if let fatal = result.fatalError { notice = fatal }
        }
    }
}

// MARK: - 系统广播按钮（UIKit 桥接）

/// RPSystemBroadcastPickerView 是系统控件，点它弹系统面板（列出本 App 的广播扩展），
/// preferredExtension 让「Jev 直播」排第一，用户基本只需再点一下「开始直播」。
///
/// ⚠️ 必须用带非零 frame 的构造器：默认 init 是零尺寸，内部按钮会被布局成
/// frame=(inf,inf,0,0)——按钮永久不可见也不可点，系统面板永远弹不出来。
/// ⚠️ preferredExtension 必须与广播扩展 bundle ID 完全一致，且面板只在真机上响应真人点按
///（模拟器不弹、iOS 26 起合成事件不弹，见 listenSection 里的注释）。
struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        picker.showsMicrophoneButton = false
        picker.preferredExtension = "com.jevchat.jarvis.live"
        // 无障碍 + 真机 UI 自动化（XCUITest 靠这个 identifier 找它）
        picker.isAccessibilityElement = true
        picker.accessibilityIdentifier = "broadcastPicker"
        picker.accessibilityLabel = "Start Screen Broadcast"
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

// MARK: - 自检用合成聊天截图

enum LiveDebugFixtures {

    /// 画一张微信风格的假聊天图：对方靠左灰底、我方靠右主题色、居中时间戳。
    /// 用来在模拟器/不开广播的前提下验证「OCR → 左右归属」整条解析路径。
    /// 文案固定中文——识别语言就是 zh-Hans，换英文反而测不到重点。
    static func makeFakeChat() -> UIImage {
        let size = CGSize(width: 390, height: 640)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.949, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            drawCenter("20:31", y: 24, in: ctx.cgContext)
            bubble("在吗，周末的那个方案你看了一眼没", side: .them, y: 64, in: ctx.cgContext)
            bubble("看了看了，这两天有点忙", side: .me, y: 138, in: ctx.cgContext)
            bubble("周五之前给你一版完整的，带预算表", side: .me, y: 200, in: ctx.cgContext)
            bubble("行，记得把报价也放进去，老板要看价格", side: .them, y: 262, in: ctx.cgContext)
            bubble("好嘞", side: .me, y: 336, in: ctx.cgContext)
            bubble("对了上次说的那家餐厅，周末要不要去试试", side: .them, y: 396, in: ctx.cgContext)
            drawCenter("发送", y: 600, in: ctx.cgContext)   // 底部 UI，应该被清洗掉
        }
    }

    private static func drawCenter(_ text: String, y: CGFloat, in ctx: CGContext) {
        let attr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let s = NSAttributedString(string: text, attributes: attr)
        let w = s.size().width
        s.draw(at: CGPoint(x: (390 - w) / 2, y: y))
    }

    private static func bubble(_ text: String, side: LiveLine.Side, y: CGFloat, in ctx: CGContext) {
        let attr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label,
        ]
        let s = NSAttributedString(string: text, attributes: attr)
        var bounds = s.boundingRect(with: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude),
                                    options: [.usesLineFragmentOrigin], context: nil)
        bounds.size.width = ceil(bounds.width)
        bounds.size.height = ceil(bounds.height)
        let bubbleRect = CGRect(x: 0, y: y, width: bounds.width + 28, height: bounds.height + 20)
        let rect: CGRect = side == .them
            ? bubbleRect.offsetBy(dx: 64, dy: 0)
            : bubbleRect.offsetBy(dx: 390 - 64 - bubbleRect.width, dy: 0)

        let color: UIColor = side == .them ? .white : UIColor(red: 0.58, green: 0.86, blue: 0.44, alpha: 1)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        color.setFill()
        path.fill()

        let textOrigin = CGPoint(x: rect.minX + 14, y: rect.minY + 10)
        s.draw(at: textOrigin)
    }
}
