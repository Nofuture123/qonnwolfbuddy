#!/usr/bin/env bash
# tests/review-identity.sh —— 审核身份可核验（scenario-03）定向测试
# 覆盖不同模型/独立会话、可选family、渠道/大小写归一化与缺证据拒绝。
# shellcheck disable=SC2015 # ok/bad 仅 echo 与计数，均返回成功。
set -uo pipefail
TMPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/.qwb-tmp"
export TMPDIR
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d "$TMPDIR/tmp.XXXXXXXX")" || exit 1
export TMPDIR="$TMP"
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 健康项目骨架：真安装（与 smoke 同法），让 lint 其余各节全绿，专测「审核身份」一节
P="$TMP/proj"; mkdir -p "$P"
bash "$ROOT/bin/qwb-init.sh" "$P" >/dev/null
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\n' >> "$P/qwbuddy/config.sh"
mkdir -p "$P/docs/reviews"
printf 'impl 原生会话转储\n' > "$P/docs/reviews/impl-session.md"
printf 'rev 原生会话转储\n'  > "$P/docs/reviews/rev-session.md"
T="$P/tasks/2099-01-01-rt.md"

mk() { # $1=review-impl 行  $2=review-rev 行（空串=不写该行）
  {
    printf '# 审核身份测试票\nstate: running\nreview-required: yes\n'
    [[ -n "${1:-}" ]] && printf '%s\n' "$1"
    [[ -n "${2:-}" ]] && printf '%s\n' "$2"
  } > "$T"
}

OUT=""; RC=0
runlint() { OUT="$(bash "$ROOT/bin/qwb-lint.sh" --project "$P" 2>&1)"; RC=$?; }

IMPL='review-impl: model=gpt-5.2-codex family=gpt cli=codex session=codex-s-001 evidence=docs/reviews/impl-session.md'
REV='review-rev: model=claude-opus-4.6 family=claude cli=claude session=claude-s-009 evidence=docs/reviews/rev-session.md'

echo "== 1. user_不同模型家族审核有效（正例）=="
mk "$IMPL" "$REV"
runlint
{ [[ "$RC" -eq 0 ]] && printf '%s' "$OUT" | grep -q '审核身份'; } \
  && ok "不同家族+各自原生session+证据齐 → LINT PASS" \
  || { bad "合法审核身份未通过（rc=${RC}）:"; printf '%s\n' "$OUT"; }

echo "== 2. 同 CLI 不同家族合法（正例）=="
mk 'review-impl: model=gpt-5.2 family=gpt cli=codex session=s-impl-1 evidence=docs/reviews/impl-session.md' \
   'review-rev: model=qwen3-max family=qwen cli=codex session=s-rev-2 evidence=docs/reviews/rev-session.md'
runlint
[[ "$RC" -eq 0 ]] && ok "同 codex CLI 不同 family → 仍 PASS" \
  || { bad "同CLI不同family被误拒（rc=${RC}）:"; printf '%s\n' "$OUT"; }

echo "== 3. user_无审核要求的普通票零负担（正例）=="
printf '# 普通票\nstate: running\n' > "$T"
runlint
[[ "$RC" -eq 0 ]] && ok "无 review-required 标记 → lint 不启用身份检查" \
  || { bad "普通票被误查（rc=${RC}）:"; printf '%s\n' "$OUT"; }
printf '%s' "$OUT" | grep -q '无 review-required' \
  && ok "lint 输出明示检查范围（跳过普通票）" || bad "lint 未明示检查范围"
printf '# 普通票2\nstate: running\nreview-required: no\n' > "$T"
runlint
[[ "$RC" -eq 0 ]] && ok "review-required: no → 不启用" || bad "review-required: no 被误查"

echo "== 4. 同家族不同模型，family为可选附记 =="
for family in 'family=gpt' '' 'family=unknown' 'family=arbitrary'; do
  mk "review-impl: model=magpie/codex/gpt-6.1-sol $family session=s-impl-1 evidence=docs/reviews/impl-session.md" \
     "review-rev: model=magpie/codex/gpt-6-astra $family session=s-rev-9 evidence=docs/reviews/rev-session.md"
  runlint
  [[ "$RC" -eq 0 ]] && ok "Sol/Astra同家族不同模型 ${family:-无family} → PASS" \
    || { bad "不同模型被误拒（rc=${RC}）:"; printf '%s\n' "$OUT"; }
