#!/usr/bin/env bash
# qwb-lib.sh —— QW buddy 运行时共享库：被 qwb-run.sh / qwb-wake.sh source（库文件，不直接运行）
#
# 本文件只定义函数：不执行动作、不设置 shell 选项（set -euo pipefail 归调用方）。
# 因此它自己不是可运行脚本——QWBUDDY.md §9 表里按「库文件，不直接运行」列出。

qwb_load_workers() {
  local PROJECT_ROOT="$1" WORKERS_CONF listed w seen count
  WORKERS_CONF="$PROJECT_ROOT/qwbuddy/workers.sh"
  [[ -f "$WORKERS_CONF" ]] || { echo "错误：缺少 ${WORKERS_CONF}；若 QWB_WORKERS 是定制表，请按 templates/workers.sh 手动创建逐工人声明；旧长串配置须显式迁移，默认配置可重跑母本仓 bin/qwb-init.sh" >&2; return 1; }
  QWB_CONFIG_ERROR=0
  QWB_CONFIG_NAMES=(); QWB_CONFIG_MODES=(); QWB_CONFIG_HARNESSES=(); QWB_CONFIG_OFFSETS=(); QWB_CONFIG_COUNTS=(); QWB_CONFIG_ARGV=()
  # shellcheck disable=SC2329 # qwb-run调用，workers声明由配置source间接调用。
  has_headless_arg() { [[ "$1" == -p || "$1" == --print || "$1" == --exec || "$1" == exec || "$1" == -p=* || "$1" == --print=* || "$1" == --exec=* || "$1" == exec=* ]]; }
  # shellcheck disable=SC2329 # 被动态workers声明入口qwb_worker调用。
  qwb_parse_worker() {
    local name="${1:-}" mode="${2:-}" known seen harness
    harness=$name
    shift 2 || { echo "错误：workers.sh 声明缺少工人名或启动方式" >&2; return 1; }
    known=0
    for seen in $QWB_WORKERS; do [[ "$seen" == "$name" ]] && known=1; done
    [[ "$known" -eq 1 ]] || { echo "错误：workers.sh 有未知工人 '${name}'（不在 QWB_WORKERS）" >&2; return 1; }
    for seen in "${QWB_CONFIG_NAMES[@]+"${QWB_CONFIG_NAMES[@]}"}"; do
      [[ "$seen" == "$name" ]] && { echo "错误：workers.sh 工人 '${name}' 重复启动定义" >&2; return 1; }
    done
    case "$mode" in
      herdr)
        # 仅以分隔符识别新式行，旧式位置实参仍按 argv 原样透传。
        if [[ "${2:-}" == -- ]]; then
          [[ "${1:-}" =~ ^[a-z][a-z0-9-]*$ && "${2:-}" == -- ]] \
            || { echo "错误：工人 '${name}' 的显式 harness 须为合法名字且后接 --" >&2; return 1; }
          harness=$1; shift 2
        fi
        ;;
      pane-run) [[ $# -ge 1 && -n "$1" ]] || { echo "错误：工人 '${name}' 的 pane-run 须有非空可执行文件" >&2; return 1; } ;;
      *) echo "错误：工人 '${name}' 启动方式 '${mode}' 非法（herdr / pane-run）" >&2; return 1 ;;
    esac
    QWB_CONFIG_NAMES+=("$name"); QWB_CONFIG_MODES+=("$mode")
    QWB_CONFIG_HARNESSES+=("$harness")
    QWB_CONFIG_OFFSETS+=("${#QWB_CONFIG_ARGV[@]}"); QWB_CONFIG_COUNTS+=("$#")
    QWB_CONFIG_ARGV+=("$@")
  }
  # shellcheck disable=SC2329 # workers.sh通过source调用声明入口。
  qwb_worker() {
    qwb_parse_worker "$@" || { QWB_CONFIG_ERROR=1; return 1; }
  }
  # 不依赖errexit：调用方的 ||/if 会抑制函数内set -e，任何声明错误必须粘住。
  # shellcheck source=/dev/null
  . "$WORKERS_CONF" || return 1
  [[ "$QWB_CONFIG_ERROR" -eq 0 ]] || return 1
  listed=()
  for w in $QWB_WORKERS; do
    for seen in "${listed[@]+"${listed[@]}"}"; do
      [[ "$seen" == "$w" ]] && { echo "错误：QWB_WORKERS 中工人 '${w}' 重复" >&2; return 1; }
    done
    listed+=("$w")
    count=0
    for seen in "${QWB_CONFIG_NAMES[@]+"${QWB_CONFIG_NAMES[@]}"}"; do [[ "$seen" == "$w" ]] && count=$((count+1)); done
    [[ "$count" -eq 1 ]] || { echo "错误：工人 '${w}' 在 workers.sh 缺少唯一启动定义" >&2; return 1; }
  done
}

