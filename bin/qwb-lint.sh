#!/usr/bin/env bash
# qwb-lint.sh —— QW buddy 自身规范检查：能自动检查的规范不只写在纸上
set -uo pipefail

usage() {
  cat <<'EOF'
用法: qwb-lint.sh [--project <根>]

逐项检查并输出 PASS/FAIL，任一 FAIL → 退出码 1：
  1. 文档承诺的脚本必须存在（QWBUDDY.md 与 docs/DESIGN.md 点名的 qwb-*.sh；qwb-init.sh 为母本仓专用安装器除外）
  2. tasks/*.md 的 state: 值 ∈ running|blocked|needs-decision|done|verified（有字段但值为空同样 FAIL；无字段的非任务文档跳过）
  3. 母本仓双配置门一致（仅母本仓布局：qwb.config.sh 与 qwbuddy/config.sh 同时存在时，
     两者的 QWB_GATE_FAST/QWB_GATE_FULL 必须相同——qwb-test.sh 只读 qwbuddy/config.sh，
     不一致 = 改 qwb.config.sh 的门不生效；只有一份配置时不适用、不输出）
  4. config 无死键（QWB_X=… 与 export QWB_X=… 都算声明；非注释行出现 $QWB_X / ${QWB_X} 才算被读取）
  5. 无「变量后紧跟非 ASCII」写法（应写成 ${VAR} 形式；扫描 bin/*.sh 全部脚本）
  6. 质量门已声明（QWB_GATE_FAST / QWB_GATE_FULL 均非空）
  7. 已派发任务书（带 scenarios-fp:）的验收场景仍在且指纹未变（派发后改场景即 FAIL）；
     带 scenarios-revised: 修订记录的票，再核对最新一条记录的 new= 指纹 == 当前基线
  8. 需独立审核的票（review-required: yes）：review-impl:/review-rev: 各行须有
     model/family/session/evidence、family 非 unknown 且两方不同、原生 session 不同实例；
     无标记的普通票不启用本检查
  9. 任务书正文无占位状态行（列首 working/done/blocked/needs-decision: 带未填占位符 <…>
     的行，是把模板示例当真实状态行抄进了票）——只警告不 FAIL：不补历史票，
     但列首占位行会污染值守指纹与疑点门，写票时必须删掉或缩进

布局：装了 qwbuddy/ 的项目 → qwbuddy/QWBUDDY.md + qwbuddy/bin/；
      母本仓（模板源）       → templates/QWBUDDY.md + bin/，配置回退 qwb.config.sh。

选项:
  --project <根>    项目根（默认：当前目录）
  -h, --help        显示本帮助
EOF
}

PROJECT_ROOT="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-lib.sh"
[[ -f "$LIB" ]] || { echo "错误：找不到共享库 ${LIB}——安装副本不完整，请用母本仓重跑 bin/qwb-init.sh 更新（幂等）" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

# 布局识别：安装版（qwbuddy/）或母本仓（templates/ + bin/）
DOCS=()
if [[ -f "$PROJECT_ROOT/qwbuddy/QWBUDDY.md" ]]; then
  BINDIR="$PROJECT_ROOT/qwbuddy/bin"; DOCS+=("$PROJECT_ROOT/qwbuddy/QWBUDDY.md")
elif [[ -f "$PROJECT_ROOT/templates/QWBUDDY.md" ]]; then
  BINDIR="$PROJECT_ROOT/bin"; DOCS+=("$PROJECT_ROOT/templates/QWBUDDY.md")
else
  echo "错误：${PROJECT_ROOT} 下找不到 QWBUDDY.md（qwbuddy/ 或 templates/）" >&2; exit 2
fi
[[ -f "$PROJECT_ROOT/docs/DESIGN.md" ]] && DOCS+=("$PROJECT_ROOT/docs/DESIGN.md")

shopt -s nullglob
binsh=( "$BINDIR"/*.sh )

echo "== 1. 文档承诺的脚本必须存在 =="
# qwb-init.sh 是母本仓专用安装器、不装进目标项目 → 从「文档点名必存在」清单剔除
names="$(grep -ohE 'qwb-[a-z0-9-]+\.sh' "${DOCS[@]}" | sort -u | grep -v '^qwb-init\.sh$')"
missing=""
for n in $names; do
  [[ -f "$BINDIR/$n" ]] || missing="${missing} ${n}"
done
if [[ -z "$missing" ]]; then
  pass "文档点名的 $(printf '%s' "$names" | wc -w | tr -d ' ') 个脚本在 ${BINDIR} 全部存在"
else
  fail "文档点名但 ${BINDIR} 缺失:${missing}"
fi

echo "== 2. 账本 state 合法 =="
bad_states=""
for f in "$PROJECT_ROOT"/tasks/*.md; do
  grep -q '^state:' "$f" || continue   # 无 state 字段行 → 非任务书（如 lessons.md），跳过
  st="$(qwb_task_state "$f")"
  if [[ -z "$st" ]]; then
    bad_states="${bad_states} $(basename "$f")=<空值>"   # 有 state: 字段但值为空 → FAIL
    continue
  fi
  case "$st" in
    running|blocked|needs-decision|done|verified) ;;
    *) bad_states="${bad_states} $(basename "$f")=${st}" ;;
  esac
done
if [[ -z "$bad_states" ]]; then
  pass "tasks/*.md 的 state 值全部合法"
else
  fail "非法 state:${bad_states}"
fi

if [[ -f "$PROJECT_ROOT/templates/QWBUDDY.md" && -f "$PROJECT_ROOT/qwb.config.sh" && -f "$PROJECT_ROOT/qwbuddy/config.sh" ]]; then
  echo "== 3. 母本仓双配置门一致（仅母本仓布局）=="
  # 母本仓里 qwb.config.sh（跟踪）与主控开局建的 qwbuddy/config.sh（未跟踪，qwb-lock/wake 要
  # qwbuddy/ 目录）同时存在时，qwb-test.sh 优先读后者——两份 QWB_GATE_* 不一致会让「改 qwb.config.sh
  # 的门不生效」且无人知道。只有一份配置时不适用、不输出（连节标题也不打印）。
  gate_of() { # $1=配置文件 $2=键名 → 打印该配置里此键的值（未设/空均打空串）；子 shell 不污染当前环境
    # shellcheck disable=SC1090,SC1091  # 动态路径，故意不 follow
    ( . "$1" >/dev/null 2>&1; eval "printf '%s' \"\${$2:-}\"" )
  }
  a_fast="$(gate_of "$PROJECT_ROOT/qwb.config.sh" QWB_GATE_FAST)"
  a_full="$(gate_of "$PROJECT_ROOT/qwb.config.sh" QWB_GATE_FULL)"
  b_fast="$(gate_of "$PROJECT_ROOT/qwbuddy/config.sh" QWB_GATE_FAST)"
  b_full="$(gate_of "$PROJECT_ROOT/qwbuddy/config.sh" QWB_GATE_FULL)"
  if [[ "$a_fast" == "$b_fast" && "$a_full" == "$b_full" ]]; then
    pass "qwb.config.sh 与 qwbuddy/config.sh 的质量门一致"
  else
    fail "母本仓双配置质量门不一致（qwb-test.sh 只读 qwbuddy/config.sh，改 qwb.config.sh 不生效）：
  QWB_GATE_FAST  qwb.config.sh=${a_fast:-（空）} | qwbuddy/config.sh=${b_fast:-（空）}
  QWB_GATE_FULL  qwb.config.sh=${a_full:-（空）} | qwbuddy/config.sh=${b_full:-（空）}"
  fi
fi

echo "== 4. config 无死键 =="
CONF="$PROJECT_ROOT/qwbuddy/config.sh"
[[ -f "$CONF" ]] || CONF="$PROJECT_ROOT/qwb.config.sh"
if [[ -f "$CONF" ]]; then
  dead=""
  if [[ ${#binsh[@]} -eq 0 ]]; then
    dead="（${BINDIR} 无任何脚本，所有键皆为死键）"
  else
    # 声明形式：QWB_X=… 与 export QWB_X=… 都算
    while IFS= read -r k; do
      [[ -n "$k" ]] || continue
      # 「被引用」= 非注释行里出现真实变量读取 $QWB_X / ${QWB_X}（R2-M3）；
      # 纯赋值（QWB_X=…）、不带 $ 的字面量（echo QWB_X）、整行注释都不算
      grep -hE '\$[{]?'"$k"'([^A-Za-z0-9_]|$)' "${binsh[@]}" 2>/dev/null \
        | grep -vE '^[[:space:]]*#' | grep -q . \
        || dead="${dead} ${k}"
    done < <(sed 's/^export[[:space:]][[:space:]]*//' "$CONF" | sed -n 's/^\(QWB_[A-Z_]*\)=.*/\1/p')
  fi
  if [[ -z "$dead" ]]; then
    pass "${CONF} 的 QWB_* 键全部被 ${BINDIR} 引用"
  else
    fail "死配置（bin/ 无引用）:${dead}"
  fi
else
  fail "找不到配置文件（试过 qwbuddy/config.sh 与 qwb.config.sh）"
fi

echo "== 5. 变量后紧跟非 ASCII 字符 =="
hits=""
[[ ${#binsh[@]} -gt 0 ]] \
  && hits="$(perl -ne 'print "$ARGV:$.: $&\n" while /\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/g' "${binsh[@]}" 2>/dev/null)"
if [[ -z "$hits" ]]; then
  pass "${BINDIR}/*.sh 无该写法"
else
  fail "发现该写法（应写成 \${VAR} 形式）：
${hits}"
fi

echo "== 6. 质量门已声明 =="
# 门未声明（空值）是配置缺失，不许静默当绿：新装项目一跑 lint 就会被提醒
if [[ -f "$CONF" ]] && (
  # shellcheck source=/dev/null
  . "$CONF" >/dev/null 2>&1
  [[ -n "${QWB_GATE_FAST:-}" && -n "${QWB_GATE_FULL:-}" ]]
); then
  pass "QWB_GATE_FAST / QWB_GATE_FULL 均已声明"
else
  fail "质量门未声明：${CONF} 里 QWB_GATE_FAST / QWB_GATE_FULL 须非空（按本项目布局填写，示例见该文件注释）"
fi

echo "== 7. 已派发任务书的验收场景与冻结 =="
# 验收场景块界定与 qwb-run.sh 派发门一致；带 scenarios-fp: 的任务书（经派发门写过基线的）
# 重算当前块指纹比对，不一致即 FAIL；有 dispatch: 但无 scenarios-fp: 的是旧制派发，警告不 FAIL。
# 带 scenarios-revised: 修订记录的票（经 --revise-scenarios 显式改过场景）：最新一条记录的
# new= 指纹必须等于当前基线——没有修订参数的场景差异仍然 FAIL（区分显式改票与无痕偷改）。
scen_bad=""
for f in "$PROJECT_ROOT"/tasks/*.md; do
  grep -q '^state:' "$f" || continue
  declared_fp="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
  if [[ -z "$declared_fp" ]]; then
    grep -q '^dispatch:' "$f" \
      && echo "警告：$(basename "$f") 有 dispatch: 但无 scenarios-fp（旧制派发，无冻结基线）" >&2
    continue
  fi
  blk="$(qwb_scenario_block "$f")"
  if [[ -z "$blk" ]]; then
    scen_bad="${scen_bad} $(basename "$f")(验收场景块缺失)"
    continue
  fi
  # 存在性与失败路径同派发门标准
  if ! { printf '%s\n' "$blk" | grep -q 'Given' \
      && printf '%s\n' "$blk" | grep -q 'When' \
      && printf '%s\n' "$blk" | grep -q 'Then'; } \
    && [[ "$(printf '%s\n' "$blk" | grep -cE '^#{1,6}[[:space:]]+user_' || true)" -lt 2 ]]; then
    scen_bad="${scen_bad} $(basename "$f")(无可识别场景)"
    continue
  fi
  printf '%s\n' "$blk" | grep -E '^#{1,6}|^[[:space:]]*Then' \
    | grep -qiE '失败|拒绝|报错|异常|负例|非法|fail|error' \
    || { scen_bad="${scen_bad} $(basename "$f")(无失败路径场景)"; continue; }
  cur_fp="$(printf '%s' "$blk" | shasum | cut -d' ' -f1)"
  [[ "$cur_fp" == "$declared_fp" ]] \
    || scen_bad="${scen_bad} $(basename "$f")(验收场景在派发后被改动)"
  # 修订记录核对：最新一条 scenarios-revised: 的 new= 指纹 == 当前基线
  lastrev="$(grep -E '^working:[[:space:]]*scenarios-revised:' "$f" | tail -1 || true)"
  if [[ -n "$lastrev" ]]; then
    revnew="$(printf '%s' "$lastrev" | sed -n 's/^working:[[:space:]]*scenarios-revised:[[:space:]]*old=[0-9a-f]\{40\}[[:space:]]\{1,\}new=\([0-9a-f]\{40\}\).*/\1/p')"
    [[ -n "$revnew" && "$revnew" == "$declared_fp" ]] \
      || scen_bad="${scen_bad} $(basename "$f")(最新修订记录 new= 指纹与当前基线不一致)"
  fi
done
if [[ -z "$scen_bad" ]]; then
  pass "带 scenarios-fp 的任务书场景均未在派发后被改动"
else
  fail "验收场景检查失败:${scen_bad}"
fi

echo "== 8. 需独立审核票的审核身份可核验 =="
# 只对显式标记 review-required: yes 的票启用——普通票零新增负担、不补历史票。
# 结构校验：review-impl:/review-rev: 两行各自 model/family/session/evidence 齐全；
# family 非 unknown、两方 family 不同、两方原生 session 不是同一实例。
# cli=/provider= 只是附记，绝不充当 family（同 CLI 不同家族合法，不同 CLI 同家族拒绝）。
# 边界：只做声明与证据引用的结构校验——不访问模型服务、不猜型号、不防伪造；
# 无法确认一律报缺证据 FAIL，不假绿。
rid_val() { # $1=身份行原文 $2=键名 → 取「键=非空白值」（行内以空白分隔）
  printf '%s' "$1" | sed -n "s/.*[[:space:]]${2}=\([^[:space:]]*\).*/\1/p" | head -1
}
rid_bad=""; rid_n=0
for f in "$PROJECT_ROOT"/tasks/*.md; do
  grep -q '^state:' "$f" || continue
  grep -qE '^review-required:[[:space:]]*yes[[:space:]]*$' "$f" || continue
  rid_n=$((rid_n+1)); n="$(basename "$f")"; b=""
  # 跳过围栏/模板示例：占位符 <...> 开头的身份行不算真实记录
  il="$(grep -E '^review-impl:' "$f" | grep -v '<' | head -1)"
  rl="$(grep -E '^review-rev:' "$f" | grep -v '<' | head -1)"
  if [[ -z "$il" || -z "$rl" ]]; then
    rid_bad="${rid_bad} ${n}(缺 review-impl/review-rev 身份行)"; continue
  fi
  im="$(rid_val "$il" model)";   ifam="$(rid_val "$il" family)"
  isess="$(rid_val "$il" session)"; iev="$(rid_val "$il" evidence)"
  rm="$(rid_val "$rl" model)";   rfam="$(rid_val "$rl" family)"
  rsess="$(rid_val "$rl" session)"; rev="$(rid_val "$rl" evidence)"
  [[ -n "$im" && -n "$ifam" && -n "$isess" && -n "$iev" ]] \
    || b="${b} 实现者身份字段不全(需model/family/session/evidence)"
  [[ -n "$rm" && -n "$rfam" && -n "$rsess" && -n "$rev" ]] \
    || b="${b} 审核者身份字段不全(需model/family/session/evidence)"
  ifam_l="$(printf '%s' "$ifam" | tr '[:upper:]' '[:lower:]')"
  rfam_l="$(printf '%s' "$rfam" | tr '[:upper:]' '[:lower:]')"
  [[ "$ifam_l" == "unknown" ]] && b="${b} 身份未确认(实现者family=unknown)"
  [[ "$rfam_l" == "unknown" ]] && b="${b} 身份未确认(审核者family=unknown)"
  if [[ -n "$ifam_l" && -n "$rfam_l" && "$ifam_l" != "unknown" && "$rfam_l" != "unknown" ]]; then
    [[ "$ifam_l" == "$rfam_l" ]] && b="${b} 实现者与审核者同家族(${ifam_l})"
  fi
  [[ -n "$isess" && -n "$rsess" && "$isess" == "$rsess" ]] \
    && b="${b} 两方同一原生session实例(${isess})"
  for ev in "$iev" "$rev"; do
    case "$ev" in
      /*|*/*) [[ -f "$ev" || -f "$PROJECT_ROOT/$ev" ]] || b="${b} 证据位置不存在(${ev})" ;;
    esac
  done
  [[ -n "$b" ]] && rid_bad="${rid_bad} ${n}(${b# })"
done
if [[ "$rid_n" -eq 0 ]]; then
  pass "无 review-required 票（普通票不启用审核身份检查）"
elif [[ -z "$rid_bad" ]]; then
  pass "${rid_n} 张需独立审核票的身份记录可核验"
else
  fail "审核身份检查失败:${rid_bad}"
fi

echo "== 9. 任务书正文无占位状态行（只警告，不 FAIL）=="
# 列首 working/done/blocked/needs-decision: 行里带 <…> 占位符 = 模板示例被当成真实状态行抄进了票：
# 会被值守指纹与疑点门当真。缩进行不算列首（模板示例必须缩进，见 TASK.md §4）。
# 只警告不 FAIL：本仓历史票已有这种行，不补历史票。
placeholder_warn=""
for f in "$PROJECT_ROOT"/tasks/*.md; do
  grep -q '^state:' "$f" || continue
  while IFS= read -r line; do
    placeholder_warn="${placeholder_warn} $(basename "$f")（占位状态行: ${line}）"
  done < <(grep -E '^(working|done|blocked|needs-decision):.*<[^>]*>' "$f" || true)
done
if [[ -z "$placeholder_warn" ]]; then
  pass "任务书正文无列首占位状态行"
else
  echo "警告：发现列首占位状态行（不算 FAIL，但值守指纹与疑点门会把它们当真，建议删除或缩进）：${placeholder_warn}" >&2
  pass "占位状态行仅警告不 FAIL（详情见上方 stderr；新写票必须删掉或缩进，不补历史票）"
fi

echo
if [[ "$FAILS" -eq 0 ]]; then echo "LINT PASS"; exit 0; else echo "LINT FAIL（${FAILS} 项）"; exit 1; fi
