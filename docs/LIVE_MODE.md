# 直播模式

> 状态：**已并入主干功能集（0.2.0，2026-10-22）**——OCR→解析链路冒烟 10/10、双出口 UI 就位、
> 标识体系归位 master（`com.jevchat.jarvis.live` / `group.com.jevchat.jarvis`）、
> 广播面板「不弹」定性为**模拟器不支持 + iOS 26 只认真人点按**（非代码 bug，见「交接状态」）。
> 结论先行：**方向可行，但有三条硬约束**（见下）。输入从「手动复制」变成「自动读屏」，
> 生成层/话术/判断层完全复用旧管线，没有新依赖。4.3 驳回后的功能差异化主力，见 [`REVIEW_4_3.md`](REVIEW_4_3.md)。

## 一、思路与数据流

用户不再「长按消息 → 复制 → 回键盘粘贴」，而是：

```
主 App「直播」页点系统广播按钮
  → ReplayKit 广播扩展（JevLive）收到全屏帧
  → 每 2 秒取一帧，Vision 本地 OCR（accurate 档，zh-Hans）
  → LiveChatParser 按气泡横向位置分「我方/对方」，洗掉时间戳/底部 UI
  → 会话门控：只有「双人聊天」画面（两侧气泡都在）才产生识别内容，其他画面只发心跳
  → 快照写 App Group（UserDefaults，每 2 秒心跳落盘：updatedAt=活着，changedAt=画面内容变化）
  → 扩展把每帧里的对方消息簇去重累积进快照 recent（封顶 6 条，跨帧留存）
  → 键盘待机页亮「读屏幕分析：「<对方最新一条>」」主按钮 + 至多两条「回复更早：「…」」，
    点任一条走 JevPipeline；键盘弹出时聊天会自动滚到最底、当前帧常只剩用户自己的消息，
    主目标此时退回 recent 最近一条，不再消失乱跳，「更早」列表让用户挑历史消息回
    （2026-10-22 用户实测需求「我想同时能回复历史的消息」）
  → 或主 App「直播」页打开自动分析开关后前台自动分析（默认关，防抖 2.5 秒），候选点一下复制
```

`message` = 尾部连续的对方气泡（多行合并），`context` = 之前 14 行带说话人前缀——
正好填进现有 `JevPipeline.analyze(message:context:)` 的两个入口。

## 二、三条硬约束（调研结论）

1. **广播扩展 ~50MB 内存 jetsam 硬上限**。所以扩展进程里只做 OCR 和落盘，
   **LLM 调用绝不放扩展里**；autoreleasepool 包住识别，帧先降采样成 720 宽灰度图再喂
   Vision（全屏 NV12 帧 ≈ 12MB，中间缓冲翻几倍，是撑爆上限的最大威胁），
   2 秒节流靠「阻塞回调队列 = ReplayKit 自动丢帧」实现，不自己攒缓冲。
2. **主 App 在后台会被挂起**：广播在跑时 App 不一定活着，Darwin 通知也唤不醒它。
   所以前台自动分析只是锦上添花，**键盘才是主出口**（键盘打开时轮询快照，2 秒一次）。
3. **OCR 档位必须 accurate**：同源 Vision 冒烟实测，`.fast` 对中文几乎全瞎
   （6 条气泡只认出 1 个英文词），`.accurate` 全对。热身后单帧 ~300ms（M 系 CLI 口径），
   iOS 走 ANE 只会更好。若真机上内存吃紧被杀，把 `LiveOCREngine.makeRequest()`
   里的档位改回 `.fast` 再试（iOS 16 起 fast 也支持中文，macOS 不行）。

另：**首次识别可能极慢**（中文识别模型首次要编译，macOS 上实测 33 秒冷启动，之后 300ms）。
iOS 模型随系统分发，冷启动代价小得多，但广播开始后的头一两帧慢属正常——
所以扩展在 `broadcastStarted` 就写心跳快照，App/键盘立刻显示「监听中」，不等首帧识别。

## 二点五、交接状态（2026-10-22 更新）

### 已经好的
- 编译、装机、App「直播」页 + 键盘「读屏幕分析」双出口 UI。
- **explore/live-ocr 已并回 master 标识体系**（2026-10-22 合并）：扩展 bundle ID
  `com.jevchat.jarvis.ios.live` → **`com.jevchat.jarvis.live`**，App Group 统一
  `group.com.jevchat.jarvis`（entitlements / project.yml / `JevLiveStore` / `preferredExtension` 四处已同步），
  团队 75LZ93U5CF，版本 0.2.0 (3)。无签名设备构建 + 扩展嵌入（PlugIns/JevLive.appex）已验证。
- 界面全量中英双语（master 本地化体系 `jevLocalized`）；相册自检补上了选中处理逻辑（此前选了没反应）。
- OCR 链路：`tools/live_ocr_smoke.swift` 冒烟 10/10（合成微信风图 6 气泡全对、左右归属全对、
  时间戳/「发送」清洗、latestIncoming/contextText 语义正确；2026-10-22 复跑通过）。App「直播」页底部自检
  （合成图 / 相册真截图）走同一条识别代码。
- 「一直未在监听」的两个根因已修（修法都有注释锚点）：
  1. **扩展心跳缺失**：旧版只在「识别出非空且变化的文字」时落盘，广播刚启动/OCR 冷启动的
     窗口里 App 永远「未在监听」。现在 `broadcastStarted` 立即写空快照，且每拍（2s）都落盘：
     `updatedAt`=心跳（广播活着它就新），`changedAt`=画面内容变化（App 防抖用它）。
     快照 key 升到 `jev.live.snapshot.v2`。
  2. **广播按钮零尺寸布局**：`RPSystemBroadcastPickerView` 默认 init 零尺寸 → 内部按钮被布局成
     `frame=(inf,inf,0,0)`（diag 视图树抓的现行）→ 按钮不可见不可点。改用非零 frame 构造器
     （`BroadcastPickerView.makeUIView`）后按钮正常渲染。

