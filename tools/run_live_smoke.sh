#!/usr/bin/env bash
# 直播模式 OCR 链路自动化冒烟：同一份 Shared/JevLive.swift 在 Mac 上跑（不用 iPhone）。
# 覆盖：识别 / 左右归属 / 时间戳与群名清洗 / 会话门控与延续 / 模糊去重 / 目标累积。
# 用法：tools/run_live_smoke.sh   （改了 Shared/JevLive.swift 后必跑）
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp tools/live_ocr_smoke.swift "$tmp/main.swift"   # 带顶层语句的文件必须叫 main.swift
swiftc -O -o "$tmp/smoke" Shared/JevLive.swift "$tmp/main.swift"
"$tmp/smoke"
