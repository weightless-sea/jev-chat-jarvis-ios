// 直播模式 OCR 链路的独立冒烟测试：同一份 Shared/JevLive.swift，
// 在 macOS 上用 CoreGraphics 画一张假聊天图 → LiveOCREngine.recognize → 断言解析结果。
// 用法：cp 本文件到仓库根目录命名 main.swift，swiftc -O Shared/JevLive.swift main.swift -o /tmp/t && /tmp/t

import Foundation
import CoreText
import CoreGraphics
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Vision

let W = 780.0, H = 1280.0

func drawText(_ s: String, size: CGFloat, color: CGColor, at point: CGPoint, in ctx: CGContext) {
    let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [
        .font: font, .foregroundColor: color,
    ])
    let line = CTLineCreateWithAttributedString(attr)
    ctx.textPosition = point
    CTLineDraw(line, ctx)
}

func bubble(_ text: String, them: Bool, y: CGFloat, in ctx: CGContext) {
    let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 30, nil)
    let attr = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
    ])
    let line = CTLineCreateWithAttributedString(attr)
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    let rect = them
        ? CGRect(x: 120, y: y, width: width + 48, height: 64)
        : CGRect(x: W - 120 - width - 48, y: y, width: width + 48, height: 64)
    let color: CGColor = them
        ? CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        : CGColor(red: 0.58, green: 0.86, blue: 0.44, alpha: 1)
    ctx.setFillColor(color)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil))
    ctx.fillPath()
    drawText(text, size: 30, color: CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
             at: CGPoint(x: rect.minX + 24, y: rect.minY + 16), in: ctx)
}

let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// 标准 CG 坐标（原点左下，y 向上）。CGBitmapContext 的首行在内存里是图顶部，makeImage 直接可用。
ctx.setFillColor(CGColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
// 群聊名称（导航栏，约在顶部 9-11%——2026-10-22 用户实测被当成对方消息混进按钮）。
// 顶部裁剪提到 12% 后应整条排除，识别不到（时间同里）。
drawText("732鱼塘(3)", size: 24, color: CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1),
         at: CGPoint(x: 300, y: 1200), in: ctx)
drawText("20:31", size: 24, color: CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1),
         at: CGPoint(x: 350, y: 1150), in: ctx)
bubble("在吗，周末的那个方案你看了一眼没", them: true, y: 1060, in: ctx)
bubble("看了看了，这两天有点忙", them: false, y: 980, in: ctx)
bubble("周五之前给你一版完整的", them: false, y: 880, in: ctx)
bubble("行，记得把报价也放进去，老板要看价格", them: true, y: 780, in: ctx)
bubble("好嘞", them: false, y: 700, in: ctx)
// 跨天分隔行（2026-10-22 真机快照实锤的漏网形态）：不清洗就会被并进「对方消息」
drawText("10月15日15:23", size: 24, color: CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1),
         at: CGPoint(x: 300, y: 640), in: ctx)
bubble("对了上次说的那家餐厅周末去吗", them: true, y: 560, in: ctx)
drawText("发送", size: 28, color: CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1),
         at: CGPoint(x: 350, y: 60), in: ctx)

let image = ctx.makeImage()!

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "/tmp/live_test.png") as CFURL,
                                           UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("已导出 /tmp/live_test.png")

// 两种识别档位对比：时间与中文识别质量
func run(_ level: VNRequestTextRecognitionLevel) -> ([LiveLine], Double) {
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = level
    req.usesLanguageCorrection = false
    req.recognitionLanguages = ["zh-Hans", "en-US"]
    req.minimumTextHeight = 0.015
    req.regionOfInterest = LiveOCREngine.regionOfInterest()
    let t0 = Date()
    try? handler.perform([req])
    let dt = Date().timeIntervalSince(t0)
    let obs = (req.results ?? []).compactMap { o -> LiveChatParser.Observation? in
        guard let text = o.topCandidates(1).first?.string else { return nil }
        return LiveChatParser.Observation(text: text, boundingBox: o.boundingBox)
    }
    return (LiveChatParser.parse(obs), dt)
}

