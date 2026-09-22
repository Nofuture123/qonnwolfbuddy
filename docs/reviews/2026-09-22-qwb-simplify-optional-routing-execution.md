# ④ 可选路由结构化接口执行报告

- 角色：执行者 Sol medium；未提交、未 push、未运行 full。
- 基线：`e74a7edaa62303a49c99c272ca2e6fd26436659b`；开工时 `git status --short` 为空。
- 源码候选：该基线之上的当前工作区 tracked diff，加未跟踪 `tests/optional-routing.sh`。主仓共享账本与本报告不属于候选源码。
- 问题核实：基线 `qwb-run.sh` 用 `sed` 从展示文本取 status/worker/reason，回退时再次读取规则文件；`qwb-dispatch.sh` 在规则校验前执行无 key 的 off 门。显式 worker 基线代码不进入 auto 分支，本轮没有重写该分支。

## 修改

- `bin/qwb-dispatch.sh`：新增 `--json` 单对象输出；规则先快照并验证，再处理无 key 的 off 门；结构化结果携带同一已验证快照的 `default_worker`；原默认展示保留。
- `bin/qwb-run.sh`：auto 只解析并验证 JSON 的状态、工人、默认工人；拒绝非法或多对象结果；不再从展示文本或第二次规则读取选工人。显式路径保留。
- `templates/QWBUDDY.md`：说明机器契约与坏规则无 key 时的失败分类。
- `tests/optional-routing.sh`：临时项目、假 HTTP、假 Herdr 的公开 CLI 定向测试；`tests/smoke.sh` 第 49 节调用它，接入既有 full/smoke 入口。

## 实跑证据

- 初始 red：`bash tests/optional-routing.sh`，exit 2（基线尚无 `--json`）。
- 最终 `bash tests/optional-routing.sh`，exit 0，15 项 PASS：JSON clear、人读展示、规则快照绑定、坏规则无 key、显式工人、env 读取探针正控、auto clear/off/ambiguous/error、坏规则、多 JSON、缺状态、诊断文字不影响选择、未知工人。
- 显式路径用临时安装副本包装 dispatch 记录调用数，以普通 `.env` 假 key 和假 grep 记录该文件读取数：dispatch=0、env-read=0、curl=0；auto 正控 dispatch=1、env-read=1。未读取或打印真实 key。
- 前置拒绝在默认 worktree 模式运行：坏规则 exit 2、非法结构 exit 2、未知工人 exit 1；各自任务书 shasum 前后相同，无 Herdr 调用、无 `.worktrees` 创建。
- `bash bin/qwb-test.sh fast`，exit 0；`bash tests/boundary-readiness.sh`，exit 0、`BOUNDARY PASS`；`shellcheck tests/optional-routing.sh`、`bash -n tests/optional-routing.sh`、`git diff --check` 均 exit 0。
- 未运行 `bash bin/qwb-test.sh full`（主控唯一 full）；未运行真实 Herdr、真实 Typesafe API、真实计费验证。假件通过不代表真实宿主验收。

## 冻结差异

`git diff --stat`（tracked）：

```text
 bin/qwb-dispatch.sh  | 55 +++++++++++++++++++++++++++++++++++++---------------
 bin/qwb-run.sh       | 26 +++++++++++++++++++------
 templates/QWBUDDY.md |  2 +-
 tests/smoke.sh       |  1 +
 4 files changed, 61 insertions(+), 23 deletions(-)
```

未跟踪新文件 `tests/optional-routing.sh` SHA-256：`494679707d11d5d64eba294b0618bce187552373f89296de1754741e6b0be25a`。

完整 tracked diff 如下（基线到当前工作区，未包含新文件正文）：

