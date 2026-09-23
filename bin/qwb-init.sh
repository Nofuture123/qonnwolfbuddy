#!/usr/bin/env bash
# qwb-init.sh —— 把 QW buddy 装进一个项目（幂等：已装过不重复追加）
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-init.sh <项目根目录>
      qwb-init.sh --migrate-worker-config <项目根目录>

把 templates/ 与 bin/ 装进 <项目>/qwbuddy/，建 tasks/ 与 tasks/lessons/，
并把钩子片段追加进 AGENTS.md / CLAUDE.md（幂等，可重复运行）。

选项:
  --migrate-worker-config  显式迁移旧长串配置；先备份，不猜测歧义项
  -h, --help    显示本帮助
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
MIGRATE=0
if [[ "${1:-}" == --migrate-worker-config ]]; then MIGRATE=1; shift; fi
[[ $# -eq 1 ]] || { usage >&2; exit 2; }

[[ -d "$1" ]] || { echo "错误：项目目录不存在：$1" >&2; exit 1; }
ROOT="$(cd "$1" && pwd)"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$SRC/../templates"

[[ -d "$TPL" ]] || { echo "错误：找不到模板目录 ${TPL}——本脚本只在 QW buddy 母本仓运行（安装副本里的同名文件属历史残留，请改用母本仓 bin/qwb-init.sh 的绝对路径）" >&2; exit 1; }

if [[ "$MIGRATE" -eq 1 ]]; then
  conf="$ROOT/qwbuddy/config.sh"; workers="$ROOT/qwbuddy/workers.sh"
  [[ ! -L "$ROOT/qwbuddy" && -d "$ROOT/qwbuddy" && ! -L "$conf" && ! -L "$workers" ]] \
    || { echo "错误：迁移目标目录或配置是符号链接，拒绝修改" >&2; exit 1; }
  [[ -f "$conf" ]] || { echo "错误：迁移所需 config.sh 不存在：${conf}" >&2; exit 1; }
  # 只迁移独立、单行、静态赋值；同一行命令或跨行引号一律留给人工处理。
  if ! CONF_TO_CHECK="$conf" python3 - <<'PYEOF'
import os, re, sys
lines = open(os.environ['CONF_TO_CHECK'], encoding='utf-8').read().splitlines()
name = re.compile(r'QWB_WORKER_(?:LAUNCH|ARGS)')
valid = re.compile(r'''\s*(?:export\s+)?QWB_WORKER_(?:LAUNCH|ARGS)=(?:"[^"$`\\]*"|'[^']*'|[A-Za-z0-9_./:=+-]*)\s*(?:#.*)?''')
for number, line in enumerate(lines, 1):
    if name.search(line) and not line.lstrip().startswith('#') and not valid.fullmatch(line):
        print(f'错误：config.sh:{number} 的旧工人赋值不是可证明的独立静态单行；原文件未动', file=sys.stderr)
        sys.exit(1)
PYEOF
  then exit 1; fi
  if ! grep -Eq '^[[:space:]]*(export[[:space:]]+)?QWB_WORKER_(LAUNCH|ARGS)=' "$conf"; then
    unset QWB_WORKER_LAUNCH QWB_WORKER_ARGS
    # shellcheck source=/dev/null
    . "$conf"
    [[ ! ${QWB_WORKER_LAUNCH+x} && ! ${QWB_WORKER_ARGS+x} ]] \
      || { echo "错误：config.sh 间接设置旧工人配置，无法可靠迁移；原文件未动" >&2; exit 1; }
    [[ -f "$workers" ]] && { echo "跳过：工人启动配置已迁移（幂等）"; exit 0; }
    echo "错误：旧启动配置不存在且 workers.sh 缺失；请检查安装副本" >&2; exit 1
  fi
  [[ ! -e "$workers" && ! -L "$workers" ]] || { echo "错误：旧配置与 workers.sh 同时存在；请先人工解决两处启动定义，原文件未动" >&2; exit 1; }
  backup="$conf.worker-config.bak"
  [[ ! -e "$backup" && ! -L "$backup" ]] \
    || { echo "错误：备份已存在 ${backup}，拒绝覆盖；原文件未动" >&2; exit 1; }
  [[ "$(grep -Ec '^[[:space:]]*(export[[:space:]]+)?QWB_WORKER_LAUNCH=' "$conf")" -le 1 \
     && "$(grep -Ec '^[[:space:]]*(export[[:space:]]+)?QWB_WORKER_ARGS=' "$conf")" -le 1 ]] \
    || { echo "错误：旧配置有重复 QWB_WORKER_LAUNCH / QWB_WORKER_ARGS 赋值；请先人工合并，原文件未动" >&2; exit 1; }
  unset QWB_WORKER_LAUNCH QWB_WORKER_ARGS
  # shellcheck source=/dev/null
  . "$conf"
  set -f  # 旧格式本来会 glob 展开；含通配符的值下方拒绝，避免迁移依赖目录内容。
  for map in "${QWB_WORKER_LAUNCH:-}" "${QWB_WORKER_ARGS:-}"; do
    case "$map" in *'*'*|*'?'*|*'['*) echo "错误：旧工人配置含 glob 通配符（* ? [），argv 依赖目录内容，原文件未动" >&2; exit 1 ;; esac
  done
  parse_old_map() { # $1=原长串，产出 MAP_NAMES / MAP_VALUES；拒绝旧解析会吞并的名字与重复项
    local part prefix known seen cur=-1
    MAP_NAMES=(); MAP_VALUES=()
    for part in $1; do
      if [[ "$part" == *=* && "$part" != -* ]]; then
        prefix="${part%%=*}"; known=0
        for seen in $QWB_WORKERS; do [[ "$seen" == "$prefix" ]] && known=1; done
        [[ "$known" -eq 1 ]] || { echo "错误：旧配置含未知工人 '${prefix}'，无法可靠迁移；原文件未动" >&2; return 1; }
        for seen in "${MAP_NAMES[@]+"${MAP_NAMES[@]}"}"; do
          [[ "$seen" == "$prefix" ]] && { echo "错误：旧配置工人 '${prefix}' 重复定义，无法可靠迁移；原文件未动" >&2; return 1; }
        done
        MAP_NAMES+=("$prefix"); MAP_VALUES+=("${part#*=}"); cur=$((${#MAP_NAMES[@]}-1))
      else
        [[ "$cur" -ge 0 ]] || { echo "错误：旧配置首项 '${part}' 无工人名，无法可靠迁移；原文件未动" >&2; return 1; }
        MAP_VALUES[cur]="${MAP_VALUES[cur]}${MAP_VALUES[cur]:+ }${part}"
      fi
    done
  }
  parse_old_map "${QWB_WORKER_LAUNCH:-}" || exit 1
  launch_names=("${MAP_NAMES[@]+"${MAP_NAMES[@]}"}"); launch_values=("${MAP_VALUES[@]+"${MAP_VALUES[@]}"}")
  parse_old_map "${QWB_WORKER_ARGS:-}" || exit 1
  args_names=("${MAP_NAMES[@]+"${MAP_NAMES[@]}"}"); args_values=("${MAP_VALUES[@]+"${MAP_VALUES[@]}"}")
  tmp_workers="$(mktemp "$ROOT/qwbuddy/.workers.XXXXXX")"
  tmp_conf="$(mktemp "$ROOT/qwbuddy/.config.XXXXXX")"
  trap 'rm -f "$tmp_workers" "$tmp_conf"' EXIT
  quote_worker_arg() {
    local rest="$1" quoted="'"
    while [[ "$rest" == *"'"* ]]; do
      quoted="${quoted}${rest%%\'*}'\\''"
      rest="${rest#*\'}"
    done
    printf "%s%s'" "$quoted" "$rest"
  }
  printf '%s\n' '# 由 qwb-init.sh 显式迁移；每个参数是一个 Bash 实参。' > "$tmp_workers"
  for worker in $QWB_WORKERS; do
    mode=herdr; launch=""; launch_seen=0; args=""
    for i in "${!launch_names[@]}"; do [[ "${launch_names[i]}" == "$worker" ]] && { launch="${launch_values[i]}"; launch_seen=1; }; done
    for i in "${!args_names[@]}"; do [[ "${args_names[i]}" == "$worker" ]] && args="${args_values[i]}"; done
    [[ "$launch_seen" -eq 0 || -n "$launch" ]] || { echo "错误：工人 '${worker}' 旧 launch 显式空值，原运行会拒绝；原文件未动" >&2; exit 1; }
    if [[ -n "$launch" && "$launch" != herdr ]]; then
      [[ "$launch" == pane-run:* ]] || { echo "错误：工人 '${worker}' 启动方式 '${launch}' 非法，原文件未动" >&2; exit 1; }
      mode=pane-run; launch="${launch#pane-run:}"
      [[ -n "$launch" && -z "$args" ]] || { echo "错误：工人 '${worker}' pane-run 命令为空或两处重复参数，原文件未动" >&2; exit 1; }
      first_arg=1
      for arg in $launch; do
        [[ "$arg" =~ ^[A-Za-z0-9_./:@%+=-]+$ ]] \
          || { echo "错误：工人 '${worker}' 的旧 pane-run 命令含 ~/{}/# 等 shell 语义或引用，参数边界无法可靠迁移；原文件未动" >&2; exit 1; }
        if [[ "$first_arg" -eq 1 && "$arg" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
          echo "错误：工人 '${worker}' 的旧 pane-run 以环境赋值开头，无法可靠迁移；原文件未动" >&2; exit 1
        fi
        first_arg=0
      done
      args="$launch"
    fi
    printf 'qwb_worker %s %s' "$(quote_worker_arg "$worker")" "$(quote_worker_arg "$mode")" >> "$tmp_workers"
    for arg in $args; do
      case "$arg" in -p|--print|--exec|exec|-p=*|--print=*|--exec=*|exec=*) echo "错误：工人 '${worker}' 含 headless 参数 '${arg}'，原文件未动" >&2; exit 1 ;; esac
      printf ' %s' "$(quote_worker_arg "$arg")" >> "$tmp_workers"
    done
    printf '\n' >> "$tmp_workers"
  done
  cp -p "$conf" "$tmp_conf"
  sed -E '/^[[:space:]]*(export[[:space:]]+)?QWB_WORKER_(LAUNCH|ARGS)=/d' "$conf" > "$tmp_conf"
  { bash -n "$tmp_workers" && bash -n "$tmp_conf"; } || { echo "错误：生成配置语法无效，原文件未动" >&2; exit 1; }
  cp -p "$conf" "$backup"
  mv "$tmp_workers" "$workers"
  mv "$tmp_conf" "$conf"
  echo "完成：已备份 ${backup}，写入 workers.sh 并移除旧长串赋值；再次迁移会跳过"
  exit 0
fi

# 专项文档只安装固定清单；写入前拒绝缺源和符号链接目标。
guide_docs=(ci-guide.md host-watch-guide.md worker-launch-guide.md)
for doc in "${guide_docs[@]}"; do
  [[ -f "$TPL/$doc" ]] || { echo "错误：缺少专项文档源文件：$TPL/$doc" >&2; exit 1; }
done

check_install_dir() {
  local path="$1"
  [[ ! -L "$path" && ( ! -e "$path" || -d "$path" ) ]] \
    || { echo "错误：安装目录不是普通目录：$path" >&2; return 1; }
}
check_install_file() {
  local path="$1"
  [[ ! -L "$path" && ( ! -e "$path" || -f "$path" ) ]] \
    || { echo "错误：安装目标不是普通文件：$path" >&2; return 1; }
}
check_preserved_file() {
  local path="$1"
  [[ ! -L "$path" || -f "$path" ]] \
    || { echo "错误：保留目标是断开或非文件的符号链接：$path" >&2; return 1; }
  [[ ! -e "$path" || -f "$path" ]] \
    || { echo "错误：保留目标不是普通文件：$path" >&2; return 1; }
}
atomic_copy() {
  local src="$1" dst="$2" tmp
  tmp="$(mktemp "$(dirname "$dst")/.qwb-install.XXXXXXXX")" || return 1
  if ! cp -p "$src" "$tmp" || ! mv -f "$tmp" "$dst"; then
    rm -f "$tmp"
    return 1
  fi
}

# 先核对本次可能写入的全部路径，避免晚发现链接时留下半套安装。
for dir in "$ROOT/qwbuddy" "$ROOT/qwbuddy/roles" "$ROOT/qwbuddy/bin" \
           "$ROOT/tasks" "$ROOT/tasks/lessons" "$ROOT/.pi" "$ROOT/.pi/extensions" \
           "$ROOT/.claude"; do
  check_install_dir "$dir" || exit 1
done
for dst in "$ROOT/qwbuddy/QWBUDDY.md" "$ROOT/qwbuddy/TASK.md" \
           "$ROOT/.gitignore" "$ROOT/AGENTS.md" "$ROOT/CLAUDE.md" \
           "$ROOT/.pi/extensions/qwb-watch.ts" "$ROOT/.pi/extensions/qwb-watch.ts.bak" \
           "$ROOT/.claude/settings.json"; do
  check_install_file "$dst" || exit 1
done
for doc in "${guide_docs[@]}"; do check_install_file "$ROOT/qwbuddy/$doc" || exit 1; done
for src in "$TPL"/roles/*.md; do check_install_file "$ROOT/qwbuddy/roles/$(basename "$src")" || exit 1; done
for src in "$SRC"/qwb-*.sh; do
  [[ "$(basename "$src")" == "qwb-init.sh" ]] && continue
  check_install_file "$ROOT/qwbuddy/bin/$(basename "$src")" || exit 1
done
for dst in "$ROOT/qwbuddy/config.sh" "$ROOT/qwbuddy/workers.sh" \
           "$ROOT/qwbuddy/brief-include.md" "$ROOT/qwbuddy/dispatch-rules.json"; do
  check_preserved_file "$dst" || exit 1
done

mkdir -p "$ROOT/qwbuddy/roles" "$ROOT/qwbuddy/bin" "$ROOT/tasks/lessons"

atomic_copy "$TPL/QWBUDDY.md" "$ROOT/qwbuddy/QWBUDDY.md"
for doc in "${guide_docs[@]}"; do
  atomic_copy "$TPL/$doc" "$ROOT/qwbuddy/$doc" || { echo "错误：安装专项文档失败：$doc" >&2; exit 1; }
done
atomic_copy "$TPL/TASK.md" "$ROOT/qwbuddy/TASK.md"
for src in "$TPL"/roles/*.md; do atomic_copy "$src" "$ROOT/qwbuddy/roles/$(basename "$src")"; done

# config.sh 可能被主控填过 QWB_CONTROLLER_PANE——已存在就不覆盖；只检测到旧版配置时提示手动迁移
OLD_CONF_NAME="config.json"
NEW_CONF=0
if [[ -f "$ROOT/qwbuddy/config.sh" ]]; then
  echo "保留：qwbuddy/config.sh 已存在，不覆盖"
else
  OLD_CONF="$ROOT/qwbuddy/$OLD_CONF_NAME"
  if [[ -f "$OLD_CONF" ]]; then
    echo "提示：检测到旧版 ${OLD_CONF}——新版配置为 bash 可直接 source 的 config.sh，旧文件不自动转换，请手动迁移后删除" >&2
  fi
  atomic_copy "$TPL/config.sh" "$ROOT/qwbuddy/config.sh"
  NEW_CONF=1
fi
if grep -Eq '^[[:space:]]*(export[[:space:]]+)?QWB_WORKER_(LAUNCH|ARGS)=' "$ROOT/qwbuddy/config.sh"; then
  echo "提示：旧工人长串配置已保留；派发前须显式运行 bin/qwb-init.sh --migrate-worker-config '$ROOT'" >&2
elif [[ -f "$ROOT/qwbuddy/workers.sh" ]]; then
  echo "保留：qwbuddy/workers.sh 已存在，不覆盖"
else
  if [[ "$NEW_CONF" -eq 1 ]]; then
    atomic_copy "$TPL/workers.sh" "$ROOT/qwbuddy/workers.sh"
  else
    echo "提示：已有 config.sh 但缺少 workers.sh；未读取/执行用户配置，也未写入可能不匹配的默认工人表，当前不可派发。请手动创建 qwbuddy/workers.sh，为 QWB_WORKERS 的每个工人写一条 qwb_worker 声明（见母本仓 templates/workers.sh）；原配置未改动。" >&2
  fi
fi

# 常驻附页模板：目标已有则不覆盖（可能已被项目主人改成自己的常驻规则），幂等
if [[ -f "$ROOT/qwbuddy/brief-include.md" ]]; then
  echo "保留：qwbuddy/brief-include.md 已存在，不覆盖"
else
  atomic_copy "$TPL/brief-include.md" "$ROOT/qwbuddy/brief-include.md"
fi

# 运行时脚本装进目标项目；qwb-init.sh 是母本仓专用安装器，不复制进目标
for s in "$SRC"/qwb-*.sh; do
  [[ "$(basename "$s")" == "qwb-init.sh" ]] && continue
  atomic_copy "$s" "$ROOT/qwbuddy/bin/$(basename "$s")"
done

# 派工规则模板：目标已有不覆盖（可能已被项目主人改成自己的派工规则），幂等（同 brief-include 做法）
if [[ -f "$ROOT/qwbuddy/dispatch-rules.json" ]]; then
  echo "保留：qwbuddy/dispatch-rules.json 已存在，不覆盖"
else
  atomic_copy "$TPL/dispatch-rules.json" "$ROOT/qwbuddy/dispatch-rules.json"
fi

# 运行态不进 git：往 <项目根>/.gitignore 追加一段；旧段补缺项。
# 只追加不重排——项目原有条目字节不变。
GITIGN="$ROOT/.gitignore"
ignore_rules=(
  '.worktrees/'
  'qwbuddy/.controller.lock/'
  'qwbuddy/.watch'
  'qwbuddy/.watch.lock/'
  'qwbuddy/.hook.lock/'
  'qwbuddy/.hook.err'
  'qwbuddy/.pi-watch.err'
)
gitign_tmp="$(mktemp "$ROOT/.qwb-gitignore.XXXXXXXX")"
if [[ -f "$GITIGN" ]]; then cp -p "$GITIGN" "$gitign_tmp"; fi
if [[ -f "$GITIGN" ]] && grep -qF '# QW buddy 运行态（qwb-init.sh 写入，勿手改本段）' "$GITIGN"; then
  had_marker=1
else
  had_marker=0
  if [[ -s "$gitign_tmp" && -n "$(tail -c1 "$gitign_tmp")" ]]; then printf '\n' >> "$gitign_tmp"; fi
  printf '%s\n' '# QW buddy 运行态（qwb-init.sh 写入，勿手改本段）' >> "$gitign_tmp"
fi
added=0
for rule in "${ignore_rules[@]}"; do
  if ! grep -qxF "$rule" "$gitign_tmp"; then
    if [[ $added -eq 0 && $had_marker -eq 1 && -s "$gitign_tmp" && -n "$(tail -c1 "$gitign_tmp")" ]]; then printf '\n' >> "$gitign_tmp"; fi
    printf '%s\n' "$rule" >> "$gitign_tmp"
    added=1
  fi
done
if [[ $had_marker -eq 0 || $added -eq 1 ]]; then
  mv -f "$gitign_tmp" "$GITIGN"
else
  rm -f "$gitign_tmp"
fi
if [[ $had_marker -eq 0 ]]; then
  echo "写入：.gitignore 追加 QW buddy 运行态"
elif [[ $added -eq 1 ]]; then
  echo "写入：.gitignore 旧 QW buddy 段补齐运行态"
else
  echo "跳过：.gitignore 已有"
fi

# 钩子：已含 qwbuddy/QWBUDDY.md 引用视为已装，跳过
append_hook() {
  local target="$1" hook="$2" tmp
  if [[ -f "$target" ]] && grep -qF 'qwbuddy/QWBUDDY.md' "$target"; then
    echo "跳过：$(basename "$target") 已有 QW buddy 钩子"
  else
    tmp="$(mktemp "$ROOT/.qwb-hook.XXXXXXXX")" || return 1
    if [[ -f "$target" ]]; then cp -p "$target" "$tmp" || return 1; fi
    { echo; cat "$TPL/$hook"; } >> "$tmp" || return 1
    mv -f "$tmp" "$target" || return 1
    echo "写入：$(basename "$target") 追加 QW buddy 钩子"
  fi
}

append_hook "$ROOT/AGENTS.md" agents-hook.md
append_hook "$ROOT/CLAUDE.md" claude-hook.md

# Pi 主控值守扩展：装到 .pi/extensions/qwb-watch.ts（值守隐形化，随 pi 进程生死）。
# 幂等三态：不存在 → 新建（重启 pi 或 /reload 后生效）；内容一致 → 不重写（mtime 不变）；
# 内容不同 → 备份为 .bak 后覆盖并在 stdout 说明（目标可能被项目主人改过，不丢内容）。
install_pi_ext() {
  local src="$TPL/pi-extensions/qwb-watch.ts"
  local dst="$ROOT/.pi/extensions/qwb-watch.ts"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    echo "跳过：.pi/extensions/qwb-watch.ts 内容一致（幂等）"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]]; then
    atomic_copy "$dst" "$dst.bak"
    atomic_copy "$src" "$dst"
    echo "写入：.pi/extensions/qwb-watch.ts 已更新（旧内容备份为 qwb-watch.ts.bak；重启 pi 或 /reload 生效）"
  else
    atomic_copy "$src" "$dst"
    echo "写入：.pi/extensions/qwb-watch.ts（重启 pi 或 /reload 后扩展生效）"
  fi
}
install_pi_ext

# Claude Code Stop hook（值守隐形化）：合并进 .claude/settings.json。
# 幂等（仅完整规范命令及执行配置判重）、不覆盖已有 hooks（其他键原样）；
# 文件不存在则新建；非法 JSON 拒绝写入（qwbuddy/ 其余安装已照常完成，stderr 说明）。
# 用 python3：dict 保插入序 + indent=2 重写后别人的内容字节级不变；不用 jq（不保证装了）。
merge_claude_hook() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "错误：本机无 python3，无法安全合并 .claude/settings.json——该文件未写入；qwbuddy/ 其余部分已装好，可装 python3 后重跑 qwb-init.sh（幂等）或手动添加 Stop hook" >&2
    return 1
  fi
  CLAUDE_SETTINGS="$ROOT/.claude/settings.json" python3 - <<'PYEOF'
import json, os, sys, tempfile

path = os.environ["CLAUDE_SETTINGS"]
entry = {
    "type": "command",
    "command": 'bash "$CLAUDE_PROJECT_DIR"/qwbuddy/bin/qwb-hook-claude-stop.sh',
    "asyncRewake": True,
    "timeout": 7200,
}

def die(msg):
    sys.stderr.write(
        f"错误：{msg}\n未写入：{path}\n"
        "说明：qwbuddy/ 其余安装已照常完成，仅 Claude Code Stop hook 未写入；"
        "修复该文件后重跑 qwb-init.sh（幂等）即可补上。\n"
    )
    sys.exit(1)

if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    try:
        data = json.loads(raw)
    except ValueError as e:
        die(f"{path} 不是合法 JSON（{e}）——拒绝写入，原文件保持逐字节不变")
    if not isinstance(data, dict):
        die(f"{path} 顶层不是 JSON 对象，拒绝写入")
else:
    data = {}

hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
    die(f"{path} 的 hooks 不是 JSON 对象，拒绝写入")
stop = hooks.setdefault("Stop", [])
if not isinstance(stop, list):
    die(f"{path} 的 hooks.Stop 不是 JSON 数组，拒绝写入")

def has_qwb(groups):
    for g in groups:
        if isinstance(g, dict):
            hooks = g.get("hooks")
            if g.get("matcher") not in (None, "") or not isinstance(hooks, list):
                continue
            for h in hooks:
                if isinstance(h, dict) and all(h.get(k) == v for k, v in entry.items()):
                    return True
    return False

if has_qwb(stop):
    print("跳过：.claude/settings.json 已有 qwb-hook-claude-stop.sh Stop hook（幂等）")
else:
    stop.append({"hooks": [entry]})
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".qwb-settings.", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    print("写入：.claude/settings.json 合并 Claude Code Stop hook（值守，asyncRewake）")
PYEOF
}

if ! merge_claude_hook; then
  exit 1
fi

echo "完成：QW buddy 已装进 ${ROOT}（账本：${ROOT}/tasks/）"
