import ReplayKit
import CoreVideo

// MARK: - 直播模式广播扩展
//
// 用户在主 App 点系统广播按钮后，iOS 把整块屏幕的帧喂到这里。四条约束决定了写法：
//   · 内存 ~50MB jetsam 硬上限：只做 OCR 与落盘，LLM 调用留给键盘/主 App；
//     帧先降采样成 720 宽灰度图再识别（见 LiveOCREngine），autoreleasepool 包全程。
//   · 回调队列被阻塞 = ReplayKit 自动丢帧：同步识别 2 秒一帧正好利用这一点节流。
//   · 没有任何 UI：结果只能写 App Group 快照，由键盘与主 App 呈现。
//   · 「没消息 ≠ 没活着」：broadcastStarted 必须立刻写一份空快照当心跳，
//     否则 OCR 冷启动的窗口里 App 永远显示「未在监听」（2026-09-24 真机首测的教训）。

final class LiveBroadcastHandler: RPBroadcastSampleHandler {

    /// OCR 节流周期。聊天画面一秒内的变化远低于此频率；2 秒兼顾实时性与耗电。
    private static let interval: TimeInterval = 2.0

    private var lastOCRAt = Date.distantPast
    /// nil = 还没识别过第一帧（与「识别出了空白画面」区分）
    private var lastSignature: String?
    /// 上一会话帧的识别内容：会话延续判定用（滚动单侧气泡区间时相邻帧有交集）。
    /// 只在会话帧更新——切出聊天后它冻结，别的 App 内容对不上交集，门控照常生效。
    private var lastLines: [LiveLine] = []
    private var changedAt = Date()
    private var framesSeen = 0
    private var ocrRuns = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        changedAt = Date()
        // 心跳快照：App/键盘 1 秒内就该显示「监听中」，不等 OCR 冷启动出活
        JevLiveStore.save(LiveSnapshot(updatedAt: changedAt, changedAt: changedAt,
                                       lines: [], frameCount: 0, recent: []))
        JevLiveStore.diag("广播已启动")
    }

    override func broadcastFinished() {
        JevLiveStore.diag("广播结束：\(framesSeen) 帧 / OCR \(ocrRuns) 次")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        framesSeen += 1
        let now = Date()
        guard now.timeIntervalSince(lastOCRAt) >= Self.interval else { return }
        lastOCRAt = now

        // App「直播」页在前台时整帧跳过（只发心跳、冻结 recent）：页面上是我们自己的
        // 识别结果 UI，OCR 它只会把上一轮目标喂回快照形成自反馈（2026-10-22 日志实锤）。
        if JevLiveStore.appLiveVisible() {
            lastSignature = ""
            lastLines = []
            JevLiveStore.save(LiveSnapshot(updatedAt: now, changedAt: changedAt, lines: [],
                                           frameCount: framesSeen,
                                           recent: JevLiveStore.load()?.recent ?? []))
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let started = Date()
        // 键盘面板开着时抬底部裁剪：面板在识别区里会被 OCR，按钮上显示的上一轮目标
        // 会被喂回快照（同一个自反馈回路）。比例由键盘自报（含时间戳，过期按 0 处理）。
        let bottomCut = min(0.6, max(0.14, JevLiveStore.keyboardPanelFraction() + 0.02))
        let lines = LiveOCREngine.recognize(pixelBuffer: pixelBuffer, bottomCut: bottomCut)
        ocrRuns += 1
        if ocrRuns == 1 {
            // 首帧识别是模型冷启动最慢的一次，时长落 diag 备查
            JevLiveStore.diag("首次识别 \(Int(Date().timeIntervalSince(started) * 1000)) ms，"
                + "\(lines.count) 行，帧 \(CVPixelBufferGetWidth(pixelBuffer))×\(CVPixelBufferGetHeight(pixelBuffer))")
        }

        // 心跳每拍都落盘（payload ~2KB，开销可忽略）；changedAt 只在内容真变了时推进。
        // 会话门控：识别内容只在会话帧产生。「会话」= 双侧气泡同框（looksLikeConversation）
        // 或与上一会话帧有共同内容（extendsConversation——滚动单侧气泡的老历史时仍算会话，
        // 否则门控会把用户翻过的消息整段漏掉）；切到别的 App 内容对不上交集，只发心跳、
        // 清空识别结果、recent 冻结保留（切回聊天不丢历史目标）。
        let inConversation = LiveChatParser.looksLikeConversation(lines)
            || LiveChatParser.extendsConversation(lines, previous: lastLines)
        if inConversation { lastLines = lines }
        let signature = inConversation ? lines.map(\.text).joined(separator: "|") : ""
        if signature != lastSignature { changedAt = now }
        lastSignature = signature
        let recent = inConversation
            ? JevLiveStore.mergingRecent(existing: JevLiveStore.load()?.recent ?? [],
                                         found: LiveChatParser.incomingClusters(in: lines))
            : (JevLiveStore.load()?.recent ?? [])
        JevLiveStore.save(LiveSnapshot(updatedAt: now, changedAt: changedAt,
                                       lines: inConversation ? Array(lines.suffix(40)) : [],
                                       frameCount: framesSeen, recent: recent))
    }
}