```diff
diff --git a/bin/qwb-dispatch.sh b/bin/qwb-dispatch.sh
index 0168257..420b523 100644
--- a/bin/qwb-dispatch.sh
+++ b/bin/qwb-dispatch.sh
@@ -7,13 +7,13 @@
 # floor、spendPriority、captain 审批流——qwb 派工只是"选一个工人"）。
 #
 # 用法:
-#   qwb-dispatch.sh <brief文件> [--project <项目根>]
+#   qwb-dispatch.sh <brief文件> [--project <项目根>] [--json]
 #     <brief文件>   任务简报（通常就是任务书路径；全文作为 state.task.brief 发给模型）
 #     --project     项目根（默认当前目录）：规则在 <项目根>/qwbuddy/dispatch-rules.json，
 #                   key 可在 <项目根>/.env；state.task.project 用项目根的目录名
 #
 # 开关（opt-in）：TYPESAFE_API_KEY 取进程环境变量，否则读 <项目根>/.env（环境变量优先）；
-#   两处都无 → stderr 一行 "qwb-dispatch: off"，exit 0，零网络调用，行为与没有本工具完全一致。
+#   两处都无 → stderr 一行 "qwb-dispatch: off"，exit 0，零网络调用。
 #   key 纪律（照抄上游）：key 只存一个 shell 变量、经文件描述符 `3< <(...)` 传给 curl 的
 #   Authorization 头、启动任何子进程前 unset TYPESAFE_API_KEY；不打印、不落日志、不落盘。
 # 规则文件：<项目根>/qwbuddy/dispatch-rules.json（模板：QW buddy 母本仓 templates/dispatch-rules.json）。
@@ -65,15 +65,21 @@ no_rules() {
 }
 emit_error() {
   echo "qwb-dispatch: error（$1）" >&2
+  if [ "$JSON_MODE" -eq 1 ]; then
+    jq -cn --arg reason "$1" --arg default "$DEFAULT_WORKER" \
+      '{status:"error",reason:$reason,default_worker:$default}'
+    exit 0
+  fi
   printf 'qwb-dispatch:\n  status: error\n  reason: %s\n' "$1"
   exit 0
 }
 now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time()*1000'; }
 
-BRIEF='' PROJECT_ROOT=''
+BRIEF='' PROJECT_ROOT='' JSON_MODE=0
 while [ $# -gt 0 ]; do
   case "$1" in
     --project) [ $# -ge 2 ] || die "--project 需要一个值"; PROJECT_ROOT=$2; shift 2 ;;
+    --json) JSON_MODE=1; shift ;;
     -h|--help) usage; exit 0 ;;
     -*) die "未知参数 $1" ;;
     *) [ -z "$BRIEF" ] || die "brief 文件只能给一个"; BRIEF=$1; shift ;;
@@ -86,18 +92,15 @@ done
 PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd)
 RULES_PATH="${PROJECT_ROOT}/qwbuddy/dispatch-rules.json"
 
-# ---- 开关门（opt-in）：环境变量优先，其次 <项目根>/.env；都无 → off，零网络调用 ----
-if [ -z "$TYPESAFE_API_KEY_PRIVATE" ]; then
-  TYPESAFE_API_KEY_PRIVATE=$(env_get TYPESAFE_API_KEY "${PROJECT_ROOT}/.env")
-fi
-if [ -z "$TYPESAFE_API_KEY_PRIVATE" ]; then
-  echo "qwb-dispatch: off（环境变量与 ${PROJECT_ROOT}/.env 都没有 TYPESAFE_API_KEY）" >&2
-  exit 0
-fi
-
-# ---- 输入与规则 ----
-[ -r "$BRIEF" ] || die "brief 文件不可读: ${BRIEF}"
-[ -e "$RULES_PATH" ] || [ -L "$RULES_PATH" ] || no_rules
+# ---- 输入与规则：先验证快照，坏规则不能被无 key 开关绕过 ----
+[ -e "$RULES_PATH" ] || [ -L "$RULES_PATH" ] || {
+  if [ "$JSON_MODE" -eq 1 ]; then
+    echo "qwb-dispatch: no rules（${RULES_PATH} 不存在）" >&2
+    printf '%s\n' '{"status":"off","default_worker":"pi"}'
+    exit 0
+  fi
+  no_rules
+}
 [ -r "$RULES_PATH" ] || die "规则文件不可读: ${RULES_PATH}"
 command -v jq >/dev/null 2>&1 || die "需要 jq"
 RULES=$(mktemp) || die "mktemp 失败"
@@ -120,6 +123,20 @@ rules_err=$(jq -r '
   else empty end
 ' "$RULES" 2>/dev/null) || die "规则文件不是合法 JSON: ${RULES_PATH}"
 [ -z "$rules_err" ] || die "规则文件不合 schema: ${RULES_PATH} - ${rules_err}"
+DEFAULT_WORKER=$(jq -r '.default.worker' "$RULES") || die "读取默认工人失败"
+
+# ---- 开关门（opt-in）：环境变量优先，其次 <项目根>/.env；都无 → off，零网络调用 ----
+if [ -z "$TYPESAFE_API_KEY_PRIVATE" ]; then
+  TYPESAFE_API_KEY_PRIVATE=$(env_get TYPESAFE_API_KEY "${PROJECT_ROOT}/.env")
+fi
+if [ -z "$TYPESAFE_API_KEY_PRIVATE" ]; then
+  echo "qwb-dispatch: off（环境变量与 ${PROJECT_ROOT}/.env 都没有 TYPESAFE_API_KEY）" >&2
+  if [ "$JSON_MODE" -eq 1 ]; then
+    jq -cn --arg default "$DEFAULT_WORKER" '{status:"off",default_worker:$default}'
+  fi
+  exit 0
+fi
+[ -r "$BRIEF" ] || die "brief 文件不可读: ${BRIEF}"
 
 # ---- 请求：与上游同形。state 只带 project 名 + brief 全文；一个 choice 问题，
 # 选项 = 每条规则的 when + 固定 default 选项。模型看不到 worker 名。 ----
@@ -191,7 +208,13 @@ RESULT=$(jq -n --arg floor "$CONFIDENCE_FLOOR" --argjson lat "$LAT_MS" --arg non
     $ev + {status: "clear", worker: $rule.worker, note: "规则命中"}
   end') || emit_error "解析失败"
 
-# ---- 输出（TOON 风格）：动态字段全部压平换行/制表符，防止注入伪行 ----
+# ---- 输出：机器模式只输出单个 JSON 对象；展示模式保持原有文本 ----
+if [ "$JSON_MODE" -eq 1 ]; then
+  jq -cn --argjson result "$RESULT" --arg default "$DEFAULT_WORKER" \
+    '$result + {default_worker:$default}' || die "JSON 输出失败"
+  exit 0
+fi
+# 动态字段全部压平换行/制表符，防止注入伪行。
 TEXT=$(jq -r '
   def flat: tostring | gsub("[\t\r\n]"; " ");
   def show($v): ($v // "-") | flat;
diff --git a/bin/qwb-run.sh b/bin/qwb-run.sh
index 68370b0..19fd979 100755
--- a/bin/qwb-run.sh
+++ b/bin/qwb-run.sh
@@ -155,20 +155,34 @@ if [[ "$WORKER" == "auto" ]]; then
   [[ -f "$DISPATCH_BIN" ]] || { echo "错误：找不到 ${DISPATCH_BIN}——安装副本不完整，请用母本仓重跑 bin/qwb-init.sh 更新" >&2; exit 1; }
   DP_ERR="$(mktemp)"
   DP_RC=0
-  DP_OUT="$(bash "$DISPATCH_BIN" "$TASK_FILE" --project "$PROJECT_ROOT" 2>"$DP_ERR")" || DP_RC=$?
+  DP_OUT="$(bash "$DISPATCH_BIN" "$TASK_FILE" --project "$PROJECT_ROOT" --json 2>"$DP_ERR")" || DP_RC=$?
   if [[ "$DP_RC" -ne 0 ]]; then
     cat "$DP_ERR" >&2; rm -f "$DP_ERR"
     echo "错误：auto 派工配置错误（qwb-dispatch 退出码 ${DP_RC}）——修好 qwbuddy/dispatch-rules.json 后重派；本次派发未发生、无副作用。" >&2
     exit "$DP_RC"
   fi
-  DP_STATUS="$(printf '%s\n' "$DP_OUT" | sed -n 's/^  status: //p' | head -1)"
+  # JSON 是唯一机器契约。必须是单个对象，字段与状态匹配；诊断文字不参与选择。
+  if ! printf '%s\n' "$DP_OUT" | jq -s -e '
+    length == 1 and (.[0] |
+    type == "object" and
+    (.status == "clear" or .status == "off" or .status == "error" or .status == "ambiguous") and
+    (.default_worker | type == "string" and test("^[^[:space:][:cntrl:]]+$")) and
+    ((has("reason") | not) or (.reason | type == "string")) and
+    (if .status == "clear" then
+      (.worker | type == "string" and test("^[^[:space:][:cntrl:]]+$"))
+     else (has("worker") | not) end))
+  ' >/dev/null 2>&1; then
+    cat "$DP_ERR" >&2; rm -f "$DP_ERR"
+    echo "错误：auto 派工结构化结果非法，拒绝派发（无副作用）" >&2
+    exit 2
+  fi
+  DP_STATUS="$(jq -r '.status' <<<"$DP_OUT")"
   if [[ "$DP_STATUS" == "clear" ]]; then
-    WORKER="$(printf '%s\n' "$DP_OUT" | sed -n 's/^  worker: //p' | head -1)"
+    WORKER="$(jq -r '.worker' <<<"$DP_OUT")"
     echo "qwb-run: auto 派工命中 → ${WORKER}" >&2
   else
-    WORKER="$(jq -r '.default.worker // empty' "$PROJECT_ROOT/qwbuddy/dispatch-rules.json" 2>/dev/null || true)"
-    [[ -n "$WORKER" ]] || WORKER="pi"
-    DP_REASON="$(printf '%s\n' "$DP_OUT" | sed -n 's/^  reason: //p' | head -1)"
+    WORKER="$(jq -r '.default_worker' <<<"$DP_OUT")"
+    DP_REASON="$(jq -r '.reason // empty' <<<"$DP_OUT")"
     { cat "$DP_ERR"; echo "qwb-run: auto 派工未命中（status=${DP_STATUS}${DP_REASON:+，${DP_REASON}}），按默认工人 ${WORKER} 继续派发"; } >&2
   fi
   rm -f "$DP_ERR"
diff --git a/templates/QWBUDDY.md b/templates/QWBUDDY.md
index 966f729..af72102 100644
--- a/templates/QWBUDDY.md
+++ b/templates/QWBUDDY.md
@@ -139,7 +139,7 @@ CI 是交付门禁，不是性能实验场：让每次 push 在最短的可信
 |---|---|
 | `qwb-init.sh <项目根>` | **母本仓专用**安装器（不装进 `qwbuddy/bin/`）：从母本仓用绝对路径运行 `bash <母本仓>/bin/qwb-init.sh <项目根>`，幂等 |
 | `qwb-run.sh --task <id> --worker <名>` | 派发 + 记账（先过验收场景门；默认开 `.worktrees/<任务id>` 隔离副本，`--here` 才落项目根；启动方式由 `workers.sh` 逐工人声明；新 tab 的 workspace 按下一行解析） |
-| `qwb-dispatch.sh <brief> [--project <根>]` | JEV 自动派工（opt-in：TYPESAFE_API_KEY 取环境变量或 <项目>/.env）：用 typesafe.ai jev-latest 从 qwbuddy/dispatch-rules.json（模板在母本仓 templates/，qwb-init.sh 安装时拷入）选规则出工人；confidence < 0.6 → ambiguous、坏规则文件 exit 2、其余一律 exit 0；qwb-run.sh `--worker auto` 自动调用，off/error/ambiguous 落默认工人不阻塞派发 |
+| `qwb-dispatch.sh <brief> [--project <根>] [--json]` | JEV 自动派工（opt-in：TYPESAFE_API_KEY 取环境变量或 <项目>/.env）：用 typesafe.ai jev-latest 从 qwbuddy/dispatch-rules.json（模板在母本仓 templates/，qwb-init.sh 安装时拷入）选规则出工人；默认输出供人阅读，`--json` 输出单个机器对象（status、default_worker，clear 时含 worker）；confidence < 0.6 → ambiguous、坏规则文件 exit 2（无 key 也拒绝）、其余一律 exit 0；qwb-run.sh `--worker auto` 只读结构化字段，off/error/ambiguous 落已校验快照中的默认工人不阻塞派发 |
 | `qwb-lib.sh` | **库文件，不直接运行**：被 `qwb-run.sh` / `qwb-wake.sh` source。`resolve_workspace` 解析工人/值守 tab 该落哪个 herdr workspace（`QWB_WORKSPACE` → `worktree.repo_root` 匹配项目根 → 调用者 workspace + 警告 三级） |
 | `qwb-wake.sh [--dry-run|--once|--ensure|--check|--block]` | 值守：查未结项 → 一轮只发**一条**投递（多票拼同一条文本，含各票 state 与最后状态行）→ 叫醒你的 pane；`QWB_REWAKE_MS` 时间兑底只对 `running` 票生效（blocked/needs-decision 等裁决，不重叫）；`--block` 每轮先复核主控锁，锁不在手（孤儿值守）不消费唤醒；`--ensure` 仅供历史 tab 手工排障，`--check` 只报值守健康；`--block [--max-ms <毫秒>]` 前台阻塞值守（无窗口，给 Claude Code Stop hook / Codex 前台 checkpoint 用）：有可动作变化退出码 2 + stdout 摘要、到期无变化 124、退出码 0 按 §1 核对输出/锁/账本后判定 |
 | `qwb-hook-claude-stop.sh` | Claude Code Stop hook 入口（由 `qwb-init.sh` 合并进 `.claude/settings.json`，主控不手动跑）：守卫（仅主控锁 pane）→ `.hook.lock` 单飞 → 前台跑 `qwb-wake.sh --block`；exit 2 时摘要双写 stdout/stderr 唤醒主控，出错写 `.hook.err` 后 exit 0 不卡主控 |
diff --git a/tests/smoke.sh b/tests/smoke.sh
index 12a3ad0..2d47c39 100755
--- a/tests/smoke.sh
+++ b/tests/smoke.sh
@@ -2303,6 +2303,7 @@ out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
 sed -i '' '/^QWB_WORKSPACE=/d' "$ENSP/qwbuddy/config.sh"
 
 echo "== 49. JEV 自动派工（qwb-dispatch.sh：off/clear/ambiguous/坏规则/响应校验/key 纪律 + qwb-run auto 集成）=="
+bash "$ROOT/tests/optional-routing.sh" && ok "可选路由公开 CLI 结构化契约" || bad "可选路由公开 CLI 结构化契约"
 # 假 curl 手法沿 firstmate tests/fm-dispatch-resolve.test.sh：记录 argv/请求体/fd3 头/子进程环境，
 # 按 FAKE_CURL_* 应答。零网络、零真 key。
 DT="$(mktemp -d)"

```

