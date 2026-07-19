#!/bin/bash
# M5 内存验收(grill #14)。本机无 Instruments(xctrace/instruments 缺失,实测),
# 改用 footprint + leaks 采样 50 次录/转/注循环。SIGUSR1 触发 toggleRecording
# (AppCoordinator 的 debug hook,仅 AIVI_DEBUG_DIR 设置时挂)。
#
# 注:这里录音是静音(无人说话)→ 走电平 gate 跳过 API,不烧钱、不注入,
# 但完整走「录音 start/stop + gate + 状态机 + 提示音」的对象生命周期,足够查泄漏。
# 真实带 API 的循环由 owner 用真 key 另跑(会计费)。
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
swift build -c release >/dev/null 2>&1
./bundle.sh >/dev/null 2>&1

SCRATCH=$(mktemp -d)
export AIVI_DEBUG_DIR="$SCRATCH"
BIN=./dist/AIVoiceInput.app/Contents/MacOS/AIVoiceInput

"$BIN" >/dev/null 2>&1 &
APP=$!
sleep 3
if ! kill -0 $APP 2>/dev/null; then echo "❌ app 未启动"; exit 1; fi

sample() { # label
  local rss; rss=$(footprint -l "$APP" 2>/dev/null | grep -i 'phys_footprint' | head -1 || true)
  local rssk; rssk=$(ps -o rss= -p $APP)
  echo "  [$1] RSS=${rssk} KB  ${rss}"
}

echo "== 50 次录/停循环(SIGUSR1),10/30/50 采样 =="
sample "start"
for i in $(seq 1 50); do
  kill -USR1 $APP 2>/dev/null   # start recording
  sleep 0.15
  kill -USR1 $APP 2>/dev/null   # stop -> gate -> idle
  sleep 0.15
  case $i in 10|30|50) sample "iter $i";; esac
done

echo "== leaks 检查 =="
LEAKS_OUT=$(leaks $APP 2>/dev/null)
echo "$LEAKS_OUT" | grep -E 'leaks for|total leaked' | head -2
# 泄漏字节:一次性系统框架分配(几百字节)是良性;逐次泄漏会随 50 次循环放大到 KB-MB
BYTES=$(echo "$LEAKS_OUT" | grep -oE '[0-9]+ total leaked bytes' | grep -oE '^[0-9]+' || echo 0)
echo "  总泄漏字节: ${BYTES:-0}(<1KB 且 RSS 平台 = 无逐次泄漏,一次性系统分配良性)"

kill $APP 2>/dev/null
echo ""
echo "判定:RSS iter 10→50 趋于平台(非单调猛涨)+ 总泄漏 <1KB = PASS。"
[ "${BYTES:-0}" -lt 1024 ]
