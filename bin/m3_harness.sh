#!/bin/bash
# M3 注入验收 harness(两进程,grill #13)。**owner 在自己的 GUI Terminal 里跑**——
# agent 的 Background launchd session 不驱动真实窗口焦点,注入的 ⌘V 落不进 receiver。
#
# 前置:辅助功能授权(系统设置→隐私与安全性→辅助功能→加运行用的 Terminal.app→打开)。
#   验证:./.build/release/aivi-cli probe 应打印 axTrusted=true。
#
# 用法:./bin/m3_harness.sh        # 全部用例
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
swift build -c release >/dev/null 2>&1
CLI=./.build/release/aivi-cli
RECV=./.build/release/InjectReceiver
OUT=$(mktemp -d)/recv.txt
export AIVI_RECEIVER_OUT="$OUT"

pass=0; fail=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "  ✅ $1"; pass=$((pass+1)); else echo "  ❌ $1: 期望[$2] 实得[$3]"; fail=$((fail+1)); fi
}

echo "== probe =="; $CLI probe
if [ "$($CLI probe | grep -c 'axTrusted=true')" != "1" ]; then
  echo "❌ 辅助功能未授权 —— 先授权给本 Terminal(见脚本头注释)。中止。"; exit 1
fi

echo "== 用例1: 粘贴法 exact 落字 + 剪贴板恢复 (P0#1 主路径) =="
SENTINEL="ORIG-CLIP-$RANDOM"
$CLI pbset "$SENTINEL" >/dev/null
rm -f "$OUT"; "$RECV" & RPID=$!; sleep 2
TEXT="帮我 review 一下这个 PR,把 bug 修掉。Mixed test 123!"
$CLI inject "$TEXT" --method paste >/dev/null; sleep 1
check "落字 exact" "$TEXT" "$(cat "$OUT" 2>/dev/null)"
check "原剪贴板已恢复" "$SENTINEL" "$($CLI pbget)"
kill $RPID 2>/dev/null

echo "== 用例2: 打字法 exact 落字 (若 CJK IME 激活会自动降级 paste,看日志) =="
rm -f "$OUT"; "$RECV" & RPID=$!; sleep 2
$CLI inject "$TEXT" --method type >/dev/null; sleep 1
check "落字 exact" "$TEXT" "$(cat "$OUT" 2>/dev/null)"
kill $RPID 2>/dev/null

echo "== 用例3: 密码框拒注 (P0#2 —— 不落剪贴板) =="
SENTINEL2="SECRET-KEEP-$RANDOM"
$CLI pbset "$SENTINEL2" >/dev/null; BEFORE=$($CLI pbcount)
rm -f "$OUT"; "$RECV" --secure & RPID=$!; sleep 2
OUTCOME=$($CLI inject "PASSWORD-SHOULD-NOT-LEAK" --method paste)
check "剪贴板未被碰(changeCount)" "$BEFORE" "$($CLI pbcount)"
check "剪贴板内容保留" "$SENTINEL2" "$($CLI pbget)"
echo "     outcome: $OUTCOME"
kill $RPID 2>/dev/null

echo "== 用例4: Secure Keyboard Entry ON 拒注 (grill #4) =="
$CLI pbset "SECURE-INPUT-$RANDOM" >/dev/null; BEFORE=$($CLI pbcount)
rm -f "$OUT"; "$RECV" --secure-input & RPID=$!; sleep 2
OUTCOME=$($CLI inject "SHOULD-BE-REFUSED" --method paste)
check "剪贴板未被碰" "$BEFORE" "$($CLI pbcount)"
echo "     outcome: $OUTCOME (应为 refusedSecureContext)"
kill $RPID 2>/dev/null

echo "== 用例5: ⌘V 被吞 → 文字仍可找回 (P0#1) =="
rm -f "$OUT"; "$RECV" --swallow-cmdv & RPID=$!; sleep 2
$CLI inject "$TEXT" --method paste >/dev/null; sleep 1
# receiver 吞了 ⌘V,所以 receiver 里应为空;找回路径 = App 的菜单(此处 harness 不含 App,
# 只验证「注入尝试了但没落进被吞的 receiver」——App 层的 lastTranscript 已在 M2 e2e 证过)
check "receiver 未收到(⌘V 被吞)" "" "$(cat "$OUT" 2>/dev/null)"
kill $RPID 2>/dev/null

echo ""
echo "== 结果: $pass 通过 / $fail 失败 =="
echo "注:真实 App(Notes/Safari/Terminal/Electron)落字请手动:热键说话→看光标处。微信 4.x best-effort。"
[ "$fail" -eq 0 ]
