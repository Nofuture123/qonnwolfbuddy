#!/usr/bin/env bash
# qwb-dispatch.sh —— JEV 自动派工（opt-in）：读任务简报，让 typesafe.ai System One（jev-latest）
# 从 config/dispatch-rules.json 里回答"该走哪条规则"这一个问题；置信度门槛、default 回退、
# 状态判定全部是 jq/bash 纯代码。模型只看到 project + brief + 各规则的 when 文本；
# worker 名等策略数据永不离开本机。
# 移植自 firstmate bin/fm-dispatch-resolve.sh（砍掉机队特有部分：多 profile、quota-axi、
# floor、spendPriority、captain 审批流——qwb 派工只是"选一个工人"）。
#
# 用法:
#   qwb-dispatch.sh <brief文件> [--project <项目根>]
#     <brief文件>   任务简报（通常就是任务书路径；全文作为 state.task.brief 发给模型）
#     --project     项目根（默认当前目录）：规则在 <项目根>/config/dispatch-rules.json，
#                   key 可在 <项目根>/.env；state.task.project 用项目根的目录名
#
# 开关（opt-in）：TYPESAFE_API_KEY 取进程环境变量，否则读 <项目根>/.env（环境变量优先）；
#   两处都无 → stderr 一行 "qwb-dispatch: off"，exit 0，零网络调用，行为与没有本工具完全一致。
#   key 纪律（照抄上游）：key 只存一个 shell 变量、经文件描述符 `3< <(...)` 传给 curl 的
#   Authorization 头、启动任何子进程前 unset TYPESAFE_API_KEY；不打印、不落日志、不落盘。
# 规则文件：<项目根>/config/dispatch-rules.json（模板：QW buddy 母本仓 templates/dispatch-rules.json）。
#   不存在 → stderr 一行 "no rules"、exit 0、不联网（qwb-run auto 会按默认工人继续派发）；
#   存在但不合 schema → exit 2（配置错误，不许被绕过或静默跳过）。
# 输出（stdout，TOON 风格块）：
#   qwb-dispatch:
#     status: clear | ambiguous | error
#     model / latency_ms / tokens、命中的 rule（when 摘录）与 confidence、probabilities 全文
#     worker: <工人名>            （仅 status: clear 才有）
#     reason: <非 clear 的原因>
#   confidence < 0.6 → ambiguous（附完整 probabilities，人工裁决）；网络/API 错/响应不合法
#   → error；除 usage/配置错误（exit 2）外一律 exit 0——派工流程永不被本工具卡死。
set -u

# key 只进这个私有变量：先摘走导出属性、再 unset 环境名，子进程环境永远看不到 key
TYPESAFE_API_KEY_PRIVATE=${TYPESAFE_API_KEY:-}
export -n TYPESAFE_API_KEY_PRIVATE 2>/dev/null || true
unset TYPESAFE_API_KEY

CONFIDENCE_FLOOR=0.6
TS_MODEL=jev-latest
TS_BASE=https://api.typesafe.ai
TS_TIMEOUT=5
DEFAULT_WHEN="No listed rule applies to this task."

usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }
die() { printf '错误: %s\n' "$1" >&2; exit 2; }