print("—— .fast ——")
let (fastLines, fastDt) = run(.fast)
for l in fastLines { let s = l.side == .them ? "[对方]" : l.side == .me ? "[我]　" : "[系统]"; print("\(s) \(l.text)") }
print(String(format: "耗时 %.0f ms", fastDt * 1000))

print("—— .accurate ——")
let (accLines, accDt) = run(.accurate)
for l in accLines { let s = l.side == .them ? "[对方]" : l.side == .me ? "[我]　" : "[系统]"; print("\(s) \(l.text)") }
print(String(format: "耗时 %.0f ms", accDt * 1000))

let lines = LiveOCREngine.recognize(cgImage: image)
print("—— 引擎全链路（accurate）——")
for l in lines { let s = l.side == .them ? "[对方]" : l.side == .me ? "[我]　" : "[系统]"; print("\(s) \(l.text)") }

var failures = 0
func check(_ cond: Bool, _ name: String) {
    print((cond ? "✅ " : "❌ ") + name)
    if !cond { failures += 1 }
}

check(!lines.isEmpty, "识别出非空对话行")
check(!lines.contains { $0.side == .system }, "时间戳/底部 UI 被清洗掉")
check(!lines.contains { $0.text.contains("鱼塘") }, "群聊名称（导航栏）被识别区域排除掉")
check(!lines.contains { $0.text.contains("10月15日") }, "跨天日期行被清洗掉")
// 自家 App/键盘的界面词（广播开着自己 App 时会被 OCR 到，2026-10-22 真机实锤）
let selfUI = LiveChatParser.parse([
    LiveChatParser.Observation(text: "AI 分析输入框文字", boundingBox: CGRect(x: 0.55, y: 0.2, width: 0.3, height: 0.03)),
    LiveChatParser.Observation(text: "秒回", boundingBox: CGRect(x: 0.1, y: 0.3, width: 0.1, height: 0.03)),
    LiveChatParser.Observation(text: "读屏幕分析", boundingBox: CGRect(x: 0.2, y: 0.4, width: 0.2, height: 0.03)),
])
check(selfUI.isEmpty, "自家 App/键盘 UI 词被清洗掉（纯解析）")
check(LiveChatParser.parse([
    LiveChatParser.Observation(text: "9月26日 23:00", boundingBox: CGRect(x: 0.3, y: 0.5, width: 0.2, height: 0.02)),
]).isEmpty, "「9月26日 23:00」带空格的跨天行被清洗（纯解析）")

// 「回复更早」目标累积（2026-10-22 用户需求：键盘一弹聊天滚到底，也要能回历史消息）
let hist: [LiveLine] = [
    .init(side: .them, text: "甲"),
    .init(side: .me, text: "乙"),
    .init(side: .them, text: "丙一"),
    .init(side: .them, text: "丙二"),
    .init(side: .system, text: "10月15日15:23"),
    .init(side: .them, text: "丁"),
]
let clusters = LiveChatParser.incomingClusters(in: hist)
check(clusters == ["丁", "丙一\n丙二", "甲"],
      "incomingClusters 自底向上收全簇（多行合并、系统行当边界），实际：\(clusters)")
let merged = JevLiveStore.mergingRecent(existing: ["丁"], found: clusters, cap: 3)
check(merged == ["丁", "丙一\n丙二", "甲"], "mergingRecent 新者在前、跨帧去重，实际：\(merged)")

// 模糊去重（2026-10-22 用户实测：「回复更早」出现两条一样的消息——键盘按钮文字被
// OCR 喂回快照的自反馈 + OCR 逐帧抖动绕过了精确去重）
let variants = [
    "市面上产品太多了 fish WiZzard 更新了拉一把，确实有崩溃",
    "市面上产品太多了 fish WiZzard 更新了 拉一\n把，确实有崩溃",      // 断行/空格不同
    "市面上产品太多了 fish Wizzard 更新了拉一把，确实有崩溃…",        // 逐字抖动+截断
]
let deduped = JevLiveStore.mergingRecent(existing: [], found: variants)
check(deduped.count == 1, "同一句话的识别变体（空格/断行/大小写/逐字抖动）只留一条，实际 \(deduped.count) 条")
check(deduped.first?.contains("有崩溃") == true, "保留的是内容完整的版本")
check(JevLiveStore.mergingRecent(existing: ["好的"], found: ["好的我现在出发"]).count == 2,
      "短消息的包含/近似关系不并入，真不同的消息都保留")
