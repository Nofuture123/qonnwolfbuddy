#!/usr/bin/env bash
# qwb-wake.sh —— 值守：以账本未结项为准，叫醒主控窗口；同一项进展未变不重复叫
set -euo pipefail
export LC_ALL=C  # 损坏字节不应让未结票从值守列表消失。

usage() {
  cat <<'EOF'
用法: qwb-wake.sh [选项]

已迁票（qwb-collab-v1）：同票持久handoff，完整event_id集合确认；旧wake指纹不消费待办。
  API交付只记transport，received/accepted/handled由接收方分别确认；controller通道可按04授权claim直接门铃本代门禁。
  每event正常门铃至多3次；未接收的角色交接耗尽后升级主控一次，主控最短30分钟低频重提。
  accepted有活动/合理wait不误催；计数封顶3，通知与纯进度均不冒充received/handled。
  所有宿主共用内核监督owner锁，第二实例显式拒绝；旧票仍使用下述兼容指纹。

循环：读账本列未结项 → 有需主控处理的新事实或 running 票超期无进展 → **只发一条** herdr pane run（多票拼进同一条文本）叫醒主控 → 等事件或超时 → 再来。
未结项 = 任务书头部 state ∈ {running, blocked, needs-decision}；非法 state 或账本 UTF-8 损坏
         也按 needs-decision 叫主控查看（state 合法值仍只有五个）。
去重：fp = sha1(state 值 + "\n" + 最后一条 working:/done:/blocked:/needs-decision: 行原文，无则空串；
     running 票判定为工人丢失时再追加 "\nlost=<pane>" 段——工人一消失指纹变一次、叫一次，之后指纹不变不重叫）；
     叫醒后写 wake: <时间戳> state=<值> fp=<sha1>。fp 未变不再叫；无 fp= 的旧 wake 行视为指纹不同。
     未迁 running 票工人未丢失且末行是 working: 时，只记进度，不因指纹变化叫醒或写 wake 行。
     投递成功才逐票写 wake 行，失败一行都不写（下轮重试）。
兜底重叫：仅对 state=running 生效——fp 未变或上述 working: 进度票，距票文件修改时间与最近一条
     wake: 时间戳中较晚者 ≥ config.sh 的 QWB_REWAKE_MS（>0 才启用，quiet 下关闭）→ 再叫一次；
     工人写进度会推迟兜底，blocked/needs-decision 指纹未变即跳过；进度票无 wake 行时只取文件修改时间，已有 wake 行的时间戳解析失败才按超期处理。
投递失败：不写 wake 行、报 stderr、继续处理下一项；值守主循环不因单次投递失败退出。
等待：一个共用订阅连接覆盖全部登记工人及角色，收到subscription_started后再level reconcile。
     事件只加速MD读回，不消费业务事实；断流/无能力每至多1秒扫描并重连，如实报缺口。
     --block到期仍是124等待结束，不认作取消/死亡；--once/--dry-run不开订阅。

选项:
  --project <根>      项目根（默认：当前目录）
  --pane <pane_id>    主控 pane（默认：$QWB_CONTROLLER_PANE 或 config.sh QWB_CONTROLLER_PANE）
  --interval <毫秒>   事件等待的超时（默认：config.sh QWB_WAKE_INTERVAL_MS，否则 120000）
  --once              只检查一轮就退出
  --dry-run           只报告未结项，不叫、不写 wake 行
  --ensure            幂等确保值守在跑：建/复用一个可见 shell tab；新建时 tab 落在项目自己的
                      workspace（config.sh 的 QWB_WORKSPACE 优先，查不到即拒绝；未声明则按
                      worktree.repo_root 匹配项目根；都没有才落调用者 workspace 并警告）；
                      判定依据是 pane 前台进程组里真实的 qwb-wake.sh 进程 + 项目路径，
                      不凭 pane 存在或名字相似；查不到/多实例明确报错，不擅自多开
  --block             前台阻塞值守（无窗口：不 pane run、不开 tab，供 Claude Code Stop hook /
                      Codex 前台 checkpoint 等主控 harness 自己调用）：每轮判定前先复核主控锁
                      （qwbuddy/.controller.lock/owner 末字段 ≠ 本进程 HERDR_PANE_ID 或锁不存在
                      → exit 0 不消费唤醒；HERDR_PANE_ID 为空则跳过复核），之后轮询账本，
                      有可动作变化 → stdout 打印摘要 + 往对应票追加 wake: 行 + 退出码 2；
                      账本无未结项 → 退出码 0；--max-ms 到期无变化 → 退出码 124；其他非 0 = 错误。
                      去重与时间兑底逻辑与循环模式完全共用（wake: 行状态记在同一本账本上，
                      两种值守形态不会互相重复叫）
  --max-ms <毫秒>     --block 的单轮阻塞上限（毫秒，超时一律毫秒）；不给则无限阻塞直到 exit 2 或 0
  --check             只报告本项目值守健康并退出：运行 / 未运行 / 未知（不写账本不改状态）
  -h, --help          显示本帮助
EOF
}

ORIGINAL_ARGS=("$@")
PROJECT_ROOT="$(pwd)"; PANE="${QWB_CONTROLLER_PANE:-}"; INTERVAL=""; ONCE=0; DRY=0; ENSURE=0; CHECK=0; BLOCK=0; MAX_MS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    --pane) PANE="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --once) ONCE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --ensure) ENSURE=1; shift ;;
    --check) CHECK=1; shift ;;
    --block) BLOCK=1; shift ;;
    --max-ms) MAX_MS="$2"; shift 2 ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [[ "$ENSURE" -eq 1 || "$CHECK" -eq 1 ]]; then
  [[ "$ENSURE" -eq 1 && "$CHECK" -eq 1 ]] && { echo "错误：--ensure 与 --check 互斥" >&2; exit 2; }
  [[ "$ONCE" -eq 0 && "$DRY" -eq 0 ]] || { echo "错误：--ensure/--check 与 --once/--dry-run 互斥" >&2; exit 2; }
fi
if [[ "$BLOCK" -eq 1 ]]; then
  (( ENSURE + CHECK + ONCE + DRY == 0 )) || { echo "错误：--block 与 --ensure/--check/--once/--dry-run 互斥" >&2; exit 2; }
else
  [[ -z "$MAX_MS" ]] || { echo "错误：--max-ms 只随 --block 使用" >&2; exit 2; }
fi
if [[ -n "$MAX_MS" ]]; then
  [[ "$MAX_MS" =~ ^[1-9][0-9]*$ ]] || { echo "错误：--max-ms 须为正整数毫秒（当前：${MAX_MS}）" >&2; exit 2; }
fi

