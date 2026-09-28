#!/usr/bin/env bash
# qwb-dispatch.sh —— JEV 自动派工（opt-in）：读任务简报，让 typesafe.ai System One（jev-latest）
# 从 qwbuddy/dispatch-rules.json 里回答"该走哪条规则"这一个问题；置信度门槛、default 回退、
# 状态判定全部是 jq/bash 纯代码。模型只看到 project + brief + 各规则的 when 文本；
# worker 名等策略数据永不离开本机。agents 把稳定分类映射到可替换的有序工人候选。
#
# 用法:
#   qwb-dispatch.sh <brief文件> [--project <项目根>] [--json]
#     <brief文件>   任务简报（通常就是任务书路径；全文作为 state.task.brief 发给模型）
#     --project     项目根（默认当前目录）：规则在 <项目根>/qwbuddy/dispatch-rules.json，
#                   key 可在 <项目根>/.env；state.task.project 用项目根的目录名
#
# 开关（opt-in）：TYPESAFE_API_KEY 取进程环境变量，否则读 <项目根>/.env（环境变量优先）；
#   两处都无 → stderr 一行 "qwb-dispatch: off"，exit 0，零网络调用。
#   key 纪律（照抄上游）：key 只存一个 shell 变量、经文件描述符 `3< <(...)` 传给 curl 的
#   Authorization 头、启动任何子进程前 unset TYPESAFE_API_KEY；不打印、不落日志、不落盘。
# 规则文件：<项目根>/qwbuddy/dispatch-rules.json（模板：QW buddy 母本仓 templates/dispatch-rules.json）。
#   不存在 → stderr 一行 "no rules"、exit 0、不联网（qwb-run auto 会按默认工人继续派发）；
#   存在但不合 schema → exit 2（配置错误，不许被绕过或静默跳过）。
#   agents 可选，形如 {"implement":["pi","codex"]}；worker 命中 key 时解析角色，
#   否则原样作为字面工人名。候选须在 config.sh + workers.sh 注册，不在 agents_disabled，
#   且 quota-axi --json 的 weekly（无则 session）余量 >= QWB_QUOTA_FLOOR（默认 10）。
#   quota 不可用时明确降级；无 key 时不查询额度。候选不可用的 default/命中角色 exit 2，
#   逐候选说明原因；agents 不递归。具名工人的模型/推理级由 workers.sh 的 argv 固化。
#   QWB_TYPESAFE_BASE 仅供本地假 server 测试覆盖 API 地址，默认 https://api.typesafe.ai。
# 输出（stdout，TOON 风格块）：
#   qwb-dispatch:
#     status: clear | ambiguous | error
#     model / latency_ms / tokens、命中的 rule（when 摘录）与 confidence、probabilities 全文
#     worker: <工人名>            （仅 status: clear 才有）
#     role: <命中的角色名或->      （字面工人名为 -；JSON 同义）
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
TS_BASE=${QWB_TYPESAFE_BASE:-https://api.typesafe.ai}
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
  if [ "$JSON_MODE" -eq 1 ]; then
    jq -cn --arg reason "$1" --arg default "$DEFAULT_WORKER" \
      '{status:"error",role:"-",reason:$reason,default_worker:$default}'
    exit 0
  fi
  printf 'qwb-dispatch:\n  status: error\n  role: -\n  reason: %s\n' "$1"
  exit 0
}
now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time()*1000'; }

BRIEF='' PROJECT_ROOT='' JSON_MODE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) [ $# -ge 2 ] || die "--project 需要一个值"; PROJECT_ROOT=$2; shift 2 ;;
    --json) JSON_MODE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "未知参数 $1" ;;
    *) [ -z "$BRIEF" ] || die "brief 文件只能给一个"; BRIEF=$1; shift ;;
  esac
done

[ -n "$BRIEF" ] || die "需要 brief 文件（见 --help）"
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT=$(pwd)
[ -d "$PROJECT_ROOT" ] || die "项目根不存在: ${PROJECT_ROOT}"
PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd)
RULES_PATH="${PROJECT_ROOT}/qwbuddy/dispatch-rules.json"