done

echo "== 5. 同模型不同档位/渠道/大小写一律拒绝 =="
for model in 'magpie/codex/gpt-6-astra' 'openai-codex/gpt-6-astra' 'MAGPIE/CODEX/GPT-6-ASTRA'; do
  mk 'review-impl: model=magpie/codex/gpt-6-astra family=gpt thinking=high session=s-impl-1 evidence=docs/reviews/impl-session.md' \
     "review-rev: model=$model family=claude thinking=low session=s-rev-9 evidence=docs/reviews/rev-session.md"
  runlint
  { [[ "$RC" -eq 1 ]] && printf '%s' "$OUT" | grep -q '同一模型(gpt-6-astra)'; } \
    && ok "同型号 $model → 拒绝并点名模型" \
    || { bad "同模型未正确拒绝（rc=${RC}）:"; printf '%s\n' "$OUT"; }
done

mk "$IMPL" ''
runlint
[[ "$RC" -eq 1 ]] && ok "缺 review-rev 行 → 拒绝" || bad "缺身份行竟通过"

echo "== 6. 同一原生 session = 同一会话换角色（反例）=="
mk 'review-impl: model=gpt-5.2 family=gpt session=SAME-SESS evidence=docs/reviews/impl-session.md' \
   'review-rev: model=claude-opus-4.6 family=claude session=SAME-SESS evidence=docs/reviews/rev-session.md'
runlint
[[ "$RC" -eq 1 ]] && ok "同一原生 session 实例 → 拒绝" || bad "同 session 竟通过（rc=${RC}）"

echo "== 7. 缺字段 / 缺证据（反例）=="
mk 'review-impl: model=gpt-5.2 family=gpt evidence=docs/reviews/impl-session.md' "$REV"
runlint
{ [[ "$RC" -eq 1 ]] && printf '%s' "$OUT" | grep -Fq '实现者身份字段不全(需model/session/evidence)'; } \
  && ok "缺 session 字段 → 拒绝并列出实际必填字段" || bad "缺 session 拒绝或必填字段文案错误"
mk 'review-impl: family=gpt session=s-impl-1 evidence=docs/reviews/impl-session.md' "$REV"
runlint
{ [[ "$RC" -eq 1 ]] && printf '%s' "$OUT" | grep -Fq '实现者身份字段不全(需model/session/evidence)'; } \
  && ok "缺 model 字段 → 拒绝并列出实际必填字段" || bad "缺 model 拒绝或必填字段文案错误"
mk 'review-impl: model=gpt-5.2 family=gpt session=s-impl-1' "$REV"
runlint
{ [[ "$RC" -eq 1 ]] && printf '%s' "$OUT" | grep -Fq '实现者身份字段不全(需model/session/evidence)'; } \
  && ok "缺 evidence 字段 → 拒绝并列出实际必填字段" || bad "缺 evidence 拒绝或必填字段文案错误"
mk "$IMPL" 'review-rev: model=claude-opus-4.6 evidence=docs/reviews/rev-session.md'
runlint
{ [[ "$RC" -eq 1 ]] && printf '%s' "$OUT" | grep -Fq '审核者身份字段不全(需model/session/evidence)'; } \
  && ok "审核者缺 session → 必填字段文案不含family" || bad "审核者必填字段文案错误"
mk 'review-impl: model=gpt-5.2 family=gpt session=s-impl-1 evidence=docs/reviews/不存在.md' "$REV"
runlint
[[ "$RC" -eq 1 ]] && ok "evidence 路径不存在 → 拒绝" || bad "不存在的证据位置竟通过"

echo
if [[ "$FAILS" -eq 0 ]]; then echo "REVIEW-IDENTITY PASS"; exit 0; else echo "REVIEW-IDENTITY FAIL（${FAILS} 项）"; exit 1; fi