[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
LEDGER="$PROJECT_ROOT/tasks"
CONF="$PROJECT_ROOT/qwbuddy/config.sh"
# 共享库（resolve_workspace 等；与 qwb-run.sh 同一份，两处不各写一份）
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-lib.sh"
[[ -f "$LIB" ]] || { echo "错误：找不到共享库 ${LIB}——安装副本不完整（旧版安装缺此文件），请用母本仓重跑 bin/qwb-init.sh 更新（幂等）" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

if [[ "$DRY" -eq 0 && "$CHECK" -eq 0 && "$BLOCK" -eq 0 ]]; then
  command -v herdr >/dev/null 2>&1 || { echo "错误：找不到 herdr 命令，无法叫醒主控" >&2; exit 1; }
fi
# 配置唯一来源是 bash 文件：直接 source（PANE 已被 --pane/环境变量占上则不覆盖）
# shellcheck source=/dev/null
if [[ -f "$CONF" ]]; then . "$CONF"; fi
INTERVAL="${INTERVAL:-${QWB_WAKE_INTERVAL_MS:-120000}}"
PANE="${PANE:-${QWB_CONTROLLER_PANE:-}}"
[[ "$INTERVAL" =~ ^[1-9][0-9]*$ ]] \
  || { echo "错误：interval 须为正整数毫秒（当前：${INTERVAL}）" >&2; exit 2; }

# —— 值守身份 / 健康（--ensure / --check 共用；status 经 --check 复用同一判定）——
# 健康判定只看 pane 前台进程组里真实的 qwb-wake.sh 进程且项目路径匹配，不凭 pane 存在或名字相似。
WATCHF="$PROJECT_ROOT/qwbuddy/.watch"

# pane get → stdout "cwd<TAB>agent<TAB>workspace"；rc：0 ok / 3 pane 不存在 / 2 其他查询失败
# 保留：旧空列与共享接口的 - 占位不同，数组字段字符串化还含进程内地址。
# 空列只用 cut -f 读取，不能改成 TAB IFS read。
pane_info() {
  local out
  if ! out="$(herdr pane get "$1" 2>&1)"; then
    printf '%s' "$out" | grep -q 'pane_not_found' && return 3 || return 2
  fi
  printf '%s' "$out" | perl -MJSON::PP=decode_json -e '
    my $j = eval { decode_json(join "", <STDIN>) } or exit 2;
    my $p = $j->{result}{pane} or exit 2;
    printf "%s\t%s\t%s",
      ($p->{foreground_cwd} // $p->{cwd} // ""), ($p->{agent} // ""), ($p->{workspace_id} // "");
  '
}

# pane process-info 一次判定 → stdout：wake:<pid>@<值守目标pane> | idle | busy | gone | err
# 值守进程认定：前台进程组里 argv0 是 shell/脚本本体 且 cmdline 含 qwb-wake.sh 且项目路径匹配；
# --ensure/--check/--once/--dry-run 这类短调用不算持续值守实例。
pane_probe() {
  local out
  if ! out="$(herdr pane process-info --pane "$1" 2>&1)"; then
    printf '%s' "$out" | grep -q 'pane_not_found' && echo gone || echo err
    return 0
  fi
  printf '%s' "$out" | qwb_pane_probe "$PROJECT_ROOT"
}

# 活值守的目标核验：$1=pane $2=pane_probe 的 wake:* 判定；值守目标 ≠ 本次要求 → 打印修复步骤并 return 1
ensure_target_ok() {
  local wpid wtgt
  wpid="${2#wake:}"; wtgt="${wpid#*@}"; wpid="${wpid%@*}"
  if [[ "$wtgt" != "$PANE" ]]; then
    {
      echo "错误：本项目值守已在 pane $1 运行，但它叫醒的主控目标是 '${wtgt:-未指定}'，本次要求 '${PANE}'——不能静默复用错误目标。"
      echo "修复：到 pane $1 停掉值守（Ctrl-C）后重跑 --ensure；或确认它就是要用的值守，改用 --pane ${wtgt:-<其目标>} 再跑。"
    } >&2
    return 1
  fi
  return 0
}

# 候选 pane = pane list 里没有 agent 字段的（值守是纯 shell tab）：stdout 空格分隔 id；rc2=查询失败
# $1=workspace：非空时只列该 workspace 的 pane——ensure 只在调用者 workspace 内行动
watch_candidates() {
  local out
  out="$(herdr pane list 2>/dev/null)" || return 2
  printf '%s' "$out" | perl -MJSON::PP=decode_json -e '
    my $ws = $ARGV[0];
    my $j = eval { decode_json(join "", <STDIN>) } or exit 2;
    print(($_->{pane_id} // ""), " ") for grep {
      !defined $_->{agent} && ($ws eq "" || (($_->{workspace_id} // "") eq $ws))
    } @{ $j->{result}{panes} // [] };
  ' "$1"
}

# 扫本项目值守进程：WATCH_FOUND=活着的 pane 列表；WATCH_QERR=查询失败 pane 数；rc2=list 失败
# $1 同 watch_candidates 的 workspace 过滤参数
watch_scan() {
  WATCH_FOUND=""; WATCH_QERR=0
  local ids p v
  ids="$(watch_candidates "$1")" || return 2
  for p in $ids; do
    v="$(pane_probe "$p")"
    case "$v" in
      wake:*) WATCH_FOUND="${WATCH_FOUND:+$WATCH_FOUND }$p" ;;
      err)    WATCH_QERR=$((WATCH_QERR + 1)) ;;
    esac
  done
  return 0
}

watch_field() { grep -oE "(^|[[:space:]])$1=[^[:space:]]+" "$WATCHF" 2>/dev/null | head -1 | cut -d= -f2 || true; }
watch_write() { # $1=pane $2=workspace $3=pid（可空）；不是另一账本，仅现有值守登记。
  perl -MFcntl=:DEFAULT,:flock,O_NOFOLLOW -MDigest::SHA=sha256_hex -e '
    my ($dir,$pane,$ws,$pid,$at,$cmd,$actor,$target)=@ARGV;
    open my $guard,"<",$dir or die "watch guard: $!\n";
    flock($guard,LOCK_EX) or die "watch flock: $!\n";
    my ($owner,$generation)=("","");
    my $path="$dir/.controller.lock/owner";
    die "watch owner symlink\n" if -l "$dir/.controller.lock" || -l $path;
    if (-e $path) {
      sysopen my $f,$path,O_RDONLY|O_NOFOLLOW or die "watch owner: $!\n";
      my $raw=<$f> // ""; close $f;
      my ($o)=$raw =~ /^\S+\s+(\S+)\s*\z/;
      if (defined($o) && $o eq $actor && $o eq $target) { $owner=$o; $generation=sha256_hex($raw) }
    }
    sysopen my $f,"$dir/.watch",O_WRONLY|O_CREAT|O_NOFOLLOW,0600 or die "watch open: $!\n";
    my @s=stat($f); die "watch nonregular/hardlink\n" unless -f $f && $s[3]==1 && $s[4]==$<;
    truncate($f,0) or die "watch truncate: $!\n";
    print {$f} "pane=$pane workspace=$ws pid=$pid started=$at controller=$owner owner-fp=$generation cmd=$cmd\n" or die "watch write: $!\n";
    close $f or die "watch close: $!\n";
  ' "$PROJECT_ROOT/qwbuddy" "$1" "$2" "$3" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$WATCH_CMD" "${HERDR_PANE_ID:-pid:$PPID}" "$PANE"
}

watch_check() {
  command -v herdr >/dev/null 2>&1 || { echo "值守：未知（herdr 不在 PATH，无法查询）"; return 0; }
  # 形态一：hook（值守隐形化）—— .hook.lock 里的 pid 存活即视为 Claude Code Stop hook 的 --block 在跑；
  # 检测在 tab 形态之前：同一项目两种形态同时存在时报 hook（前台阻塞形态优先，tab 是 fallback）
  local hpid=""
  hpid="$(cat "$PROJECT_ROOT/qwbuddy/.hook.lock/pid" 2>/dev/null || true)"
  if [[ -n "$hpid" ]] && kill -0 "$hpid" 2>/dev/null; then
    echo "值守：hook（pid ${hpid}）——仅进程存活；接班健康未验证，不据此启用"
    return 0
  fi
  # 形态二：pi 扩展（值守隐形化）——.watch 记 kind=pi-ext pid=<子进程 pid>，pid 活即值守在跑；
  # pid 死 = pi 已退出或扩展收工 → 未运行。判活用 kill -0 不需要 herdr，故放在 tab 扫描之前；
  # 同项目 Claude hook 与 pi 扩展互斥（一个主控只用一种 harness），hook 在前优先。
  if [[ -f "$WATCHF" ]] && [[ "$(watch_field kind)" == "pi-ext" ]]; then
    local wpid=""
    wpid="$(watch_field pid)"
    if [[ -n "$wpid" ]] && [[ "$wpid" != 0 ]] && kill -0 "$wpid" 2>/dev/null; then
      echo "值守：pi-ext（pid ${wpid}）——仅进程存活；须核对宿主、管道和接班，不据此启用"
    else
      echo "值守：未运行（pi-ext 子进程已退出）"
    fi
    return 0
  fi
  local rp="" dead="" qfail=0 v="" target_ws=""
  target_ws="$(resolve_workspace "$PROJECT_ROOT" 2>/dev/null)" || {
    echo "值守：未知（目标 workspace 查询失败）"; return 0;
  }
  [[ -n "$target_ws" ]] || target_ws="${HERDR_WORKSPACE_ID:-}"
  [[ -f "$WATCHF" ]] && rp="$(watch_field pane)"
  if [[ -n "$rp" && -n "$target_ws" && "$(watch_field workspace)" != "$target_ws" ]]; then
    echo "值守：未知（登记 workspace 与当前项目目标不符）"; return 0
  fi
  if ! watch_scan "$target_ws"; then
    echo "值守：未知（herdr pane list 查询失败，无法确认值守是否在跑）"; return 0
  fi
  if [[ -n "$rp" && " ${WATCH_FOUND} " != *" ${rp} "* ]]; then
    v="$(pane_probe "$rp")"
    case "$v" in
      wake:*) WATCH_FOUND="${WATCH_FOUND:+$WATCH_FOUND }$rp" ;;
      gone)   dead="登记 pane ${rp} 已不存在" ;;
      idle)   dead="登记 pane ${rp} 的值守进程已退出（shell 仍空闲在）" ;;
      busy)   dead="登记 pane ${rp} 的值守进程已不在（前台被其他进程占用）" ;;
      err)    qfail=1 ;;
    esac
  fi
  if [[ -n "$WATCH_FOUND" ]]; then
    local n; n=$(wc -w <<<"$WATCH_FOUND" | tr -d ' ')
    if (( WATCH_QERR + qfail > 0 )); then
      # 混合不确定态：见了活实例但还有查不出的 pane——明确未知，不保证单实例
      echo "值守：未知（pane ${WATCH_FOUND} 在跑，但 $((WATCH_QERR + qfail)) 个候选 pane 查询失败，无法排除第二实例）"
    elif [[ "$n" -gt 1 ]]; then
      echo "值守：异常（发现 ${n} 个实例：${WATCH_FOUND}——请手工关停多余的）"
    else
      local extra=""
      [[ "$WATCH_FOUND" != "$rp" || -z "$rp" ]] && extra="（未登记，系手工/外部启动）"
      echo "值守：tab（pane ${WATCH_FOUND}）${extra}"
    fi
    return 0
  fi
  [[ -n "$dead" ]] && { echo "值守：未运行（${dead}）"; return 0; }
  if [[ "$qfail" -gt 0 || "$WATCH_QERR" -gt 0 ]]; then
    echo "值守：未知（部分 pane 进程查询失败，无法确认）"; return 0
  fi
  if [[ -n "$rp" ]]; then echo "值守：未运行（登记 pane ${rp} 无值守进程）"
  else echo "值守：未运行（无登记，扫描也未发现本项目值守进程）"; fi
  return 0
}

SELF_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
# printf %q 逐参数转义：项目路径含空格/单引号时启动命令仍然合法
printf -v WATCH_CMD 'bash %q --project %q --pane %q --interval %q' \
  "$SELF_BIN" "$PROJECT_ROOT" "$PANE" "$INTERVAL"

watch_ensure() {
  [[ -d "$PROJECT_ROOT/qwbuddy" ]] \
    || { echo "错误：项目未安装 qwb（缺 ${PROJECT_ROOT}/qwbuddy），先跑 bin/qwb-init.sh" >&2; return 1; }
  [[ -n "$PANE" ]] \
    || { echo "错误：--ensure 需要主控 pane（--pane / QWB_CONTROLLER_PANE / config.sh）" >&2; return 2; }
  # 建 tab 目标 workspace：优先环境；仅有 HERDR_PANE_ID 时从 pane get 推导
  local ws="${HERDR_WORKSPACE_ID:-}" info=""
  if [[ -z "$ws" && -n "${HERDR_PANE_ID:-}" ]]; then
    info="$(pane_info "$HERDR_PANE_ID")" \
      || { echo "错误：无法确认调用者 workspace（herdr pane get ${HERDR_PANE_ID} 失败）" >&2; return 1; }
    ws="$(printf '%s' "$info" | cut -f3)"
  fi
  [[ -n "$ws" ]] \
    || { echo "错误：无 herdr 上下文（需 HERDR_WORKSPACE_ID 或 HERDR_PANE_ID），不能定位建 tab 的 workspace" >&2; return 1; }

  # 本次要叫醒的目标主控 pane 必须真实存在且同属该 workspace——在获锁与一切副作用前核对；
  # 不存在/查不到/无 workspace 归属/异 workspace 一律拒绝（fail-closed）
  local tinfo trc=0 tws
  tinfo="$(pane_info "$PANE")" || trc=$?
  if [[ "$trc" -ne 0 ]]; then
    if [[ "$trc" -eq 3 ]]; then
      echo "错误：目标主控 pane ${PANE} 不存在（pane_not_found）——ensure 不擅自假定或跨边界行动" >&2
    else
      echo "错误：目标主控 pane ${PANE} 查询失败，无法确认存在与归属——不擅自行动" >&2
    fi
    return 1
  fi
  tws="$(printf '%s' "$tinfo" | cut -f3)"
  [[ -n "$tws" ]] \
    || { echo "错误：目标主控 pane ${PANE} 无 workspace 归属可查——拒绝" >&2; return 1; }
  [[ "$tws" == "$ws" ]] \
    || { echo "错误：目标主控 pane ${PANE} 属于 workspace ${tws}（当前 ${ws}）——ensure 只在调用者 workspace 内行动" >&2; return 1; }

  # 创建、扫描、登记、复用统一使用项目目标 workspace；主控仍可在调用者 workspace。
  local tabws
  tabws="$(resolve_workspace "$PROJECT_ROOT")" || return 1
  [[ -n "$tabws" ]] || tabws="$ws"

  # 防并发 ensure 双开：独立 mkdir 原子锁（不能用主控锁——主控长期持有它，ensure 正是主控调用的）
  local WLOCK="$PROJECT_ROOT/qwbuddy/.watch.lock" rcr=0
  mkdir "$WLOCK" 2>/dev/null \
    || { echo "错误：另一个 ensure 正在执行或留下残留锁（${WLOCK}）；确认无并发后可 rm -rf 该目录重跑" >&2; return 1; }
  # 中断清锁：EXIT/INT/TERM 都只清自己拿到的这一把。
  # SIGKILL/断电捕获不到，残留锁属「需人工核实后恢复」的边界，不假称全覆盖。
  QWB_WATCH_LOCKDIR="$WLOCK"   # 须全局：EXIT trap 触发时本函数可能已不在栈上
  trap 'rm -rf "$QWB_WATCH_LOCKDIR"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  _ensure_body || rcr=$?
  rm -rf "$WLOCK"
  trap - EXIT INT TERM
  unset QWB_WATCH_LOCKDIR
  return "$rcr"
}

# 返回 1=投递失败、2=探测失败、3=登记失败；具体失败文案由两条入口保留。
watch_launch() {
  local pane="$1" workspace="$2" tries=0 nv=""
  herdr pane run "$pane" "$WATCH_CMD" >/dev/null || return 1
  while (( tries < 6 )); do
    nv="$(pane_probe "$pane")"; [[ "$nv" == wake:* ]] && break
    sleep 0.5; tries=$((tries + 1))
  done
  [[ "$nv" == wake:* ]] || return 2
  WATCH_LAUNCH_PID="${nv#wake:}"; WATCH_LAUNCH_PID="${WATCH_LAUNCH_PID%@*}"
  [[ -n "$workspace" ]] || workspace="$(watch_field workspace)"
  watch_write "$pane" "$workspace" "$WATCH_LAUNCH_PID" || return 3
  return 0
}

_ensure_body() {
  local rp="" scanrc=0 v="" np="" launchrc=0
  [[ -f "$WATCHF" ]] && rp="$(watch_field pane)"
  # 只扫描本项目选定的值守 workspace。
  watch_scan "$tabws" || scanrc=$?
  # 不确定态必须先于一切成功分支：list 挂或候选查不出 → 拒绝（fail-closed），不复用不新开
  if [[ "$scanrc" -ne 0 ]]; then
    echo "错误：herdr pane list 查询失败，无法排除已有值守——不擅自多开。修好 herdr 后重跑 --ensure" >&2
    return 1
  fi
  if [[ "$WATCH_QERR" -gt 0 ]]; then
    echo "错误：${WATCH_QERR} 个候选 pane 进程查询失败，无法排除已有值守——不擅自多开/复用。修好 herdr 后重跑 --ensure" >&2
    return 1
  fi
  if [[ -n "$WATCH_FOUND" ]]; then
    local n; n=$(wc -w <<<"$WATCH_FOUND" | tr -d ' ')
    if [[ "$n" -gt 1 ]]; then
      echo "错误：发现 ${n} 个本项目值守实例（${WATCH_FOUND}）。不擅自多开/清理，请手工关停多余实例后重跑 --ensure" >&2
      return 1
    fi
    # 换主控不能静默复用：复核值守命令的真实 --pane 目标，不符即拒并给修复步骤
    v="$(pane_probe "$WATCH_FOUND")"
    ensure_target_ok "$WATCH_FOUND" "$v" || return 1
    if [[ "$WATCH_FOUND" != "$rp" || ! -f "$WATCHF" ]]; then
      local iinfo iws
      iinfo="$(pane_info "$WATCH_FOUND")" || {
        echo "错误：候选值守 pane ${WATCH_FOUND} 身份查询失败——不补登记或误认领" >&2; return 1;
      }
      iws="$(printf '%s' "$iinfo" | cut -f3)"
      [[ "$iws" == "$tabws" ]] || {
        echo "错误：候选值守 pane ${WATCH_FOUND} 属于 workspace ${iws:-未知}（目标 ${tabws}）——不补登记" >&2; return 1;
      }
      watch_write "$WATCH_FOUND" "$tabws" "" \
        || { echo "错误：值守身份登记写入失败（${WATCHF}）" >&2; return 1; }
      echo "复用已在运行的值守（pane ${WATCH_FOUND}，此前未登记/登记不一致，已补记 .watch）"
    else
      # 已登记也复核/更新本代主控授权，不能把旧无授权登记当协议接线齐备。
      watch_write "$WATCH_FOUND" "$tabws" "$(watch_field pid)" || return 1
      echo "复用已在运行的值守（pane ${WATCH_FOUND}）"
    fi
    return 0
  fi
  # 无活值守：登记 pane 还在且 shell 空闲 → 原地重启；占用/消失 → 另开新 tab。
  # 登记 pane 属于别的 workspace → 不认领不重启，拒绝给修复步骤。
  if [[ -n "$rp" ]]; then
    [[ "$(watch_field workspace)" == "$tabws" ]] || {
      echo "错误：登记 pane ${rp} 的 workspace 与项目目标 ${tabws} 不符——拒绝认领" >&2; return 1;
    }
    local rinfo grc
    rinfo="$(pane_info "$rp")"; grc=$?
    if [[ "$grc" -eq 0 ]]; then
      local rws; rws="$(printf '%s' "$rinfo" | cut -f3)"
      [[ "$rws" == "$tabws" ]] || {
        echo "错误：登记 pane ${rp} 属于 workspace ${rws}（目标 ${tabws}）——不认领不重启。" >&2
        echo "修复：核实该 pane 后删掉 ${WATCHF} 登记重跑 --ensure；或到 workspace ${rws} 手工处理" >&2
        return 1; }
    elif [[ "$grc" -eq 2 ]]; then
      echo "错误：登记 pane ${rp} 查询失败，无法确认 workspace 归属——不擅自多开" >&2; return 1
    fi
    # grc=3（pane 不存在）→ 交给 pane_probe 走 gone 分支
    v="$(pane_probe "$rp")"
    case "$v" in
      wake:*)
        ensure_target_ok "$rp" "$v" || return 1
        watch_write "$rp" "$tabws" "$(watch_field pid)" || return 1
        echo "复用已在运行的值守（pane ${rp}）"; return 0 ;;
      err)
        echo "错误：登记 pane ${rp} 进程查询失败，无法确认值守状态——不擅自多开" >&2; return 1 ;;
      idle)
        watch_launch "$rp" "" || launchrc=$?
        case "$launchrc" in
          1) echo "错误：往 pane ${rp} 投递值守启动命令失败" >&2; return 1 ;;
          2) echo "错误：已向 pane ${rp} 投递值守启动命令，但连续探测未确认进程出现——不算确保成功，未登记 .watch；请到该 pane 看实际报错后重跑" >&2; return 1 ;;
          3) echo "错误：值守身份登记写入失败（${WATCHF}）" >&2; return 1 ;;
        esac
        echo "值守已在原 pane 重启（pane ${rp} pid ${WATCH_LAUNCH_PID}）"
        return 0 ;;
      busy) echo "登记 pane ${rp} 已被其他进程占用，另开新 tab（不动旧 pane）" ;;
      gone) echo "登记 pane ${rp} 已不存在，另开新 tab" ;;
    esac
  fi
  # tabws 在任何副作用之前已经确定，与扫描/复用范围相同。
  local tout
  tout="$(herdr tab create --workspace "$tabws" --cwd "$PROJECT_ROOT" --label "qwb-值守" --no-focus 2>&1)" \
    || { echo "错误：herdr tab create 失败：${tout}" >&2; return 1; }
  # 保留旧宽松取值：pane_id 为数组时输出含内存地址，无法证明逐字节等价。
  np="$(printf '%s' "$tout" | perl -MJSON::PP=decode_json -e '
    my $j = eval { decode_json(join "", <STDIN>) } or exit 1;
    print($j->{result}{root_pane}{pane_id} // "");' || true)"
  [[ -n "$np" ]] || { echo "错误：tab create 响应缺 root_pane.pane_id" >&2; return 1; }
  watch_launch "$np" "$tabws" || launchrc=$?
  case "$launchrc" in
    1) echo "错误：新 tab ${np} 投递值守启动命令失败" >&2; return 1 ;;
    2) echo "错误：已建值守 tab ${np} 并投递启动命令，但连续探测未确认进程出现——不算确保成功，未登记 .watch；请到 pane ${np} 看实际报错后重跑" >&2; return 1 ;;
    3) echo "错误：值守身份登记写入失败（${WATCHF}）" >&2; return 1 ;;
  esac
  echo "已在 workspace ${tabws} 新建值守 tab 并启动（pane ${np} pid ${WATCH_LAUNCH_PID}）"
  return 0
}