## r2：独立审核 r1 的唯一 AMEND 返修（2026-09-22）

审核来源：`docs/reviews/2026-09-22-qwb-simplify-optional-routing-r1.md`。r1 指出空规则文件或连续两个有效 JSON 对象在无 key 时被误判为 off。本轮仅修改 `bin/qwb-dispatch.sh` 的规则快照校验和 `tests/optional-routing.sh` 的对应反例；其余接口与行为未改。

- red：新增反例后运行 `bash tests/optional-routing.sh`，exit 1，明确输出 `FAIL empty direct CLI: expected exit 2, got 0`。r1 已独立复现双对象同样 exit 0。
- green：在原 schema 校验前用 `jq -s` 解析并要求输入数恰为 1；无效 JSON 仍报原来的「不是合法 JSON」，单对象仍由原 schema 校验顶层对象及字段。
- `bash tests/optional-routing.sh`：exit 0，19 项 PASS。空文件与两个有效对象串接分别在无 key 下直接 CLI exit 2、stderr 明确指出规则文件错误、stdout 为空、curl 调用数 0。相应上层 auto 用默认 worktree 模式验证 exit 2，任务书 shasum 前后相同、无 Herdr 调用、无 `.worktrees` 创建、curl 调用数 0。
- `bash bin/qwb-test.sh fast`：exit 0；`git diff --check`、`shellcheck bin/qwb-dispatch.sh tests/optional-routing.sh`、`bash -n bin/qwb-dispatch.sh tests/optional-routing.sh`：均 exit 0。
- 主控初轮 `full` exit 0、耗时 120.151 秒的收据只绑定 r1 旧候选；本 r2 候选未运行 full，也未运行真实 Herdr/Typesafe API。

r2 最终源码仍基于 HEAD `e74a7edaa62303a49c99c272ca2e6fd26436659b`，未提交。最终 tracked diff 范围及摘要：

```text
 bin/qwb-dispatch.sh  | 57 +++++++++++++++++++++++++++++++++++++---------------
 bin/qwb-run.sh       | 26 ++++++++++++++++++------
 templates/QWBUDDY.md |  2 +-
 tests/smoke.sh       |  1 +
 4 files changed, 63 insertions(+), 23 deletions(-)
```

`git diff -- bin/qwb-dispatch.sh bin/qwb-run.sh templates/QWBUDDY.md tests/smoke.sh | shasum -a 256`：`346b86073418cb4afb8a6f5d60dda3e95836988752990fbc32037c56e1c70864`。未跟踪 `tests/optional-routing.sh` SHA-256：`e3656f8a5c7bd789f4752c4d3995ad3190110fdae6a83a2656322290d8743463`。上文 r1 冻结差异与 hash 仅代表旧候选，本节数值代表最终 r2 候选。