### 「面板不弹」定性（原唯一拦路虎，非代码 bug）
2026-10-22 调研定性（Apple 文档 + 社区案例，注释锚点在 `LiveView.listenSection` 与 `BroadcastPickerView`）：
1. **模拟器上系统广播面板永远不弹**——广播上传扩展不被模拟器支持，这条排查线从一开始就死路；
2. **真机上必须真人点按**：iOS 26 起对合成事件明显收紧，XCUITest 坐标点击、无障碍激活、
   私有 `buttonPressed:` 都不触发系统面板（前两轮排查的合成点按全落在这一类）；
3. 代码侧唯一能做的就是配置正确（`preferredExtension` 与扩展 bundle ID 完全一致、扩展真实嵌入、
   三 target 同团队签名）+ 按钮可见可点——这四项现在都满足并写进了构建自检。

**下一步只剩一步：真机装 0.2.0 (3)，解锁状态用手指点「直播」页的广播按钮**——
预期弹系统面板 → 选「Jev 直播」→ 开始广播。通了之后跑 `UITests/LiveBroadcastUITests.swift`
（断言已写好：监听中 → 已识别帧 → 60 秒不掉线 → 停播；注意它只负责点按钮和断言状态，
面板内的「开始直播」仍需真人代点一次）。真机自动化命令：

```bash
xcodegen generate   # 若改过 project.yml
xcodebuild test -project JevJarvis.xcodeproj -scheme JevJarvis \
  -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates
```

手机需解锁、别拔线、测试运行期间别手动点屏幕。扩展侧诊断走 App Group 的
`jev.diag.v1`（`JevLiveStore.diag`，[直播] 前缀），用
`devicectl device copy from --domain-type appGroupDataContainer` 拉出来看。

## 三、左右归属的边界（启发式， knowingly 不完美）

- 判据：一行（并集框）中点 x > 0.55 屏宽 → 我方。微信/QQ/iMessage/Telegram 等
  左右布局聊天都满足；引用块、超长链接卡片、系统居中提示可能判错边。
- 洗掉：纯时间行、`发送`/`输入` 等底部 UI 词（另有 regionOfInterest 裁掉状态栏与输入条）。
- 表情包/图片不产生文字，等于漏一行，不影响其余行的归属。
- 群聊里谁说的分不出来（都算「对方」）——对「该回哪条」影响有限，对语气有影响，后续再说。

## 四、真机测试步骤（模拟器测不了广播链路）

1. `xcodegen generate` → Xcode 选 `JevJarvis` scheme → 真机 Run。
2. App →「直播」页 → 点广播按钮 → 系统面板选「Jev 直播」→ 开始广播。
3. 切到微信，停留在某会话几秒（让扩展吃几帧）。
4. 回 App「直播」页：看「识别结果」一节是否还原了对话、左右有没有判反。
5. 键盘路径：微信里把键盘切到 Jev → 待机页应出现主色「读屏幕分析：…」按钮 →
   点它，应直接出候选（等价于原来「分析剪贴板」的效果）。
6. 想关：控制中心停止广播，或回 App 点停止。快照 150 秒后自动视为失效。
7. 不开广播也能验证 OCR：App「直播」页底部「自检」——合成示例图 / 从相册选真截图，
   走的是同一条识别与解析代码。

## 五、隐私与上架注意

- **按 App 白名单过滤做不到（iOS 硬限制）**：广播扩展拿不到「当前前台是哪个 App」的任何 API，
  只收裸视频帧——系统不暴露窗口归属，这条对所有 iOS 录屏类 App 一视同仁，绕不过去。
- **替代方案=会话门控（2026-10-22 落地）**：只有「长得像双人聊天」的画面（`LiveChatParser.looksLikeConversation`，
  我方+对方两侧气泡同时在场）才产生识别内容；其他画面只发心跳、清空识别结果、recent 冻结保留。
  广播期间切去设置/相册/银行等 App，快照里不会留下那个 App 的内容。App「直播」页在门控生效时明示
  「当前画面不像聊天界面，不产生识别内容」。
- 系统录屏指示（紫色胶囊）全程可见，且每次开始都要用户在系统面板显式确认——
  这是 Apple 的设计，也是我们的免责边界。
- 对话文本会发往用户自配的生成层端点（BYO key）。「直播」页与隐私政策要写明
  「屏幕内容会被本地 OCR，识别出的对话文本仅在你触发分析时发送给你配置的模型」。
- 上架审核风险中等：ReplayKit 广播是合法 API，但「录屏 + 上传」组合需要说清楚用途；
  TestFlight 先行（符合项目发 500 人群测留存的定位）。

## 六、已知限制 / 下一步

- [ ] 真机验证广播链路 + 内存水位（Xcode Memory gauge 看 JevLive 进程，别过 50MB）
- [ ] 真机试 iOS 的 `.fast` 档：若中文可用则换回去，更省内存
- [ ] 键盘打开期间对新消息「自动出候选」（目前要点一下按钮；自动做会烧 token，需开关）
- [ ] 群聊 sender 区分；引用/回复消息的归并
- [ ] 快照里带 App 名/会话名，避免把不相关 App 的画面当对话（目前靠用户自己别乱切）
- [ ] 审核条款 5.1.1/5.1.2 的隐私话术打磨