if [[ "$CHECK" -eq 1 ]]; then watch_check; exit 0; fi
if [[ "$ENSURE" -eq 1 ]]; then watch_ensure; exit 0; fi

# 所有适配器共用同一个代码监督owner。内核锁随进程死亡释放，不凭PID清锁。
if [[ "$DRY" -eq 0 && -d "$PROJECT_ROOT/qwbuddy" && "${QWB_SUPERVISOR_GUARDED:-}" != "$PPID" ]]; then
  exec perl -MFcntl=:DEFAULT,:flock,F_GETFD,F_SETFD,FD_CLOEXEC,O_NOFOLLOW -e '
    my ($dir,@cmd)=@ARGV;
    sysopen my $guard,"$dir/.supervisor.guard",O_RDWR|O_CREAT|O_NOFOLLOW,0600 or die "supervisor guard: $!\n";
    my @s=stat($guard); die "supervisor guard unsafe\n" unless -f $guard && $s[3]==1 && $s[4]==$<;
    flock($guard,LOCK_EX|LOCK_NB) or do { print STDERR "值守故障：已有代码监督owner，拒绝第二实例\n"; exit 75 };
    my $flags=fcntl($guard,F_GETFD,0); defined($flags) && fcntl($guard,F_SETFD,$flags & ~FD_CLOEXEC) or die "guard inherit\n";
    $ENV{QWB_SUPERVISOR_GUARDED}=$$;
    my $pid=fork(); defined($pid) or die "supervisor fork: $!\n";
    if (!$pid) { exec @cmd; die "supervisor exec: $!\n" }
    $SIG{TERM}=sub { kill "TERM",$pid }; $SIG{INT}=sub { kill "INT",$pid };
    while (waitpid($pid,0)<0) { next if $!{EINTR}; die "supervisor wait: $!\n" }
    my $rc=$?; exit 128+($rc&127) if $rc&127; exit($rc>>8);
  ' "$PROJECT_ROOT/qwbuddy" bash "$SELF_BIN" "${ORIGINAL_ARGS[@]}"
