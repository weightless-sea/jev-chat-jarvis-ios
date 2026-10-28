# Guideline 4.3(a) 驳回应对（2026-10-14 审核）

> 本文记录 0.1.0 (2) 被 4.3(a) Design - Spam 拒绝的事实、成因分析与重提方案。
> 重提的代码侧改动已全部落在 0.2.0 (3)：**新增直播模式（录屏 + 本地 OCR + 键盘免复制出候选）**，
> 这是与市面上「复制 → 生成回复」类套壳 App 最硬的差异化点。

## 一、事实

- Submission ID: `9f9696f1-566e-4b2b-b0c8-85a3bac9f3f9`
- 审核日期：2026-10-14；审核设备：iPad Air 11-inch (M3)；版本：0.1.0 (2)
- 条款：**Guideline 4.3(a) - Design - Spam**
- 触发背景：4.3(a) 是机器初筛，比对的是**二进制相似度、UI 截图相似度、元数据（名称/截图/描述）与其他 App 的重合度**。同一份代码模板改编上架多个 App、或与商店里大量同功能 App 高度相似，都会命中。

## 二、成因分析（本项目最可能的三条）

1. **功能形态撞车**：v0.1.0 的用户可见功能就三件事——粘贴文字 → 调模型 → 回候选。「AI 聊天回复助手」这个形态在商店里存量很大，特征空间太窄，机器初筛按「功能 + UI 布局 + 文案」聚簇时容易被归进同一个簇。
2. **iPhone-only App 跑在 iPad 兼容模式下审核**：审核设备是 iPad Air，兼容模式的界面拉伸会让截图更「模板化」，加重相似度观感。
3. **元数据差异化不足**：截图、描述、关键词与同类 App 用词高度重合（顺手可查：同类词「高情商回复」「AI 回复」下的头部产品）。

> 注意：Apple **不会**因为「Swift 源码重复」发 4.3——它看不到你的源码。所谓「重复代码量多触发 4.3」的真实机制是「**产物相似**」：同样的功能集 + 同样的界面骨架 + 同样的 SDK 指纹。所以对策不是去重源码，而是**把「用户可见的东西」做出独有性**。

## 三、0.2.0 (3) 已落地的差异化

| 改动 | 为什么有助于过 4.3 |
|---|---|
| **直播模式**（`JevLive` 广播扩展 + `LiveView` + 键盘「读屏幕分析」） | 商店同类 App 没有的能力：ReplayKit 录屏 + 本地 Vision OCR + 气泡左右归属解析，免复制直接出候选。这是功能独占点，也是给审核员看的「这个 App 为什么不是又一个套壳」的答案 |
| 版本 0.1.0 (2) → **0.2.0 (3)**，构建号递增 | 大版本语义上明确「这是有实质新功能的一版」，配合回复信说明 |
| 中英双语界面 + 语言切换 | 界面文案本身构成差异 |
| 键盘面板为直播亮出专属入口（读屏幕分析按钮） | 键盘截图可单独体现该能力 |

## 四、重提前检查清单（在 App Store Connect 做）

1. **截图重做**：至少 1 张放直播模式（App「直播」页识别结果 + 键盘「读屏幕分析」按钮），别全用「分析剪贴板」结果页——那是与同类最像的一张。截图文案（上叠大字）强调「免复制」「本地 OCR 读屏」。
2. **描述首段改写**：第一句就说「屏幕监听 + 键盘直出回复」，把「复制粘贴」降级为兼容路径。关键词避开与头部同类完全相同的组合。
3. **审核备注（App Review Information → Notes）**：写清三件事——① 直播模式怎么用（点直播页按钮 → 系统面板确认 → 回聊天页）；② 录屏是系统 API、紫色指示常亮、OCR 在本机；③ 只有用户点分析时文本才发往用户自配的接口。**审核设备是 iPad，App 是 iPhone-only，备注里提醒审核员用 iPhone 或兼容模式体验完整功能。**
4. **演示视频**（可选但推荐）：App Preview 或备注里给个链接，30 秒演示直播模式全链路。
5. 隐私政策 URL 有效且提到「屏幕内容本地 OCR」（直播模式上架后隐私清单同步补 `ScreenRecording`? 无需——OCR 在本机、不上传画面，不新增收集项；政策文字里说明即可）。

## 五、回复信模板（Resolution Center / 重新提交时附上）

> 英文放前面，中文留档。按实际情况删改，别承诺做不到的事。

**English:**

> Thank you for the review. Guideline 4.3(a) appears to be a false positive: this app is an original, independently developed keyboard assistant, not a repost or a clone of another app on the account.
>
> In version 0.2.0 the app gained a genuinely differentiating capability that no generic "AI reply" app offers: **Live Mode**. The user can start a system screen broadcast (ReplayKit, requires explicit user confirmation each time, with the system's purple recording indicator always visible). A broadcast upload extension runs **on-device Vision OCR** locally — the screen content never leaves the device — reconstructs the conversation by bubble position, and surfaces a "Read screen" action directly in our custom keyboard, so the user no longer needs to copy messages at all. Only when the user taps analyze does the recognized text get sent to the model endpoint the user configured themselves (bring-your-own key).
>
> The app is a single product on this developer account, built from its own codebase, with original icon, artwork, and screenshots. New screenshots highlighting Live Mode are attached to this submission.

**中文留档：**

> 感谢审核。4.3(a) 应为误判：本 App 为独立原创开发，非同账号下重复提交的克隆应用。
>
> 0.2.0 版新增了同类产品不具备的独有功能——**直播模式**：用户在 App 内点系统广播按钮（ReplayKit，每次开始都需用户在系统面板显式确认，录屏期间状态栏紫色指示常亮），广播扩展在本机用 Vision 完成文字识别（屏幕内容不出设备），按气泡位置还原对话后，在我们的自定义键盘中直接亮出「读屏幕分析」入口，用户无需再复制消息。只有当用户主动点分析时，识别文本才发送到用户自行配置的模型接口（自带 Key）。
>
> 本开发者账号下这是一个独立产品，代码、图标、截图均为原创。本次提交已附突出直播模式的新截图。

## 六、如果再次被 4.3 拒

- 用 Resolution Center **回复审核员**（Request a phone call 也可选），别盲目重传——机器初筛连续命中时，人工复核反而容易翻案。
- 要求提供：本 App 与「被认定重复」的 App 的对应关系。若对方点名了某个 App，针对性写差异对照表。
- 终极手段是 App Review Board 申诉（`appreview@apple.com`，标题带 Submission ID）。
- 同账号后续若要发「同源不同皮」的兄弟包，必须做到：不同名称/图标/配色/截图/首发功能集，且本体功能有实质区别——这是 4.3 的红线，本项目按定位（500 人群 TestFlight 测留存）不走这条线。