# .env 里取一行 key（无文件/无该行输出空）；语义照抄上游 fmx_env_get
env_get() {
  local key=$1 file=$2 line val
  [ -f "$file" ] || return 0
  line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file" 2>/dev/null | tail -n1) || return 0
  [ -n "$line" ] || return 0
  val=${line#*=}
  val=${val#"${val%%[![:space:]]*}"}   # 去首空白
  val=${val%"${val##*[![:space:]]}"}   # 去尾空白（含 CR）
  case "$val" in
    \"*\") val=${val#\"}; val=${val%\"} ;;
    \'*\') val=${val#\'}; val=${val%\'} ;;
  esac
  printf '%s' "$val"
}

no_rules() {
  echo "qwb-dispatch: no rules（${RULES_PATH} 不存在——模板在 QW buddy 母本仓 templates/dispatch-rules.json）" >&2
  exit 0
}
emit_error() {
  echo "qwb-dispatch: error（$1）" >&2
  printf 'qwb-dispatch:\n  status: error\n  reason: %s\n' "$1"
  exit 0
}
now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time()*1000'; }

BRIEF='' PROJECT_ROOT=''
while [ $# -gt 0 ]; do
  case "$1" in
    --project) [ $# -ge 2 ] || die "--project 需要一个值"; PROJECT_ROOT=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "未知参数 $1" ;;
    *) [ -z "$BRIEF" ] || die "brief 文件只能给一个"; BRIEF=$1; shift ;;
  esac
done

[ -n "$BRIEF" ] || die "需要 brief 文件（见 --help）"
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT=$(pwd)
[ -d "$PROJECT_ROOT" ] || die "项目根不存在: ${PROJECT_ROOT}"
PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd)
RULES_PATH="${PROJECT_ROOT}/config/dispatch-rules.json"

# ---- 开关门（opt-in）：环境变量优先，其次 <项目根>/.env；都无 → off，零网络调用 ----
if [ -z "$TYPESAFE_API_KEY_PRIVATE" ]; then
  TYPESAFE_API_KEY_PRIVATE=$(env_get TYPESAFE_API_KEY "${PROJECT_ROOT}/.env")
fi
if [ -z "$TYPESAFE_API_KEY_PRIVATE" ]; then
  echo "qwb-dispatch: off（环境变量与 ${PROJECT_ROOT}/.env 都没有 TYPESAFE_API_KEY）" >&2
  exit 0
fi

# ---- 输入与规则 ----
[ -r "$BRIEF" ] || die "brief 文件不可读: ${BRIEF}"
[ -e "$RULES_PATH" ] || [ -L "$RULES_PATH" ] || no_rules
[ -r "$RULES_PATH" ] || die "规则文件不可读: ${RULES_PATH}"
command -v jq >/dev/null 2>&1 || die "需要 jq"
RULES=$(mktemp) || die "mktemp 失败"
RESP_FILE=$(mktemp) || { rm -f "$RULES"; die "mktemp 失败"; }
trap 'rm -f "$RULES" "$RESP_FILE"' EXIT
cp "$RULES_PATH" "$RULES" || die "无法快照规则文件: ${RULES_PATH}"
chmod 400 "$RULES" || die "无法保护规则快照"

# schema 校验：rules 数组、每条非空 when + 合法 worker（非空、无空白/控制字符）、default 存在。
# 坏文件 exit 2——配置错误不许被绕过或静默跳过。
rules_err=$(jq -r '
  def worker_ok($w): ($w | type) == "string" and ($w | test("^[^[:space:][:cntrl:]]+$"));
  if type != "object" then "顶层必须是对象"
  elif (.rules | type) != "array" then "rules 必须是数组"
  elif any(.rules[]; type != "object") then "每条规则必须是对象"
  elif any(.rules[]; (.when | type) != "string" or (.when | length) == 0) then "每条规则需要非空 when"
  elif any(.rules[]; (worker_ok(.worker) | not)) then "每条规则需要合法 worker（非空、无空白/控制字符）"
  elif ((.default | type) != "object") then "default 必须是对象"
  elif (worker_ok(.default.worker) | not) then "default 需要合法 worker（非空、无空白/控制字符）"
  else empty end
' "$RULES" 2>/dev/null) || die "规则文件不是合法 JSON: ${RULES_PATH}"
[ -z "$rules_err" ] || die "规则文件不合 schema: ${RULES_PATH} - ${rules_err}"

# ---- 请求：与上游同形。state 只带 project 名 + brief 全文；一个 choice 问题，
# 选项 = 每条规则的 when + 固定 default 选项。模型看不到 worker 名。 ----
REQUEST=$(jq -n --rawfile brief "$BRIEF" --arg project "$(basename "$PROJECT_ROOT")" --arg model "$TS_MODEL" \
  --arg none_criterion "$DEFAULT_WHEN" --slurpfile rules "$RULES" '
  ($rules[0]) as $cfg |
  ($cfg.rules | to_entries | map({key: ("rule_" + ((.key + 1) | tostring)), value: .value.when}) | from_entries) as $criteria |
  {
    model: $model,
    state: {task: {project: $project, brief: $brief}},
    questions: {
      rule: {
        type: "choice",
        instructions: "Which ONE dispatch rule best fits `task` (read `task.brief` and `task.project`)? Each option is the rule'"'"'s own matching condition; pick `default` when no rule'"'"'s condition is met, including when a rule'"'"'s own exemption text excludes this task.",
        criteria: ($criteria + {default: $none_criterion})
      }
    }
  }')

T0=$(now_ms)
HTTP=$(printf '%s' "$REQUEST" | curl -sS --max-time "$TS_TIMEOUT" -o "$RESP_FILE" -w '%{http_code}' \
  -X POST "$TS_BASE/v1/systemone" -H 'Content-Type: application/json' \
  -H @/dev/fd/3 3< <(printf 'Authorization: Bearer %s\n' "$TYPESAFE_API_KEY_PRIVATE") \
  --data-binary @- 2>/dev/null) || HTTP=000
T1=$(now_ms)
LAT_MS=$(( T1 - T0 ))
[ "$HTTP" = 200 ] || emit_error "http ${HTTP}（${LAT_MS} ms）: $(head -c 200 "$RESP_FILE" 2>/dev/null | tr '\n' ' ')"

# 响应校验（照抄上游）：choice 是字符串、confidence ∈ [0,1]、probabilities 恰好覆盖全部选项
# 且各项 ∈ [0,1]、和 ≈ 1（±0.01）、usage 缺省或为数值对象。任一不符 → error（exit 0）。
jq -e --slurpfile rules "$RULES" '
  (($rules[0].rules | to_entries | map("rule_" + ((.key + 1) | tostring))) + ["default"] | sort) as $choices |
  (.answers.rule.choice | type) == "string" and
  (.answers.rule.confidence | type) == "number" and
  .answers.rule.confidence >= 0 and .answers.rule.confidence <= 1 and
  (.answers.rule.probabilities | type) == "object" and
  ((.answers.rule.probabilities | keys | sort) == $choices) and
  all(.answers.rule.probabilities[]; type == "number" and . >= 0 and . <= 1) and
  ((.answers.rule.probabilities | [.[]] | add) as $total | $total >= 0.99 and $total <= 1.01) and
  ((has("usage") | not) or
    ((.usage | type) == "object" and
     (.usage.input_tokens | type) == "number" and
     (.usage.output_tokens | type) == "number"))' \
  "$RESP_FILE" >/dev/null 2>&1 || emit_error "响应不是合法的 rule Choice 应答"

# ---- 后处理（纯 jq，无模型参与）：choice 不在选项集 / 低置信度 / 命中规则 / default ----
RESULT=$(jq -n --arg floor "$CONFIDENCE_FLOOR" --argjson lat "$LAT_MS" --arg none_criterion "$DEFAULT_WHEN" \
  --slurpfile resp "$RESP_FILE" --slurpfile rules "$RULES" '
  ($resp[0]) as $r | ($rules[0]) as $cfg | ($r.answers.rule) as $a |
  ($a.choice) as $choice |
  (if ($choice | test("^rule_[1-9][0-9]*$"))
   then ($choice | ltrimstr("rule_") | tonumber) else null end) as $rule_number |
  (if $choice == "default" then null
   elif $rule_number != null and $rule_number <= ($cfg.rules | length) then $cfg.rules[$rule_number - 1]
   else null end) as $rule |
  {
    model: $r.model, latency_ms: $lat, tokens: ($r.usage // null),
    rule: $choice,
    rule_when: ((if $rule == null then $none_criterion else $rule.when end) | .[0:60]),
    confidence: $a.confidence, probabilities: $a.probabilities
  } as $ev |
  if $choice != "default" and $rule == null then
    $ev + {status: "error", reason: ("rule " + $choice + " 不在规则文件里")}
  elif $a.confidence < ($floor | tonumber) then
    $ev + {status: "ambiguous", reason: ("confidence " + ($a.confidence | tostring) + " 低于门槛 " + $floor)}
  elif $choice == "default" then
    $ev + {status: "clear", worker: $cfg.default.worker, note: "无规则命中，走 default"}
  else
    $ev + {status: "clear", worker: $rule.worker, note: "规则命中"}
  end') || emit_error "解析失败"

# ---- 输出（TOON 风格）：动态字段全部压平换行/制表符，防止注入伪行 ----
TEXT=$(jq -r '
  def flat: tostring | gsub("[\t\r\n]"; " ");
  def show($v): ($v // "-") | flat;
  "qwb-dispatch:",
  "  status: \(.status | flat)",
  "  model: \(show(.model))   latency_ms: \(show(.latency_ms))   tokens: \(show(.tokens.input_tokens))/\(show(.tokens.output_tokens))",
  "  rule: \(.rule | flat) (\(.rule_when | flat))   confidence: \(.confidence | flat)",
  "  probabilities: \([.probabilities | to_entries[] | "\(.key | flat)=\(.value | flat)"] | join(" "))",
  (if .reason then "  reason: \(.reason | flat)" else empty end),
  (if .note then "  note: \(.note | flat)" else empty end),
  (if .worker then "  worker: \(.worker | flat)" else empty end)' <<<"$RESULT") || emit_error "输出渲染失败"
printf '%s\n' "$TEXT"
exit 0