fi

# 未结项：输出「文件<TAB>state」。state 异常按 needs-decision 叫主控查看。
# 无 state: 字段行的文件（如 tasks/lessons.md）不算任务书，跳过不警告。
# 单遍扫描（qwb_ledger_scan）把全部任务书一次读完，不再每票起 6 个子进程；
# 其输出列序为「路径<TAB>utf8ok<TAB>collab<TAB>state」，state 可能为空串故放最后一列（见 lib 注释）。
open_items() {
  local f st u8 col
  while IFS=$'\t' read -r f u8 col st; do
    if [[ "$u8" == "0" ]]; then
      echo "警告：$(basename "$f") 账本 UTF-8 损坏，按未结项叫主控查看" >&2
      printf '%s\tneeds-decision\n' "$f"
      continue
    fi
    case "$st" in
      running|blocked|needs-decision) printf '%s\t%s\n' "$f" "$st" ;;
      done|verified)
        # collab=0 时 qwb_task_obligations 本来就立即返回空，直接跳过不改变结果。
        if [[ "$col" == "1" ]]; then
          if [[ -n "$(qwb_task_obligations "$PROJECT_ROOT" "$f")" ]]; then
            printf '%s\tneeds-decision\n' "$f"
          fi
        fi ;;
      *) echo "警告：$(basename "$f") state=${st} 非法，按未结项叫主控查看" >&2
         printf '%s\tneeds-decision\n' "$f" ;;
    esac
  done < <(qwb_ledger_scan "$LEDGER"/*.md)
  return 0
}

# 最近一次 wake 行里的 fp（无 wake 行或解析不到 fp= 则为空 → 视为指纹不同）
last_wake_fp() {
  grep '^wake:' "$1" 2>/dev/null | tail -1 | sed -n 's/.*fp=\([^[:space:]]*\).*/\1/p' || true
}

# 最近一条 wake: 行的时间戳字段（无则空）
last_wake_ts() {
  grep '^wake:' "$1" 2>/dev/null | tail -1 | sed -n 's/^wake:[[:space:]]*\([^[:space:]]*\).*/\1/p' || true
}

# ISO8601 UTC（YYYY-MM-DDTHH:MM:SSZ）→ epoch 秒；格式或数值非法 → 输出空、退出非 0
ts_epoch() {
  perl -MTime::Local=timegm -e '
    my $s = shift // "";
    exit 1 unless $s =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;
    my $e = eval { timegm($6, $5, $4, $3, $2 - 1, $1) };
    exit 1 unless defined $e;
    print $e;
  ' "$1" 2>/dev/null
}