check(LiveChatParser.areSameMessage("这数字挺有意思，你这是在暗示什么吗？",
                                    "这数字挺有意思,你这是在暗示什么吗"),
      "中英文标点混排的同一句话视为相同")
let snapHist = LiveSnapshot(updatedAt: Date(), changedAt: Date(), lines: hist, frameCount: 1, recent: merged)
check(snapHist.latestIncoming == "丁", "滚动到历史片段时主目标退回 recent.first，实际：\(snapHist.latestIncoming ?? "nil")")

// 会话门控（2026-10-22 用户隐私诉求：非聊天画面不产生识别内容）
check(LiveChatParser.looksLikeConversation([.init(side: .them, text: "在吗"), .init(side: .me, text: "嗯")]),
      "两侧气泡都在 = 会话")
check(!LiveChatParser.looksLikeConversation([.init(side: .them, text: "甲"), .init(side: .them, text: "乙")]),
      "只有单侧气泡（纯对方）不是会话——防止单列 UI 误入")
check(!LiveChatParser.looksLikeConversation([.init(side: .me, text: "甲"), .init(side: .me, text: "乙")]),
      "只有单侧气泡（纯我方）不是会话")
check(!LiveChatParser.looksLikeConversation([]), "空画面不是会话")
// 会话延续：滚动单侧气泡的历史区间时，相邻帧有共同内容仍算会话（否则翻历史会被门控漏掉）
check(LiveChatParser.extendsConversation(
    [.init(side: .them, text: "丙"), .init(side: .them, text: "丁")],
    previous: [.init(side: .me, text: "乙"), .init(side: .them, text: "丙")]),
    "与上一帧有共同行 = 会话延续（单侧滚动区间）")
check(!LiveChatParser.extendsConversation(
    [.init(side: .them, text: "设置")],
    previous: [.init(side: .me, text: "乙"), .init(side: .them, text: "丙")]),
    "与上一帧无共同行 = 不是会话（切到别的 App）")
check(!LiveChatParser.extendsConversation(
    [.init(side: .them, text: "新内容")], previous: []),
    "上一帧为空（刚开播/刚切回）时无延续可言")
check(lines.first?.side == .them, "第一行归属对方（左）")
let lastMe = lines.filter { $0.side == .me }.last
check(lastMe?.text.contains("好嘞") == true, "最后一条我方消息为「好嘞」")
check(lines.last?.side == .them, "末尾是对方消息")
// 注意：单字断言会踩 OCR 逐字抖动（「餐厅」曾偶发认成「贅厅」），锚定多字词
check(lines.last?.text.contains("上次说的那家") == true, "末行是最后那条对方消息，实际：\(lines.last?.text ?? "nil")")

if !lines.isEmpty {
    let snap = LiveSnapshot(updatedAt: Date(), changedAt: Date(), lines: lines, frameCount: 1)
    check(snap.latestIncoming?.contains("上次说的那家") == true,
          "latestIncoming = 末条对方消息，实际：\(snap.latestIncoming ?? "nil")")
    check(snap.latestIncoming?.contains("10月15日") != true, "latestIncoming 不含日期行")
    let ctxText = snap.contextText ?? ""
    check(ctxText.contains("我："), "contextText 带说话人前缀")
    check(ctxText.contains("报价"), "contextText 含此前对话（报价那条）")
    check(ctxText.contains("好嘞"), "contextText 含日期行之前的我方消息")
    check(!ctxText.contains("上次说的那家"), "contextText 不含待回消息本体")
}

print(failures == 0 ? "\n全部通过" : "\n有 \(failures) 项失败")
exit(failures == 0 ? 0 : 1)