# ---- 输入与规则：先验证快照，坏规则不能被无 key 开关绕过 ----
[ -e "$RULES_PATH" ] || [ -L "$RULES_PATH" ] || {
  if [ "$JSON_MODE" -eq 1 ]; then
    echo "qwb-dispatch: no rules（${RULES_PATH} 不存在）" >&2
    printf '%s\n' '{"status":"off","default_worker":"pi"}'
    exit 0
  fi
  no_rules
}
[ -r "$RULES_PATH" ] || die "规则文件不可读: ${RULES_PATH}"
command -v jq >/dev/null 2>&1 || die "需要 jq"
RULES=$(mktemp) || die "mktemp 失败"
RESP_FILE=$(mktemp) || { rm -f "$RULES"; die "mktemp 失败"; }
trap 'rm -f "$RULES" "$RESP_FILE"' EXIT
cp "$RULES_PATH" "$RULES" || die "无法快照规则文件: ${RULES_PATH}"
chmod 400 "$RULES" || die "无法保护规则快照"

# schema 校验：rules 数组、每条非空 when + 合法 worker（非空、无空白/控制字符）、default 存在。
# 坏文件 exit 2——配置错误不许被绕过或静默跳过。
rules_count=$(jq -s 'length' "$RULES" 2>/dev/null) || die "规则文件不是合法 JSON: ${RULES_PATH}"
[ "$rules_count" -eq 1 ] || die "规则文件必须恰好一个顶层 JSON 对象: ${RULES_PATH}"
rules_err=$(jq -r '
  def worker_ok($w): ($w | type) == "string" and ($w | test("^[^[:space:][:cntrl:]]+$"));
  if type != "object" then "顶层必须是对象"
  elif (.rules | type) != "array" then "rules 必须是数组"
  elif any(.rules[]; type != "object") then "每条规则必须是对象"
  elif any(.rules[]; (.when | type) != "string" or (.when | length) == 0) then "每条规则需要非空 when"
  elif any(.rules[]; (worker_ok(.worker) | not)) then "每条规则需要合法 worker（非空、无空白/控制字符）"
  elif ((.default | type) != "object") then "default 必须是对象"
  elif (worker_ok(.default.worker) | not) then "default 需要合法 worker（非空、无空白/控制字符）"
  elif has("agents") and (.agents | type) != "object" then "agents 必须是对象"
  elif any((.agents // {})[]; type != "array") then "agents 值必须是非空候选数组"
  elif any((.agents // {})[]; length == 0 or any(.[]; worker_ok(.) | not)) then "agents 候选需要合法 worker（非空、无空白/控制字符）"
  elif (.agents // {} | keys) as $roles | any((.agents // {})[][]; . as $w | $roles | index($w)) then "agents 值必须是字面工人名，不允许角色套角色"
  elif has("agents_disabled") and (.agents_disabled | type) != "array" then "agents_disabled 必须是数组"
  elif any(.agents_disabled[]?; worker_ok(.) | not) then "agents_disabled 需要合法工人名"
  else empty end
' "$RULES" 2>/dev/null) || die "规则文件不是合法 JSON: ${RULES_PATH}"
[ -z "$rules_err" ] || die "规则文件不合 schema: ${RULES_PATH} - ${rules_err}"
# 先判定开关；off 仍解析 default，但不调用可能联网的 quota-axi。
if [ -z "$TYPESAFE_API_KEY_PRIVATE" ]; then
  TYPESAFE_API_KEY_PRIVATE=$(env_get TYPESAFE_API_KEY "${PROJECT_ROOT}/.env")
fi

# 注册信息来自原有两份 shell 配置，在子 shell 中读取，避免改变本脚本的开关和变量。
# 启动契约的完整验证仍由 qwb-run 执行；这里仅提取候选身份与 quota 的 harness/model。
worker_registry() (
  QWB_WORKERS='' rows='[]'
  # shellcheck source=/dev/null
  [ ! -f "$PROJECT_ROOT/qwbuddy/config.sh" ] || . "$PROJECT_ROOT/qwbuddy/config.sh" >/dev/null || exit 1
  # shellcheck disable=SC2329 # 由下面 source 的 workers.sh 调用
  qwb_worker() {
    local name=${1:-} mode=${2:-} harness model='' w known=0
    [ "$#" -ge 2 ] || return 1
    shift 2
    for w in $QWB_WORKERS; do [ "$w" != "$name" ] || known=1; done
    [ "$known" -eq 1 ] || return 0
    case "$mode" in
      herdr)
        harness=$name
        # 仅以分隔符识别新式行，旧式位置实参仍按 argv 原样透传。
        if [[ "${2:-}" == -- ]]; then
          [[ "${1:-}" =~ ^[a-z][a-z0-9-]*$ && "${2:-}" == -- ]] || return 1
          harness=$1; shift 2
        fi
        ;;
      pane-run) [ "$#" -gt 0 ] || return 1; harness=${1##*/}; shift ;;
      *) return 1 ;;
    esac
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -m|--model) [ "$#" -ge 2 ] || return 1; model=$2; shift ;;
        --model=*) model=${1#*=} ;;
      esac
      shift
    done
    rows=$(jq -cn --argjson rows "$rows" --arg name "$name" --arg harness "$harness" --arg model "$model" \
      '$rows + [{name:$name,harness:$harness,model:$model}]') || return 1
  }
  # shellcheck source=/dev/null
  [ ! -f "$PROJECT_ROOT/qwbuddy/workers.sh" ] || . "$PROJECT_ROOT/qwbuddy/workers.sh" >/dev/null || exit 1
  printf '%s' "$rows"
)

REGISTRY='[]' QUOTA='null' QUOTA_NOTE='' QUOTA_FLOOR=${QWB_QUOTA_FLOOR:-10}
if jq -e '(.agents // {} | length) > 0' "$RULES" >/dev/null; then
  jq -en --arg floor "$QUOTA_FLOOR" '$floor | tonumber | . >= 0 and . <= 100' >/dev/null 2>&1 \
    || die "QWB_QUOTA_FLOOR 必须是 0 到 100 的数值"
  REGISTRY=$(worker_registry) || die "无法读取工人注册配置 config.sh / workers.sh"
  if [ -n "$TYPESAFE_API_KEY_PRIVATE" ]; then
    if ! command -v quota-axi >/dev/null 2>&1; then
      QUOTA_NOTE='quota-axi 未安装，降级为注册+禁名单'
    elif ! QUOTA=$(quota-axi --json 2>/dev/null); then
      QUOTA='null'; QUOTA_NOTE='quota-axi 失败，降级为注册+禁名单'
    elif ! jq -se 'length == 1 and (.[0] |
      (.schemaVersion == 5 or .schemaVersion == 6) and (.providers | type) == "array" and
      (if .schemaVersion == 5 then
         ([.providers[].provider] | length) == ([.providers[].provider] | unique | length)
       else
         ([.providers[] | [.provider, .accountKey]] | length) ==
         ([.providers[] | [.provider, .accountKey]] | unique | length)
       end) and
      all(.providers[]; type == "object" and (.provider | type) == "string" and
        ((.windows // []) | type) == "array" and all(.windows[]?; type == "object")))' \
      <<<"$QUOTA" >/dev/null 2>&1; then
      QUOTA='null'; QUOTA_NOTE='quota-axi 快照不合法，降级为注册+禁名单'
    fi
  fi
fi

# quota_row 的 schema 5/6 绑定规则沿用 firstmate FM_QUOTA_ROW_JQ：6 按 lane/default，
# 5 按 provider。同一窗口种类有多条限制时取最小余量，不能用宽松窗口盖过耗尽窗口。
RESOLUTIONS=$(jq -c --argjson registry "$REGISTRY" --argjson quota "$QUOTA" \
  --arg quota_note "$QUOTA_NOTE" --arg floor "$QUOTA_FLOOR" --arg key_on "${TYPESAFE_API_KEY_PRIVATE:+yes}" '
  def quota_lane($h; $m):
    if $h == "codex" then "codex-home"
    elif ($h == "pi" or $h == "pi-signed") and ($m | contains("/"))
    then ($m | split("/")[0] | if . == "codex-native" then "codex-home" else . end)
    else "" end;
  def quota_row($snapshot; $provider; $lane):
    [$snapshot.providers[]? | select(.provider == $provider)] as $rows |
    if $snapshot.schemaVersion == 6 then
      ([$rows[] | select(.accountKey == $lane)][0] // [$rows[] | select(.accountKey == "default")][0] // null)
    else $rows[0] // null end;
  . as $cfg |
  def candidate($w):
    [$registry[] | select(.name == $w)] as $registered |
    {worker:$w} +
    (if ($registered | length) != 1 then {reason:"未注册或无唯一启动定义"}
     elif ($cfg.agents_disabled // [] | index($w)) != null then {reason:"agents_disabled"}
     elif $key_on == "" then {}
     elif $quota == null then {quota_note:$quota_note}
     else $registered[0] as $reg |
       $reg.harness as $provider |
       quota_row($quota; $provider; quota_lane($reg.harness; $reg.model)) as $row |
       if $row == null then {quota_note:("quota 无匹配 provider/account: " + $provider + "，降级为注册+禁名单")}
       else [$row.windows[]? | select(.kind == "weekly")] as $weekly |
         (if ($weekly | length) > 0 then $weekly else [$row.windows[]? | select(.kind == "session")] end) as $windows |
         [$windows[].percentRemaining | select(type == "number" and . >= 0 and . <= 100)] as $remaining |
         if ($remaining | length) == 0
         then {quota_note:"quota 无有效 weekly/session 余量，降级为注册+禁名单"}
         else ($remaining | min) as $left |
           if $left < ($floor | tonumber) then {reason:("quota " + $windows[0].kind + " " + ($left | tostring) + "% < " + $floor + "%")}
           elif ($remaining | length) < ($windows | length) then {quota_note:"quota 部分窗口余量未知，降级为仅核对已知窗口"}
           else {} end
         end
       end
     end);
  def resolve($w):
    if ($cfg.agents // {} | has($w)) then
      [$cfg.agents[$w][] | candidate(.)] as $candidates |
      ([$candidates[] | select(has("reason") | not)][0] //
       {reason:("role " + $w + " 全部候选不可用：" + ($candidates | map(.worker + "（" + .reason + "）") | join("；")))}) + {role:$w}
    else {worker:$w,role:"-"} end;
  {default:resolve(.default.worker), rules:[.rules[] | resolve(.worker)]}
' "$RULES") || die "解析 agents/quota 失败"
DEFAULT_WORKER=$(jq -r '.default.worker // empty' <<<"$RESOLUTIONS")
[ -n "$DEFAULT_WORKER" ] || die "$(jq -r '.default.reason' <<<"$RESOLUTIONS")"
QUOTA_NOTE=$(jq -r '.default.quota_note // empty' <<<"$RESOLUTIONS")
[ -z "$QUOTA_NOTE" ] || printf 'qwb-dispatch: %s\n' "$QUOTA_NOTE" >&2

# ---- 开关门（opt-in）：环境变量优先，其次 <项目根>/.env；都无 → off，零网络调用 ----
if [ -z "$TYPESAFE_API_KEY_PRIVATE" ]; then
  echo "qwb-dispatch: off（环境变量与 ${PROJECT_ROOT}/.env 都没有 TYPESAFE_API_KEY）" >&2
  if [ "$JSON_MODE" -eq 1 ]; then
    jq -cn --arg default "$DEFAULT_WORKER" '{status:"off",default_worker:$default}'
  fi
  exit 0
fi
[ -r "$BRIEF" ] || die "brief 文件不可读: ${BRIEF}"

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
[ "$HTTP" = 200 ] || emit_error "http ${HTTP}（${LAT_MS} ms）：远端请求失败"

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
  --argjson resolutions "$RESOLUTIONS" --slurpfile resp "$RESP_FILE" --slurpfile rules "$RULES" '
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
    $ev + $resolutions.default + {status: "clear", note: "无规则命中，走 default"}
  else
    $ev + $resolutions.rules[$rule_number - 1] + {status: "clear", note: "规则命中"}
  end') || emit_error "解析失败"
if jq -e '.status == "clear" and has("reason")' <<<"$RESULT" >/dev/null; then
  die "$(jq -r '.reason' <<<"$RESULT")"
fi
QUOTA_NOTE=$(jq -r '.quota_note // empty' <<<"$RESULT")
[ -z "$QUOTA_NOTE" ] || printf 'qwb-dispatch: %s\n' "$QUOTA_NOTE" >&2
RESULT=$(jq '. + {role:(.role // "-")} | del(.quota_note)' <<<"$RESULT") || emit_error "解析失败"

# ---- 输出：机器模式只输出单个 JSON 对象；展示模式保持原有文本 ----
if [ "$JSON_MODE" -eq 1 ]; then
  jq -cn --argjson result "$RESULT" --arg default "$DEFAULT_WORKER" \
    '$result + {default_worker:$default}' || die "JSON 输出失败"
  exit 0
fi
# 动态字段全部压平换行/制表符，防止注入伪行。
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
  "  role: \(show(.role))",
  (if .worker then "  worker: \(.worker | flat)" else empty end)' <<<"$RESULT") || emit_error "输出渲染失败"
printf '%s\n' "$TEXT"
exit 0
