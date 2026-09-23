#!/usr/bin/env bash
# qwb-lib.sh —— QW buddy 运行时共享库：被 qwb-run.sh / qwb-wake.sh source（库文件，不直接运行）
#
# 本文件只定义函数：不执行动作、不设置 shell 选项（set -euo pipefail 归调用方）。
# 因此它自己不是可运行脚本——QWBUDDY.md §9 表里按「库文件，不直接运行」列出。

# 只提取首个 state 值；是否有 state 字段、值是否合法由调用方决定。
qwb_task_state() {
  sed -n 's/^state:[[:space:]]*//p' "$1" | head -1 | tr -d '[:space:]'
}

# 最后一条规格疑点相关事件；普通进展行不解除疑点。
qwb_last_spec_event() {
  grep -E '^blocked:[[:space:]]*spec-defect:|^working:[[:space:]]*spec-resolved:' "$1" | tail -1 || true
}

# 与派发和 lint 共用的场景块边界；保留原始行字节供现有指纹算法使用。
qwb_scenario_block() {
  awk '
    inblk==0 && /^#{1,6}[^#]*验收场景/ { inblk=1; print; next }
    inblk==1 && (/^#{1,2}[^#]/ || /^(working|done|blocked|needs-decision|dispatch|not-sent|wake|worktree|worktree-space|scenarios-fp):/) { inblk=0 }
    inblk==1 { print }
  ' "$1"
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
  local root="${1:-}" declared="${QWB_WORKSPACE:-}" raw rows avail
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
    echo "警告：工人 tab 开在调用者 workspace ${HERDR_WORKSPACE_ID:-（未知）}——本项目未声明 QWB_WORKSPACE；跨项目派活请在 <项目>/qwbuddy/config.sh 里填 QWB_WORKSPACE=<该项目 workspace id>" >&2
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

# worker_lost <任务书> —— 工人丢失判定（关机/herdr 重启后 pane 没了，票还 running）
#
# 取该票最新一条 dispatch: 的 pane=，herdr pane get 判活：
#   pane_not_found，或 pane 在但 agent 字段为空（工人进程已退出、pane 退回 shell）
#     → 工人丢失：stdout 打印 pane id，返回 0
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
    lost) printf '%s\n' "$pane"; return 0 ;;
    *)    echo "无法确认工人状态（herdr pane get ${pane} 响应不符合契约）" >&2; return 2 ;;
  esac
}