# —— 一轮判定：--once/--dry-run 循环与 --block 完全共用同一份判定，不写两份 ——
# collect_due <输出文件>：遍历未结项，把「本轮要叫」的票逐行 TSV 写进 $1：
#   文件路径 <TAB> state <TAB> fp <TAB> 最后状态行原文截160字符 <TAB> 丢失pane（空=未丢失/未知）
# 非 --block 模式将跳过的票往 stdout 打「跳过：…」说明；全局 OPEN_N = 未结项总数。
# fp 输入 = state\n最后状态行（\nlost=<pane> 仅 running 票判定为工人丢失时追加）；
# 工人丢失判定只在有 herdr 且非 --dry-run 时做；无法确认不当丢失、不拼 lost 段（不猜）。
# 已迁票的在途工人：沿用worker_lost；只读探针不会把unknown猜成死亡。
collect_worker_due() {
  local f="$1" st="$2" data="$3" out="$4" source lost="" now
  now="$(now_ms)"
  source="$(printf '%s' "$data" | perl -MJSON::PP -MTime::Local=timegm -MDigest::SHA=sha256_hex -0777 -e '
    my ($now,$retry,$quiet,$ownerfile)=@ARGV;
    my $d=decode_json(<STDIN>);
    exit if $d->{phase}=~/^(done|verified)$/ || ($d->{gate} && $d->{gate}{verdict} eq "accepted");
    my ($e)=grep { $_->{kind} eq "dispatch" && $d->{ops}{$_->{op_id}}{status} ne "not-sent" } reverse @{$d->{events}};
    exit unless $e; my $op=$e->{op_id};
    exit if grep { $_->{kind} eq "done" && $_->{op_id} eq $op && $_->{seq}>$e->{seq} } @{$d->{events}};
    my ($business)=grep { $_->{kind}!~/^(wake|handoff-pending|handoff-transport)$/ } reverse @{$d->{events}};
    my @t=$business->{at}=~/^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z$/;
    my $at=timegm($t[5],$t[4],$t[3],$t[2],$t[1]-1,$t[0])*1000;
    my $due=!$quiet && $retry=~/^[1-9][0-9]*$/ && $now-$at>=$retry;
    if ($due) {
      open my $owner,"<",$ownerfile or die "worker owner read: $!\n"; my $fp=sha256_hex(<$owner> // ""); close $owner;
      $due=0 if grep { !$_->{handled} && $_->{accepted} ne "" && $_->{owner_fp} eq $fp && ($now<$_->{wait_until} || $now-$_->{activity_at}<$retry) } values %{$d->{handoffs} // {}};
    }
    print JSON::PP->new->canonical->utf8->encode({dispatch=>$e->{event_id},op=>$op,pane=>$d->{ops}{$op}{pane},timer_due=>$due ? 1 : 0});
  ' "$now" "${QWB_REWAKE_MS:-0}" "$POSTURE_QUIET" "$PROJECT_ROOT/qwbuddy/.controller.lock/owner")" || return 3
  [[ -n "$source" ]] || return 0
  lost="$(worker_lost "$f")" || lost=""
  if [[ -z "$lost" ]] && ! printf '%s' "$source" | perl -MJSON::PP -0777 -e 'exit !decode_json(<STDIN>)->{timer_due}'; then return 0; fi
  source="$(perl -MJSON::PP -e 'my $d=decode_json($ARGV[0]); $d->{lost}=$ARGV[1] ne "" ? 1 : 0; print JSON::PP->new->canonical->utf8->encode($d)' "$source" "$lost")"
  printf '%s\t%s\t-\t[qwb-worker] %s\t%s\n' "$f" "$st" "$source" "$lost" >> "$out"
}

# 路由最终确定后才按收件代次去重；第二次身份失效也重新计算主控指纹。
worker_due_row() {
  local f="$1" st="$2" summary="$3" target="$4" grant="$5" data now
  data="$(qwb_ledger "$PROJECT_ROOT" "$f" read)" || return 3
  now="$(now_ms)"
  printf '%s' "$data" | perl -MJSON::PP -MDigest::SHA=sha1_hex,sha256_hex -MTime::Local=timegm -0777 -e '
    use utf8;
    my ($f,$st,$raw,$target,$grant,$now,$retry,$quiet,$ownerfile)=@ARGV;
    my $d=decode_json(<STDIN>); my $s=decode_json(substr($raw,length("[qwb-worker] ")));
    exit if $d->{phase}=~/^(done|verified)$/ || ($d->{gate} && $d->{gate}{verdict} eq "accepted");
    my ($dispatch)=grep { $_->{kind} eq "dispatch" && $d->{ops}{$_->{op_id}}{status} ne "not-sent" } reverse @{$d->{events}};
    exit unless $dispatch && $dispatch->{event_id} eq $s->{dispatch};
    exit if grep { $_->{kind} eq "done" && $_->{op_id} eq $s->{op} && $_->{seq}>$dispatch->{seq} } @{$d->{events}};
    my ($business)=grep { $_->{kind}!~/^(wake|handoff-pending|handoff-transport)$/ } reverse @{$d->{events}};
    sub epoch { my @t=$_[0]=~/^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z$/; die "worker event time invalid\n" unless @t; return timegm($t[5],$t[4],$t[3],$t[2],$t[1]-1,$t[0])*1000 }
    my $at=epoch($business->{at});
    open my $owner,"<",$ownerfile or die "worker owner read: $!\n"; my $owner_raw=<$owner> // ""; close $owner;
    my $owner_fp=sha256_hex($owner_raw);
    my $fp=sha1_hex(JSON::PP->new->canonical->utf8->encode(["worker-watch",$s->{dispatch},$s->{op},$s->{pane},$s->{lost} ? "lost" : $business->{seq},$target,$grant,$owner_fp]));
    my @wakes=grep { $_->{kind} eq "wake" && $_->{line}=~/\bfp=\Q$fp\E(?:\s|$)/ } @{$d->{events}};
    if ($s->{lost}) { exit if @wakes }
    else {
      exit if $quiet || $retry!~/^[1-9][0-9]*$/;
      exit if grep { !$_->{handled} && $_->{accepted} ne "" && $_->{owner_fp} eq $owner_fp && ($now<$_->{wait_until} || $now-$_->{activity_at}<$retry) } values %{$d->{handoffs} // {}};
      my $last=@wakes ? epoch($wakes[-1]{at}) : 0; $last=$at if $at>$last;
      exit if $now-$last<$retry;
    }
    $s->{payload}=$s->{lost} ? "工人丢失：pane=$s->{pane} op=$s->{op}；请派工者核查" : "工人无进展：".($now-$at)."ms（阈值${retry}ms）pane=$s->{pane} op=$s->{op}";
    print join("\t",$f,$st,$fp,"[qwb-worker] ".JSON::PP->new->canonical->utf8->encode($s),$s->{lost} ? $s->{pane} : ""),"\n";
  ' "$f" "$st" "$summary" "$target" "$grant" "$now" "${QWB_REWAKE_MS:-0}" "$POSTURE_QUIET" "$PROJECT_ROOT/qwbuddy/.controller.lock/owner"
}

OPEN_N=0; POSTURE_QUIET=0
collect_due() {
  local out="$1" f st last fp lwf we mtime progress legacy lostpane="" pending retry posture plan_data plan_result plan_rc owner
  OPEN_N=0; POSTURE_QUIET=0
  if [[ -e "$PROJECT_ROOT/qwbuddy/.posture.md" || -L "$PROJECT_ROOT/qwbuddy/.posture.md" ]]; then
    if posture="$(bash "$(dirname "$LIB")/qwb-ledger.sh" mode-status --project "$PROJECT_ROOT")"; then
      POSTURE_QUIET="$(printf '%s' "$posture" | perl -MJSON::PP -0777 -e 'print decode_json(<STDIN>)->{mode} eq "quiet" ? 1 : 0')"
    else
      echo '警告：模式记录不可读；不猜权限，保留现场，其他票照原授权交接' >&2
    fi
  fi
  while IFS=$'\t' read -r f st; do
    OPEN_N=$((OPEN_N + 1))
    if [[ "$DRY" -eq 0 ]] && grep -q '^<!-- qwb-collab-v1$' "$f"; then
      # 几十张票扫描：已派当前spec不重复派；仅发一次明确就绪事件，仍由受限授权规划/主控调用run。
      plan_data="$(qwb_ledger "$PROJECT_ROOT" "$f" read)" || return 3
      collect_worker_due "$f" "$st" "$plan_data" "$out" || return 3
      if printf '%s' "$plan_data" | perl -MJSON::PP -0777 -e '
        my $d=decode_json(<STDIN>); exit 1 unless $d->{planning};
        exit 1 if $d->{claim} || $d->{planning}{pending_revision} || $d->{phase} eq "verified" || ($d->{gate} && $d->{gate}{verdict} eq "accepted");
        exit 1 if grep { $_->{kind} eq "dispatch" && $_->{spec_rev}==$d->{spec_rev} } @{$d->{events}};
      '; then
        owner="$(awk 'NR==1 {print $NF}' "$PROJECT_ROOT/qwbuddy/.controller.lock/owner")"
        plan_rc=0
        plan_result="$(qwb_ledger "$PROJECT_ROOT" "$f" plan-ready "$owner")" || plan_rc=$?
        if (( plan_rc != 0 )); then
          (( plan_rc == 1 )) && printf '%s' "$plan_result" | perl -MJSON::PP -0777 -e '
            my $d=eval { decode_json(<STDIN>) }; exit 1 unless ref($d) eq "HASH" && ($d->{status} // "") eq "blocked";
          ' || return 3
        fi
      fi
      retry="${QWB_REWAKE_MS:-$INTERVAL}"
      [[ "$retry" =~ ^[1-9][0-9]*$ ]] || retry="$INTERVAL"
      (( retry <= 86400000 )) || retry=86400000
      pending="$(bash "$(dirname "$LIB")/qwb-send.sh" pending --project "$PROJECT_ROOT" --task "$f" --retry-ms "$retry" --due)" || return 3
      [[ "$pending" != '[]' ]] || continue
      # 同批完整event_id；旧wake指纹不是消费游标，摘要不把正文当系统指令。
      last="[qwb-handoff] $(printf '%s' "$pending" | perl -MJSON::PP -0777 -e '
        my $p=decode_json(<STDIN>); print JSON::PP->new->canonical->utf8->encode([map { +{event_id=>$_->{event_id},payload=>$_->{payload},reconcile=>$_->{reconcile},(exists($_->{controller_hint}) ? (controller_hint=>$_->{controller_hint}) : ()),(exists($_->{fallback}) ? (fallback=>$_->{fallback}) : ())} } @$p]);
      ')"
      fp="$(printf '%s' "$pending" | shasum | cut -d' ' -f1)"
      printf '%s\t%s\t%s\t%s\t\n' "$f" "$st" "$fp" "$last" >> "$out"
      continue
    fi
    last="$(grep -E '^(working|done|blocked|needs-decision):' "$f" 2>/dev/null | tail -1 || true)"
    lostpane=""
    if [[ "$st" == "running" && "$DRY" -eq 0 ]]; then
      lostpane="$(worker_lost "$f")" || lostpane=""
    fi
    # fp 输入 = state\n最后状态行；running 票判定为丢失时再追加 \nlost=<pane>
    # （直接管道进 shasum：命令替换会剥尾随换行；尾部 || true 保 pipefail 下群组非空退出不炸）
    fp="$( { printf '%s\n' "$st"
             printf '%s' "$last"
             [[ -n "$lostpane" ]] && printf '\nlost=%s' "$lostpane" || true
           } | shasum | cut -d' ' -f1)"
    lwf="$(last_wake_fp "$f")"
    legacy=1; progress=0
    grep -q '^<!-- qwb-collab-v1$' "$f" && legacy=0
    if [[ "$legacy" -eq 1 && "$st" == "running" && -z "$lostpane" && "$last" == working:* ]]; then
      progress=1
    fi
    if [[ "$progress" -eq 1 || ( -n "$lwf" && "$lwf" == "$fp" ) ]]; then
      # Quiet suppresses legacy timer nudges, never actionable new facts or durable handoffs.
      [[ "$progress" -eq 1 || "$POSTURE_QUIET" -eq 0 ]] || continue
      if [[ "$st" != "running" ]]; then
        [[ "$BLOCK" -eq 1 ]] || echo "跳过：$(basename "$f") state=${st} 等裁决（进展未变，不重叫）"
        continue
      fi
      we=skip
      if [[ "$POSTURE_QUIET" -eq 0 && "${QWB_REWAKE_MS:-0}" =~ ^[1-9][0-9]*$ ]]; then
        we="$(ts_epoch "$(last_wake_ts "$f")")" || we=""
        if [[ -n "$we" && "$legacy" -eq 1 ]] \
          || { [[ "$progress" -eq 1 ]] && ! grep -q '^wake:' "$f"; }; then
          mtime="$(perl -e 'print((stat($ARGV[0]))[9] // 0)' "$f")"
          if [[ -z "$we" ]] || (( mtime > we )); then we="$mtime"; fi
        fi
        if [[ -z "$we" ]] || (( $(now_ms) - we * 1000 >= QWB_REWAKE_MS )); then
          we=""
        fi
      fi
      if [[ -n "$we" ]]; then
        if [[ "$BLOCK" -eq 0 ]]; then
          if [[ "$progress" -eq 1 ]]; then
            echo "跳过：$(basename "$f") state=${st}（工人在推进，进度行不叫醒）"
          else
            echo "跳过：$(basename "$f") state=${st}（已叫过，进展未变）"
          fi
        fi
        continue
      fi
    fi
    if [[ "$DRY" -eq 1 ]]; then
      echo "未结项（将叫醒）: $(basename "$f") state=$st"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$st" "$fp" "$(printf '%s' "$last" | qwb_utf8_excerpt 160)" "$lostpane" >> "$out"
  done < <(open_items)
}

# 一轮一条投递的共用拼装：$1 = due 文件 → 全局 DUE_N / DUE_MSG
seq_mark() {
  local marks=(① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩ ⑪ ⑫ ⑬ ⑭ ⑮ ⑯ ⑰ ⑱ ⑲ ⑳)
  if (( $1 >= 1 && $1 <= 20 )); then printf '%s' "${marks[$(($1 - 1))]}"; else printf '(%s)' "$1"; fi
}
compose_msg() {
  DUE_N=0; DUE_MSG=""
  local f st fp last lostpane hint sep=""
  while IFS=$'\t' read -r f st fp last lostpane; do
    DUE_N=$((DUE_N + 1))
    [[ -n "$last" ]] || last="尚无状态行"
    hint=""
    if [[ "$last" == '[qwb-handoff] '* && "$last" == *'"controller_hint":'* ]]; then
      hint="$(printf '%s' "${last#\[qwb-handoff\] }" | perl -MJSON::PP -0777 -e '
        binmode STDOUT, ":encoding(UTF-8)"; my %seen;
        print join("；",grep { !$seen{$_}++ } map { $_->{controller_hint} // () } @{decode_json(<STDIN>)});
      ')"
    fi
    if [[ "$last" == '[qwb-handoff] '* && "$last" == *'"fallback":'* ]]; then
      hint="${hint:+${hint}；}$(printf '%s' "${last#\[qwb-handoff\] }" | perl -MJSON::PP -0777 -e '
        use utf8; binmode STDOUT, ":encoding(UTF-8)";
        print join("；",map { my $h=$_; my $r=$h->{fallback}; ($r->{mode} eq "escalation" ? "交接升级主控" : "交接低频重提")."：event_id=$h->{event_id}；原路由目标（按当前规则判定）=$r->{role}/$r->{pane}；已投次数=3" } grep { $_->{fallback} } @{decode_json(<STDIN>)});
      ')"
    fi
    if [[ "$last" == '[qwb-worker] '* ]]; then
      last="$(printf '%s' "${last#\[qwb-worker\] }" | perl -MJSON::PP -0777 -e 'binmode STDOUT, ":encoding(UTF-8)"; print decode_json(<STDIN>)->{payload}')"
    fi
    DUE_MSG="${DUE_MSG}${sep}$(seq_mark "$DUE_N") $(basename "$f" .md)(${st}) ${hint:+${hint}；}最近: ${last}"
    [[ -n "$lostpane" ]] && DUE_MSG="${DUE_MSG}（工人丢失）"
    sep=" "
  done < "$1"
}

# 两次身份复核共用相同的 canonical JSON，不减少核验次数。
gate_proof() {
  local proof
  proof="$(qwb_gate_identity "$PROJECT_ROOT" "$1" "$2")" || proof='{}'
  printf '%s' "$proof" | perl -MJSON::PP -0777 -e 'binmode STDOUT, ":encoding(UTF-8)"; print JSON::PP->new->canonical->encode(decode_json(<STDIN>))'
}

# 复用03唯一监督：已claim且02本代身份可信的原票，一批直接门铃门禁。
# 不创建第二watcher，不替门禁确认received/handled；ready/重诊仍交主控。
route_gate_due() {
  local duef="$1" controller="$2" dir keep f st fp last lostpane data info actor grant target proof i idx failed role request_event split remainder
  local targets=() batches=() grants=() actors=() roles=()
  dir="$(mktemp -d "${TMPDIR:-/tmp}/qwb-gate-routes.XXXXXX")" || return 3
  keep="$dir/controller"; : > "$keep"
  while IFS=$'\t' read -r f st fp last lostpane; do
    info=""
    if [[ "$last" == '[qwb-handoff] '* && "$last" == *'"fallback":'* ]]; then
      split="$(perl -MJSON::PP -e '
        my $p=decode_json(substr($ARGV[0],length("[qwb-handoff] "))); my $j=JSON::PP->new->canonical->utf8;
        print $j->encode([grep { $_->{fallback} } @$p]),"\t",$j->encode([grep { !$_->{fallback} } @$p]);
      ' "$last")"
      IFS=$'\t' read -r split remainder <<< "$split"
      printf '%s\t%s\t%s\t[qwb-handoff] %s\t\n' "$f" "$st" "$(printf '%s' "$split" | shasum | cut -d' ' -f1)" "$split" >> "$keep"
      [[ "$remainder" != '[]' ]] || continue
      last="[qwb-handoff] $remainder"
      fp="$(printf '%s' "$remainder" | shasum | cut -d' ' -f1)"
    fi
    if [[ "$last" == '[qwb-worker] '* ]]; then
      data="$(qwb_ledger "$PROJECT_ROOT" "$f" read)" || { rm -rf "$dir"; return 3; }
      info="$(printf '%s' "$data" | perl -MJSON::PP -0777 -e '
        use utf8; binmode STDOUT, ":encoding(UTF-8)";
        my $d=decode_json(<STDIN>); my $s=decode_json(substr($ARGV[0],length("[qwb-worker] ")));
        my $p=$d->{planning_authority} // ($d->{planning} ? $d->{planning}{authority} : undef);
        if ($p && $d->{ops}{$s->{op}}{owner} eq $p->{identity}{pane}) {
          print "$p->{identity}{actor}\t".JSON::PP->new->canonical->encode($p->{identity})."\t$p->{identity}{pane}\t规划";
        }
      ' "$last")"
    elif [[ "$last" == '[qwb-handoff] '* ]]; then
      data="$(qwb_ledger "$PROJECT_ROOT" "$f" read)" || { rm -rf "$dir"; return 3; }
      info="$(printf '%s' "$data" | perl -MJSON::PP -0777 -e '
        use utf8; binmode STDOUT, ":encoding(UTF-8)";
        my $d=decode_json(<STDIN>); my $g=$d->{gate};
        my $due=decode_json(substr($ARGV[0],length("[qwb-handoff] "))); my %due=map { $_->{event_id}=>1 } @$due;
        my ($r)=sort { $a->{event_id} cmp $b->{event_id} } grep { $_->{reply_sha256} eq "" && $due{"source:".$_->{event_id}} } values %{$d->{test_requests} // {}};
        if ($r) {
          print "$r->{identity}{actor}\t".JSON::PP->new->canonical->encode($r->{identity})."\t$r->{identity}{pane}\t测试体系\tsource:$r->{event_id}";
        } elsif ($g && $d->{claim} && $d->{claim}{owner} eq $g->{identity}{pane} && $g->{verdict}=~/^(pending|rework)$/) {
          print "$g->{identity}{actor}\t".JSON::PP->new->canonical->encode($g->{identity})."\t$g->{identity}{pane}\t门禁";
        } elsif ($g && $g->{verdict}=~/^(accepted|rediagnose)$/ && ($d->{planning_authority} || ($d->{planning} && $d->{planning}{authority}))) {
          # 验收结论和技术重诊回主控，不能再次落入规划分支。
        } elsif (my $p=$d->{planning_authority} // ($d->{planning} ? $d->{planning}{authority} : undef)) {
          my @planning=grep { !exists $_->{controller_hint} } @$due;
          if (@planning) {
            print "$p->{identity}{actor}\t".JSON::PP->new->canonical->encode($p->{identity})."\t$p->{identity}{pane}\t规划";
            print "\t".join(",",map { $_->{event_id} } @planning) if @planning<@$due;
          }
        }
      ' "$last")"
    fi
    if [[ -n "$info" ]]; then
      IFS=$'\t' read -r actor grant target role request_event <<< "$info"
      if [[ -n "$request_event" ]]; then
        split="$(perl -MJSON::PP -e '
          my ($raw,$ids)=@ARGV; my %ids=map { $_=>1 } split /,/,$ids;
          my $p=decode_json(substr($raw,length("[qwb-handoff] "))); my $j=JSON::PP->new->canonical->utf8;
          print $j->encode([grep { $ids{$_->{event_id}} } @$p]),"\t",$j->encode([grep { !$ids{$_->{event_id}} } @$p]);
        ' "$last" "$request_event")"
        IFS=$'\t' read -r split remainder <<< "$split"
        if [[ "$remainder" != '[]' ]]; then
          printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$st" "$fp" "[qwb-handoff] $remainder" "$lostpane" >> "$keep"
        fi
        last="[qwb-handoff] $split"
        fp="$(printf '%s' "$split" | shasum | cut -d' ' -f1)"
      fi
      idx=-1
      for i in "${!targets[@]}"; do [[ "${targets[i]}" != "$target" ]] || idx="$i"; done
      if (( idx < 0 )); then
        proof="$(gate_proof "$actor" "$role")"
        if [[ "$proof" == "$grant" ]]; then
          idx="${#targets[@]}"; targets+=("$target"); grants+=("$grant"); actors+=("$actor"); roles+=("$role"); batches+=("$dir/$idx")
          : > "${batches[idx]}"
        fi
      fi
      if (( idx >= 0 )) && [[ "${grants[idx]}" == "$grant" ]]; then
        if [[ "$last" == '[qwb-worker] '* ]]; then
          worker_due_row "$f" "$st" "$last" "$target" "$grant" >> "${batches[idx]}" || { rm -rf "$dir"; return 3; }
        else
          printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$st" "$fp" "$last" "$lostpane" >> "${batches[idx]}"
        fi
        continue
      fi
    fi
    if [[ "$last" == '[qwb-worker] '* ]]; then
      worker_due_row "$f" "$st" "$last" "$controller" '' >> "$keep" || { rm -rf "$dir"; return 3; }
    else
      printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$st" "$fp" "$last" "$lostpane" >> "$keep"
    fi
  done < "$duef"
  for i in "${!targets[@]}"; do
    [[ -s "${batches[i]}" ]] || continue
    # 投递前再核代次；失效只交主控，不把旧pane/session当新实例。
    proof="$(gate_proof "${actors[i]}" "${roles[i]}")"
    if [[ "$proof" != "${grants[i]}" ]]; then
      while IFS=$'\t' read -r f st fp last lostpane; do
        if [[ "$last" == '[qwb-worker] '* ]]; then
          worker_due_row "$f" "$st" "$last" "$controller" '' >> "$keep" || { rm -rf "$dir"; return 3; }
        else
          printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$st" "$fp" "$last" "$lostpane" >> "$keep"
        fi
      done < "${batches[i]}"
      continue
    fi
    failed=0
    while IFS=$'\t' read -r f st fp last lostpane; do
      qwb_ledger "$PROJECT_ROOT" "$f" wake-check "$controller" "$st" "$fp" >/dev/null || { failed=1; break; }
      record_transport "$f" "$last" || { failed=1; break; }
    done < "${batches[i]}"
    if (( failed )); then rm -rf "$dir"; return 3; fi
    compose_msg "${batches[i]}"
    local message
    if [[ "${roles[i]}" == 规划 ]]; then
      message="规划看账本：${DUE_N} 张受限原票有请求/就绪事件 →${DUE_MSG}。先received/accept/prepared，对账request映射与原话；仅按授权版本/范围/工人/预算派工，读回后handled；不改在验标准、不自动验收/合并。"
    elif [[ "${roles[i]}" == 测试体系 ]]; then
      message="测试体系看账本：${DUE_N} 张原票有关联request →${DUE_MSG}。只处理本人绑定请求，给受限建议不替作者自证；门禁独自验收，不改场景或自动合并。"
    else
      message="门禁看账本：${DUE_N} 张原票有成果 →${DUE_MSG}。按本人持久claim核证据/独立审核/原范围返修，不改场景或自动合并。"
    fi
    if herdr pane run "${targets[i]}" "$message"; then
      while IFS=$'\t' read -r f st fp last lostpane; do
        qwb_ledger "$PROJECT_ROOT" "$f" wake "$controller" "$st" "$fp" >/dev/null || { rm -rf "$dir"; return 3; }
      done < "${batches[i]}"
      [[ "$POSTURE_QUIET" -eq 1 ]] || echo "已直接门铃${roles[i]}：${DUE_N} 张票 → pane ${targets[i]}"
    else
      echo "错误：门禁门铃失败（pane ${targets[i]}），03待办/有界重投预算保留" >&2
    fi
  done
  cp "$keep" "$duef" || { rm -rf "$dir"; return 3; }
  rm -rf "$dir"
}

check_round() {
  due_create
  local duef="$QWB_DUE_FILE"
  : > "$duef"
  collect_due "$duef" || { due_cleanup; return 3; }
  if [[ "$DRY" -eq 0 && -s "$duef" && -n "$PANE" ]]; then
    route_gate_due "$duef" "$PANE" || { due_cleanup; return 3; }
  fi
  if [[ ! -s "$duef" ]]; then
    if (( OPEN_N == 0 && POSTURE_QUIET == 0 )); then echo "账本无未结项"; fi
    due_cleanup
    return 0
  fi
  compose_msg "$duef"
  if [[ "$DRY" -eq 1 ]]; then due_cleanup; return 0; fi
  [[ -n "$PANE" ]] || { echo "错误：有未结项但不知道主控 pane（--pane / QWB_CONTROLLER_PANE / config.sh QWB_CONTROLLER_PANE）" >&2; due_cleanup; exit 1; }
  # 先逐票核验wake-only权限，拒绝不投递；登记在启动探针后完成，循环启动首轮可稍后重试。
  local f st fp last lostpane write_failed=0
  while IFS=$'\t' read -r f st fp last lostpane; do
    qwb_ledger "$PROJECT_ROOT" "$f" wake-check "$PANE" "$st" "$fp" >/dev/null \
      || { echo "错误：值守写入未授权/协议非法，不投递：$f" >&2; write_failed=1; break; }
  done < "$duef"
  if (( write_failed )); then due_cleanup; return 1; fi
  # 先持久记录传输尝试；即使API前崩溃也保留待办且重投有界。
  while IFS=$'\t' read -r f st fp last lostpane; do
    record_transport "$f" "$last" || { write_failed=1; break; }
  done < "$duef"
  if (( write_failed )); then due_cleanup; return 3; fi
  # 一轮只发一条投递，API成功不代表received或handled。
  if herdr pane run "$PANE" "看账本：${DUE_N} 张未结项有进展 →${DUE_MSG}。只需读这些票。"; then
    while IFS=$'\t' read -r f st fp last lostpane; do
      qwb_ledger "$PROJECT_ROOT" "$f" wake "$PANE" "$st" "$fp" >/dev/null \
        || { echo "警告：wake 行写入失败（下轮重试）：$f" >&2; write_failed=1; continue; }
      [[ "$POSTURE_QUIET" -eq 1 ]] || echo "已叫醒：$(basename "$f" .md) state=${st} → pane ${PANE}"
    done < "$duef"
  else
    echo "错误：投递失败（pane ${PANE}）：本轮 ${DUE_N} 张票一行 wake 都不写、保持未叫，下轮重试" >&2
  fi
  due_cleanup
  return "$write_failed"
}

EVENT_DIR=""; EVENT_PID=""; EVENT_SEEN=""; QWB_DUE_FILE=""
EVENT_CLEANUP_MAX_SECONDS=4  # SECONDS 为整秒：首段留取整裕量，再各等 1 秒；真实总时限 4 秒。
# 创建期间只记中断；mktemp 忽略 INT/TERM，确保建好文件后路径能完整读回。
# 路径登记后恢复既有退出码，再由 EXIT 同时回收 due 文件与订阅器。
due_create() {
  local interrupted=0 rc=0
  trap 'interrupted=130' INT
  trap 'interrupted=143' TERM
  QWB_DUE_FILE="$(trap '' INT TERM; mktemp "${TMPDIR:-/tmp}/qwb-due.XXXXXX")" || rc=$?
  trap 'trap "" INT TERM; exit 130' INT
  trap 'trap "" INT TERM; exit 143' TERM
  if (( interrupted != 0 )); then trap '' INT TERM; exit "$interrupted"; fi
  return "$rc"
}
due_cleanup() {
  [[ -z "$QWB_DUE_FILE" ]] || rm -f "$QWB_DUE_FILE"
  QWB_DUE_FILE=""
}
# 内建 read 保留首行原有换行；IFS= 保留首尾空白与反斜杠。
# 先重定向 stderr，缺文件时也安静返回 0；无结尾换行时仍输出已读内容。
event_mark() {
  if [[ -z "$EVENT_DIR" ]]; then return 0; fi
  local line=""
  if IFS= read -r line 2>/dev/null < "$EVENT_DIR/notice"; then
    printf '%s\n' "$line"
  else
    printf '%s' "$line"
  fi
}
event_cleanup() {
  # 监督进程会转发信号；同一中断可能再次到达，不能截断 EXIT 清理。
  trap '' INT TERM
  due_cleanup
  if [[ -n "$EVENT_PID" ]]; then
    local started=$SECONDS phase deadline
    for phase in 1 2 3; do
      kill -0 "$EVENT_PID" 2>/dev/null || break
      case "$phase" in
        1) kill -TERM "$EVENT_PID" 2>/dev/null || true ;;
        2) echo 'Herdr subscriber still alive; retrying TERM' >&2
           kill -TERM "$EVENT_PID" 2>/dev/null || true ;;
        3) echo 'Herdr subscriber still alive after two TERM attempts; sending SIGKILL' >&2
           kill -KILL "$EVENT_PID" 2>/dev/null || true ;;
      esac
      deadline=$((started + EVENT_CLEANUP_MAX_SECONDS - 3 + phase))
      while kill -0 "$EVENT_PID" 2>/dev/null && (( SECONDS < deadline )); do sleep 0.01; done
    done
    # 只回收已退出的子进程；即使内核尚未完成 KILL，也不再无限 wait。
    if ! kill -0 "$EVENT_PID" 2>/dev/null; then wait "$EVENT_PID" 2>/dev/null || true; fi
  fi
  [[ -z "$EVENT_DIR" ]] || rm -rf "$EVENT_DIR"
}
# --once/--dry-run 也会创建 due 文件；复用同一 EXIT 清理，不覆盖订阅器收尾。
# 宿主消失会关闭 stdout；保留 SIGPIPE 的 141 退出码，同时排空持锁订阅器。
trap event_cleanup EXIT
trap 'trap "" INT TERM PIPE; exit 141' PIPE
trap 'trap "" INT TERM; exit 130' INT
trap 'trap "" INT TERM; exit 143' TERM
event_start() {
  EVENT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qwb-events.XXXXXX")"
  bash "$(dirname "$LIB")/qwb-herdr.sh" subscribe --project "$PROJECT_ROOT" --notice "$EVENT_DIR/notice" &
  EVENT_PID=$!
  local deadline=$(( $(now_ms) + 1000 ))
  [[ -z "${block_deadline:-}" ]] || (( deadline <= block_deadline )) || deadline="$block_deadline"
  while [[ ! -s "$EVENT_DIR/notice" ]] && kill -0 "$EVENT_PID" 2>/dev/null && (( $(now_ms) < deadline )); do sleep 0.05; done
  [[ -s "$EVENT_DIR/notice" ]] || echo 'Herdr subscription not yet established; bounded MD reconcile fallback' >&2
}
wait_round() {
  local budget="$INTERVAL" end remaining mark
  # ponytail: bounded whole-MD scan (1s), incremental indexing only if project size warrants it.
  (( budget <= 1000 )) || budget=1000
  end=$(( $(now_ms) + budget ))
  [[ -z "${block_deadline:-}" ]] || (( end <= block_deadline )) || end="$block_deadline"
  while :; do
    mark="$(event_mark)"
    [[ "$mark" == "$EVENT_SEEN" ]] || return 0
    remaining=$(( end - $(now_ms) )); (( remaining > 0 )) || return 0
    (( remaining <= 50 )) || remaining=50
    sleep_ms "$remaining"
  done
}

# —— block 模式：前台阻塞值守（Claude Code Stop hook / Codex 前台 checkpoint 的共用核心）——
# 判定与循环模式完全共用（collect_due 的指纹去重 + 仅 running 的时间兑底 + 工人丢失指纹段），
# 只有「叫醒」动作不同：不 pane run，而是把同一份拼装打到 stdout、往票追加 wake: 行后以退出码 2 交还调用方。
# 返回码：2 = 有可动作变化（已写 wake 行）；0 = 账本无未结项（不写任何行）；1 = 有未结项但无变化（内部）
pi_orphan_clear() {
  # Pi 宿主被 SIGKILL 时只有子进程能清登记。与扩展写/清 .watch 共用目录 flock，
  # 且必须同时匹配子进程 PID 与会话实例，绝不删除新宿主的登记。
  [[ "${QWB_WATCH_INSTANCE:-}" =~ ^[A-Za-z0-9-]+$ ]] || return 0
  perl -MFcntl=:flock -e '
    my ($dir, $pid, $instance) = @ARGV;
    open my $guard, "<", $dir or die "orphan guard open: $!\n";
    flock($guard, LOCK_EX) or die "orphan guard flock: $!\n";
    my $path = "$dir/.watch";
    open my $old, "<", $path or exit 0;
    my $current = <$old> // "";
    close $old;
    unlink $path if index($current, "kind=pi-ext pid=$pid instance=$instance ") == 0;
  ' "$PROJECT_ROOT/qwbuddy" "${QWB_SUPERVISOR_GUARDED:-$$}" "$QWB_WATCH_INSTANCE" \
    || echo "警告：Pi 孤儿值守未能清理自己的 .watch 登记" >&2
}

block_owner_ok() {
  if [[ -n "${QWB_SUPERVISOR_GUARDED:-}" && "$QWB_SUPERVISOR_GUARDED" != "$PPID" ]]; then
    pi_orphan_clear
    return 1
  fi
  # Pi 以宿主 PID 绑定子进程；SIGKILL 后 PPID 改变，旧 pane 锁即使尚在也不能消费进展。
  if [[ -n "${QWB_WATCH_PARENT_PID:-}" ]]; then
    [[ "$QWB_WATCH_PARENT_PID" =~ ^[1-9][0-9]*$ ]] || return 1
    local actual_parent
    if [[ "${QWB_SUPERVISOR_GUARDED:-}" == "$PPID" ]]; then
      actual_parent="$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d '[:space:]')"
    else
      actual_parent="$(ps -o ppid= -p "$$" 2>/dev/null | tr -d '[:space:]')"
    fi
    if [[ "$actual_parent" != "$QWB_WATCH_PARENT_PID" ]]; then
      pi_orphan_clear
      return 1
    fi
  fi
  # 孤儿值守复核：主控锁不在本进程手里（换会话后被新主控接管 / 锁已不存在）→ 不消费唤醒。
  # HERDR_PANE_ID 为空（非 herdr 环境，如 smoke）跳过复核。
  [[ -n "${HERDR_PANE_ID:-}" ]] || return 0
  local owner=""
  owner="$(qwb_lock_owner "$PROJECT_ROOT")"
  [[ "$owner" == "$HERDR_PANE_ID" ]]
}

record_transport() {
  local f="$1" summary="$2" id mode role pane retry
  [[ "$summary" == '[qwb-handoff] '* ]] || return 0
  # 确认严格绑定collect_due的旧批次；并发到达的新事件不得被这次传输消费。
  while IFS=$'\t' read -r id mode role pane retry; do
    if [[ "$mode" == normal ]]; then
      bash "$(dirname "$LIB")/qwb-send.sh" transport --project "$PROJECT_ROOT" --task "$f" --event "$id" >/dev/null || return 1
    else
      bash "$(dirname "$LIB")/qwb-send.sh" transport --project "$PROJECT_ROOT" --task "$f" --event "$id" --mode "$mode" --route-role "$role" --route-pane "$pane" --retry-ms "$retry" >/dev/null || return 1
    fi
  done < <(printf '%s' "${summary#\[qwb-handoff\] }" | perl -MJSON::PP -0777 -e '
    binmode STDOUT, ":encoding(UTF-8)";
    for my $h (@{decode_json(<STDIN>)}) {
      my $r=$h->{fallback}; print join("\t",$h->{event_id},$r ? @{$r}{qw(mode role pane retry_ms)} : ("normal","-","-",0)),"\n";
    }
  ')
}

block_round() {
  due_create
  local duef="$QWB_DUE_FILE"
  : > "$duef"
  collect_due "$duef" || { due_cleanup; return 3; }
  local any="$OPEN_N" f st fp last lostpane
  if [[ -s "$duef" ]]; then
    if ! block_owner_ok; then due_cleanup; return 0; fi
    route_gate_due "$duef" "${HERDR_PANE_ID:-pid:$PPID}" || { due_cleanup; return 3; }
  fi
  if [[ -s "$duef" ]]; then
    if ! block_owner_ok; then due_cleanup; return 0; fi
    compose_msg "$duef"
    local lost_host=0 write_failed=0
    while IFS=$'\t' read -r f st fp last lostpane; do
      if ! block_owner_ok; then lost_host=1; break; fi
      # block由主控harness调用；空pane的旧票兼容入口仍沿用原runtime行。
      local target="${HERDR_PANE_ID:-pid:$PPID}"
      record_transport "$f" "$last" || { write_failed=1; break; }
      qwb_ledger "$PROJECT_ROOT" "$f" wake "$target" "$st" "$fp" >/dev/null \
        || { echo "错误：wake 行写入失败：$f" >&2; write_failed=1; break; }
    done < "$duef"
    if (( write_failed )); then due_cleanup; return 3; fi
    if (( lost_host )); then due_cleanup; return 0; fi
    printf '看账本：%d 张未结项有进展 →%s。只需读这些票。\n' "$DUE_N" "$DUE_MSG"
    due_cleanup
    return 2
  fi
  due_cleanup
  (( any )) || return 0
  return 1
}

if [[ "$BLOCK" -eq 1 ]]; then
  block_deadline=""
  if [[ -n "$MAX_MS" ]]; then
    block_deadline=$(( $(now_ms) + MAX_MS ))
  fi
  event_start
  while :; do
    EVENT_SEEN="$(event_mark)"
    # 每轮判定前复核主控锁：锁不在手 = 本值守是孤儿（主控会话已退出 / 锁被新主控接管），
    # exit 0、不写任何 wake 行，不消费唤醒
    if ! block_owner_ok; then
      echo "值守：主控锁不在本进程（owner=$(qwb_lock_owner "$PROJECT_ROOT")，本进程 ${HERDR_PANE_ID}），孤儿值守退出不消费唤醒"
      exit 0
    fi
    brc=0; block_round || brc=$?
    if (( brc == 2 )); then exit 2; fi
    if (( brc == 0 )); then echo "账本无未结项"; exit 0; fi
    if (( brc > 2 )); then exit "$brc"; fi
    if [[ -n "$block_deadline" ]] && (( $(now_ms) >= block_deadline )); then
      echo "值守：--block 到期（--max-ms ${MAX_MS}ms）无变化" >&2
      exit 124
    fi
    wait_round
  done
fi

if [[ "$ONCE" -eq 0 && "$DRY" -eq 0 ]]; then event_start; fi
while :; do
  EVENT_SEEN="$(event_mark)"
  [[ -z "${QWB_SUPERVISOR_GUARDED:-}" || "$QWB_SUPERVISOR_GUARDED" == "$PPID" ]] || { echo '值守故障：监督owner已退出，不交接新消息' >&2; exit 3; }
  roundrc=0; check_round || roundrc=$?
  if [[ "$ONCE" -eq 1 || "$DRY" -eq 1 ]]; then
    exit "$roundrc"
  fi
  wait_round
done