# 启动唯一共用路径；argv逐项原样进入Herdr，不拼接成prompt。
qwb_start_worker() {
  local name="$1" pane="$2" harness="$3" timeout="$4"
  shift 4
  local argv=(agent start "$name" --kind "$harness" --pane "$pane" --timeout "$timeout")
  if [[ $# -gt 0 ]]; then argv+=(-- "$@"); fi
  herdr "${argv[@]}"
}

# 复用02的原生身份核验；只在账本加锁前调用status（status会读票，不能倒锁）。
# 指定actor供主控授权；否则还核调用者确为登记Pi的后代，而非仅环境pane声明。
qwb_gate_identity() {
  python3 -B - "$1" "${2:-}" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" <<'PY'
import hashlib, json, os, subprocess, sys
from pathlib import Path
root, actor, bindir = sys.argv[1:]
base = Path(root) / 'qwbuddy'; roles = base / '.roles'
try:
    matches = []
    if roles.exists():
        if roles.is_symlink(): raise ValueError('角色目录符号链接')
        for path in roles.glob('*.json'):
            if path.is_symlink(): raise ValueError('角色记录符号链接')
            d = json.loads(path.read_text())
            if (actor and d.get('actor') == actor) or (not actor and d.get('pane') == os.environ.get('HERDR_PANE_ID')): matches.append(d)
    if not matches:
        if actor: raise ValueError('门禁未登记')
        print('{}'); sys.exit(0)
    if len(matches) != 1: raise ValueError('角色归属不唯一')
    d = matches[0]
    r = subprocess.run(['bash',bindir+'/qwb-role.sh','status','--project',root,'--actor',d['actor']],capture_output=True,text=True)
    if r.returncode: raise ValueError(r.stderr.strip())
    d = json.loads(r.stdout)
    owner = (base / '.controller.lock/owner').read_bytes()
    if (d['role'] != '门禁' or d.get('pending') or d['phase'] == 'retired' or d['activity'] not in ('idle','done','working','blocked') or
        d.get('owner_fp') != hashlib.sha256(owner).hexdigest() or not d.get('actual_model') or not d.get('actual_effort')): raise ValueError('门禁本代身份/模型未知或主控已换代')
    if not actor:
        pid = os.getpid(); ancestors = set()
        for _ in range(64):
            if pid <= 1 or pid in ancestors: break
            ancestors.add(pid)
            if pid == d['pid']: break
            v = subprocess.check_output(['ps','-p',str(pid),'-o','ppid='],text=True).strip()
            if not v.isdigit(): raise ValueError('调用者祖先未知')
            pid = int(v)
        if d['pid'] not in ancestors: raise ValueError('pane声明不是实际门禁调用者')
    print(json.dumps({k:d[k] for k in ('actor','pane','incarnation','owner_fp','controller','session_id','actual_model','actual_effort')}))
except (KeyError, ValueError, OSError, subprocess.SubprocessError) as e:
    print('门禁身份拒绝: '+str(e),file=sys.stderr); sys.exit(1)
PY
}

# 只读取已配置具名Pi工人，不替主控选择型号/effort；赋予门禁前冻结准确配置。
qwb_gate_profile() (
  local root="$1" selected="$2" i offset count
  # shellcheck source=/dev/null
  . "$root/qwbuddy/config.sh" >&2
  qwb_load_workers "$root" || exit 1
  for i in "${!QWB_CONFIG_NAMES[@]}"; do
    [[ "${QWB_CONFIG_NAMES[i]}" == "$selected" ]] || continue
    offset="${QWB_CONFIG_OFFSETS[i]}"; count="${QWB_CONFIG_COUNTS[i]}"
    python3 -B - "${QWB_CONFIG_MODES[i]}" "${QWB_CONFIG_HARNESSES[i]}" "${QWB_CONFIG_ARGV[@]:offset:count}" <<'PY'
import json,sys
mode,harness,*args=sys.argv[1:]
try:
    assert mode=='herdr' and harness=='pi', '门禁当前仅接已配置可见Pi工人'
    d={}
    for flag,key in [('--model','model'),('--provider','provider'),('--thinking','effort')]:
        assert args.count(flag)==1, '型号/effort必须准确固定'
        d[key]=args[args.index(flag)+1]; assert d[key] and not d[key].startswith('-')
    assert not any(x.split('=',1)[0] in ('--fast','--priority','--service-tier') for x in args), '不得开启fast/priority'
    print(json.dumps(d))
except (AssertionError,IndexError) as e:
    print('工人身份拒绝: '+str(e),file=sys.stderr); sys.exit(1)
PY
    exit $?
  done
  echo '错误：主控授权工人未配置' >&2; exit 1
)

# 只提取首个 state 值；是否有 state 字段、值是否合法由调用方决定。
qwb_task_state() {
  sed -n 's/^state:[[:space:]]*//p' "$1" | head -1 | tr -d '[:space:]'
}

# 文件里任意非法 UTF-8 都代表账本不能完整解释；点名/值守须按未结处理。
qwb_ledger_utf8_ok() {
  perl -MEncode=decode,FB_CROAK -e '
    local $/; eval { decode("UTF-8", <>, FB_CROAK) }; exit($@ ? 1 : 0)
  ' "$1" >/dev/null 2>&1
}

# 对外摘要只输出合法 UTF-8；先替换坏字节，再按 Unicode 字符截断。
# LC_ALL=C 仍用于账本解析，不能拿 bash 字节子串直接交给 Herdr。
qwb_utf8_excerpt() {
  perl -MEncode=decode,encode,FB_DEFAULT -e '
    my $limit = shift;
    local $/; my $raw = <STDIN> // "";
    my $text = decode("UTF-8", $raw, FB_DEFAULT);
    $text =~ tr/\t\r\n/   /;
    binmode STDOUT, ":raw";
    print encode("UTF-8", substr($text, 0, $limit));
  ' "${1:-160}"
}

# 默认工人名：ASCII id 与旧算法逐字节一致；中文 id 用字符截取后附完整 id 短哈希。
qwb_default_agent_name() {
  perl -MEncode=decode,FB_DEFAULT -MDigest::SHA=sha1_hex -e '
    local $/; my $raw = <STDIN> // "";
    my $hash = substr(sha1_hex($raw), 0, 8);
    my $nonascii = $raw =~ /[\x80-\xff]/;
    my $text = decode("UTF-8", $raw, FB_DEFAULT);
    my $name = substr("qwb-" . $text, 0, 32);
    $name =~ tr/A-Z/a-z/;
    $name =~ s/[^a-z0-9_-]//g;
    if ($nonascii) {
      $name = substr($name, 0, 23) . "-" . $hash;
    } else {
      my $suffix = $name;
      $suffix =~ s/^qwb-//;
      $suffix =~ s/[^a-z0-9]//g;
      $name = "qwb-" . $hash if length($suffix) < 3;
    }
    print $name;
  '
}

# 最后一条规格疑点相关事件；普通进展行不解除疑点。
qwb_last_spec_event() {
  grep -E '^blocked:[[:space:]]*spec-defect:|^working:[[:space:]]*spec-resolved:' "$1" | tail -1 || true
}

# 与派发和 lint 共用的场景块边界；保留原始行字节供现有指纹算法使用。
qwb_scenario_block() {
  awk '
    inblk==0 && /^#{1,6}[^#]*验收场景/ { inblk=1; print; next }
    inblk==1 && (/^<!-- qwb-collab-/ || /^#{1,2}[^#]/ || /^(working|done|blocked|needs-decision|dispatch|not-sent|wake|worktree|worktree-space|scenarios-fp):/) { inblk=0 }
    inblk==1 { print }
  ' "$1"
}

# 已迁票的持久未结义务，不依赖末行working/done。损坏协议也按未结处理。
qwb_task_obligations() {
  grep -q '<!-- qwb-collab-' "$2" || return 0
  local data
  data="$(qwb_ledger "$1" "$2" read)" || { printf '%s' 'protocol-unknown'; return 0; }
  printf '%s' "$data" | perl -MJSON::PP -MDigest::SHA=sha256_hex -0777 -e '
    my $d=decode_json(<STDIN>);
    print "claim=$d->{claim}{op_id} " if $d->{claim};
    my $stage=$d->{land} ? $d->{land}{stage} : "";
    print "gate=$d->{gate}{verdict} pending-land-cleanup " if $d->{gate} && $stage ne "closed";
    print "land=$stage " if $d->{land} && $stage ne "closed";
    for my $k (sort keys %{$d->{questions}}) { print "key=$k " if $d->{questions}{$k}{resumed} eq "" }
    my $h=$d->{handoffs} // {};
    print "handoff=$_ " for sort grep { !$h->{$_}{handled} } keys %$h;
    for my $e (@{$d->{events}}) {
      my $id="source:".(length($e->{event_id})<=153 ? $e->{event_id} : sha256_hex($e->{event_id}));
      print "source=$e->{event_id} " if ($e->{kind} eq "migrate" || ($e->{kind}!~/^(?:handoff-|gate-(?!verdict))/ && $e->{line}=~/^(working|done|blocked|needs-decision):/)) && !exists $h->{$id};
    }
  '
}

# 全部运行时写账经此入口。legacy仅保留未迁票格式；contract后权限/原子发布自动启用。
qwb_ledger() {
  local root="$1" task="$2" cmd="$3" ledger_bin
  shift 3
  ledger_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-ledger.sh"
  [[ -f "$ledger_bin" ]] || { echo "错误：缺 qwb-ledger.sh，拒绝绕过writer" >&2; return 1; }
  bash "$ledger_bin" "$cmd" --project "$root" --task "$task" --legacy -- "$@"
}

qwb_op_id() {
  perl -e 'open my $f,"<","/dev/urandom" or die $!; read($f,my $b,16)==16 or die "random不足"; print unpack("H*",$b)'
}

# —— herdr workspace list 响应 → TSV 行「id<TAB>focused<TAB>repo_root<TAB>linked<TAB>checkout_path」——
# 形状防御（R2-M2）：result.workspaces 必须是数组；每项 workspace_id 必须是非空 JSON 字符串
# （对象/数组/数字/布尔/null/空串一律判整体失败）。任一项不符 → 非 0 退出，调用方据此拒绝派发，
# 不静默跳过坏项、也不用缺 id 的项继续匹配。
# repo_root 只在部分 workspace 上有（取决于它怎么建的），没有就输出空串；有则归一成物理路径
# （realpath），好让 /tmp 与 /private/tmp 这类符号链接差异不影响等值比较。
qwb_ws_rows() {
  perl -MJSON::PP=decode_json,encode_json -MCwd=realpath -e '
    my $j = eval { decode_json(join "", <STDIN>) };
    exit 1 unless $j && ref $j eq "HASH" && ref $j->{result} eq "HASH"
      && ref $j->{result}{workspaces} eq "ARRAY";
    for my $w (@{ $j->{result}{workspaces} }) {
      exit 1 unless ref $w eq "HASH";
      my $id = $w->{workspace_id};
      exit 1 unless defined $id && !ref $id && $id ne "" && encode_json($id) =~ /^"/;
      my $rr = (ref $w->{worktree} eq "HASH") ? $w->{worktree}{repo_root} : undef;
      $rr = "" unless defined $rr && !ref $rr;
      if ($rr ne "") { my $cr = realpath($rr); $rr = $cr if defined $cr; }
      my $linked = (ref $w->{worktree} eq "HASH" && $w->{worktree}{is_linked_worktree}) ? 1 : 0;
      my $checkout = (ref $w->{worktree} eq "HASH") ? $w->{worktree}{checkout_path} : undef;
      $checkout = "" unless defined $checkout && !ref $checkout;
      if ($checkout ne "") { my $cc = realpath($checkout); $checkout = $cc if defined $cc; }
      printf "%s\t%s\t%s\t%s\t%s\n", $id, ($w->{focused} ? 1 : 0), $rr, $linked, $checkout;
    }
  '
}

# resolve_workspace <项目根> —— 解析工人/值守 tab 应落在哪个 herdr workspace
#
# 三级规则（取第一个命中）：
#   1. config.sh 声明了 QWB_WORKSPACE：必须是本机 herdr 里真实存在的 workspace id，否则拒绝
#      （不是静默回退——声明写错了就报错让人改 config，别把工人送到别处去）
#   2. 未声明：按 herdr workspace list 里 worktree.repo_root 物理路径 == 项目根物理路径匹配；
#      多于一个匹配则取 focused 的，都不 focused 取第一个并 stderr 警告
#   3. 都没有：回退调用者 workspace（输出空串）+ stderr 一行警告
#
# stdout：workspace id（空串 = 用调用者 workspace，调用方不要传 --workspace）
# 返回：0 = 解析完成（输出可能为空）；非 0 = 拒绝（响应不符契约 / 查询失败 / 声明的 id 不存在）
# 查询失败与响应不合契约都在任何副作用之前非 0 退出，让调用方 fail-closed。
resolve_workspace() {
  local root="${1:-}" quiet_fallback="${2:-}" declared="${QWB_WORKSPACE:-}" raw rows avail
  [[ -n "$root" ]] || root="$(pwd)"
  if ! raw="$(herdr workspace list 2>&1)"; then
    {
      echo "错误：herdr workspace list 查询失败，无法确定工人 tab 落在哪个 workspace——拒绝派发。原始错误："
      printf '%s\n' "$raw"
    } >&2
    return 1
  fi
  if ! rows="$(printf '%s' "$raw" | qwb_ws_rows)"; then
    {
      echo "错误：herdr workspace list 响应不符合契约（result.workspaces[].workspace_id 必须是非空字符串）——拒绝派发。原始响应："
      printf '%s\n' "$raw"
    } >&2
    return 1
  fi
  avail="$(printf '%s\n' "$rows" | cut -f1 | grep -v '^$' | paste -sd, -)"
  if [[ -n "$declared" ]]; then
    if printf '%s\n' "$rows" | perl -F'\t' -lane 'BEGIN { $id = shift @ARGV; $found = 0 } $found = 1 if @F >= 4 && $F[0] eq $id && $F[3] eq "0"; END { exit($found ? 0 : 1) }' "$declared"; then
      printf '%s' "$declared"
      return 0
    fi
    {
      echo "错误：config.sh 声明了 QWB_WORKSPACE='${declared}'，但本机 herdr 里没有这个主 workspace（或它是任务 worktree Space；现有：${avail}）——拒绝派发。"
      echo "修复：把 QWB_WORKSPACE 改成上面某个 id，或清空它（留空则按 worktree.repo_root 自动匹配项目根）。"
    } >&2
    return 1
  fi
  local rroot hits="" id f first="" focus="" n=0
  rroot="$(cd "$root" 2>/dev/null && pwd -P)" || rroot="$root"
  hits="$(printf '%s\n' "$rows" | perl -F'\t' -lane 'BEGIN { $r = shift @ARGV } print "$F[0]\t$F[1]" if @F >= 4 && $F[2] ne "" && $F[2] eq $r && $F[3] eq "0"' "$rroot")"
  while IFS=$'\t' read -r id f; do
    if [[ -n "$id" ]]; then
      n=$((n + 1))
      if [[ -z "$first" ]]; then first="$id"; fi
      if [[ "$f" == "1" && -z "$focus" ]]; then focus="$id"; fi
    fi
  done <<< "$hits"
  if (( n == 0 )); then
    if [[ "$quiet_fallback" != task-worktree ]]; then
      echo "警告：工人 tab 开在调用者 workspace ${HERDR_WORKSPACE_ID:-（未知）}——本项目未声明 QWB_WORKSPACE；跨项目派活请在 <项目>/qwbuddy/config.sh 里填 QWB_WORKSPACE=<该项目 workspace id>" >&2
    fi
    return 0
  fi
  if [[ -n "$focus" ]]; then
    printf '%s' "$focus"
    return 0
  fi
  if (( n > 1 )); then
    echo "警告：多个 workspace 匹配项目根 ${root}（都不 focused），取第一个 ${first}——请在 config.sh 用 QWB_WORKSPACE 明确指定" >&2
  fi
  printf '%s' "$first"
  return 0
}

# 本项目指定 linked Git worktree 在 Spaces 中的唯一 workspace ID；不存在时输出空串。
# 查询失败、响应不合法或同一路径重复登记均失败关闭。
qwb_worktree_space() {
  local root="$1" dir="$2" raw rows matches count
  raw="$(herdr workspace list 2>&1)" || { echo "错误：herdr workspace list 失败：$raw" >&2; return 1; }
  rows="$(printf '%s' "$raw" | qwb_ws_rows)" || { echo "错误：herdr workspace list 响应不合法" >&2; return 1; }
  root="$(cd "$root" && pwd -P)" || return 1
  dir="$(cd "$dir" && pwd -P)" || return 1
  matches="$(printf '%s\n' "$rows" | perl -F'\t' -lane '
    BEGIN { ($root, $dir) = splice @ARGV, 0, 2 }
    print "$F[0]\t$F[2]" if @F >= 5 && $F[3] eq "1" && $F[4] eq $dir
  ' "$root" "$dir")"
  count="$(printf '%s\n' "$matches" | grep -c . || true)"
  [[ "$count" -le 1 ]] || { echo "错误：同一 worktree 对应多个 Herdr Space：$dir" >&2; return 1; }
  if [[ -n "$matches" && "${matches#*$'\t'}" != "$root" ]]; then
    echo "错误：worktree Space ${matches%%$'\t'*} 的 repo_root 与项目根不符，拒绝操作：$dir" >&2
    return 1
  fi
  printf '%s' "${matches%%$'\t'*}"
}

# 路径必须是本项目登记的独立 Git worktree，不能把普通目录或别的仓库误当任务 Space。
qwb_is_project_worktree() {
  local root="$1" dir="$2" root_phys dir_phys top p listing
  root_phys="$(cd "$root" 2>/dev/null && pwd -P)" || return 1
  dir_phys="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
  [[ "$dir_phys" != "$root_phys" ]] || return 1
  top="$(git -C "$dir_phys" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ "$(cd "$top" 2>/dev/null && pwd -P)" == "$dir_phys" ]] || return 1
  listing="$(git -C "$root_phys" worktree list --porcelain)" \
    || { echo "错误：无法查询本项目 Git worktree 列表" >&2; return 2; }
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    [[ "$(cd "$p" 2>/dev/null && pwd -P)" == "$dir_phys" ]] && return 0
  done < <(printf '%s\n' "$listing" | sed -n 's/^worktree //p')
  return 1
}

# Actual native activity; unknown refuses reuse rather than trusting a Herdr idle edge.
qwb_pane_activity() {
  local helper data
  helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-herdr.sh"
  data="$(bash "$helper" activity --project "${PROJECT_ROOT:-$PWD}" --pane "$1" --dir "$2" --task "$3")" || return 1
  printf '%s' "$data" | perl -MJSON::PP -0777 -e 'print decode_json(<STDIN>)->{activity}'
}

# worker_lost <任务书> —— 工人丢失判定（关机/herdr 重启后 pane 没了，票还 running）
#
# 取该票最新一条 dispatch: 的 pane=，herdr pane get 判活：
#   pane_not_found → 端点丢失：stdout 打印 pane id，返回 0；
#   agent 字段为空仅证明原生标签已退回，可能旧CLI仍后台存活 → unknown，不猜死亡。
#   agent 仍在 → 未丢失，返回 1；无 dispatch 行（未派）→ 未丢失，返回 1
#   其他查询失败 / 响应不合契约 → 无法判定：stderr 一行「无法确认工人状态」，返回 2（不当丢失，不猜）
# 只应在有 herdr 且非 --dry-run 的路径调用（判定需要真实查询）。
worker_lost() {
  local f="$1" disp pane out v
  disp="$(grep '^dispatch:' "$f" 2>/dev/null | tail -1 || true)"
  [[ -n "$disp" ]] || return 1
  pane="$(printf '%s\n' "$disp" | grep -o 'pane=[^[:space:]]*' | head -1 | cut -d= -f2)"
  [[ -n "$pane" ]] || return 1
  if ! out="$(herdr pane get "$pane" 2>&1)"; then
    if printf '%s\n' "$out" | grep -q 'pane_not_found'; then
      printf '%s\n' "$pane"
      return 0
    fi
    echo "无法确认工人状态（herdr pane get ${pane} 查询失败：${out}）" >&2
    return 2
  fi
  v="$(printf '%s\n' "$out" | perl -MJSON::PP=decode_json -0777 -e '
    my $j = eval { decode_json(<STDIN>) };
    my $p = ($j && ref $j eq "HASH" && ref $j->{result} eq "HASH" && ref $j->{result}{pane} eq "HASH")
      ? $j->{result}{pane} : undef;
    exit 2 unless defined $p;
    print((defined $p->{agent} && $p->{agent} ne "") ? "live" : "lost");
  ' 2>/dev/null || true)"
  case "$v" in
    live) return 1 ;;
    lost) echo "无法确认工人状态（pane ${pane} 原生标签已退回，但原PID死亡未证明；保留现场）" >&2; return 2 ;;
    *)    echo "无法确认工人状态（herdr pane get ${pane} 响应不符合契约）" >&2; return 2 ;;
  esac
}
