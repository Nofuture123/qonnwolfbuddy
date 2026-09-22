// QW buddy 值守扩展（Pi 主控）：持有 `qwb-wake.sh --block` 阻塞子进程，子进程 exit 2 时把
// stdout 摘要以 follow-up 用户消息注入会话叫醒主控。子进程由本 pi 进程 spawn、随 pi 死——
// 不是守护进程。安装：qwb-init.sh 装到 <项目>/.pi/extensions/qwb-watch.ts，重启 pi 或 /reload 生效。
//
// 行为规格（tasks/2026-09-16-watch-invisible-pi.md §0，退出码契约见 docs/DECISIONS.md 二十九）：
//   session_start：主控锁在手（qwbuddy/.controller.lock/owner 末字段 == 本进程 HERDR_PANE_ID）
//     → spawn `bash qwbuddy/bin/qwb-wake.sh --block`（无 --max-ms，无限阻塞），并登记
//     qwbuddy/.watch（kind=pi-ext pid=<子进程 pid>）。非锁主 → 不动（非主控的 pi 会话不值守）。
//   exit 2 → stdout 摘要以 `[qwb-wake] …` sendUserMessage(deliverAs:"followUp") 注入，立即重启下一轮。
//   exit 0 → 不注入不重启，清 .watch；下次 turn_end 用 `--block --max-ms 1` 探测
//     （0 = 账本无未结项 / 124 = 有未结项），有未结项即重新值守——判定复用 qwb-wake.sh，不另写账本解析。
//   其他退出码 → 记 qwbuddy/.pi-watch.err，指数退避重启（上限 QWB_WAKE_INTERVAL_MS × 8），
//     退避到顶注入一次 `[qwb-wake] 值守故障：…`——这是叫醒主控去修，不是通知使用者。
//   单飞：扩展内只持一个子进程；session_start 重复触发（/new、/resume、reload）先杀旧再起新。
//   session_shutdown 与 pi 进程退出 → 杀子进程（spawn 不 detach）。
import { spawn } from "node:child_process";
import { appendFileSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// —— 可注入核心：子进程管理与消息拼装不依赖 pi 进程，供 tests/pi-ext.test.mjs 直接测 ——

// 方法语法（非属性箭头）保持双变兼容：ChildProcess 的 stdout/stderr/on 可直接赋给本接口。
export interface WatchTextStream {
  setEncoding(enc: string): unknown;
  on(ev: "data", cb: (chunk: string) => void): unknown;
}

export interface WatchChildLike {
  pid?: number;
  kill(): unknown;
  stdout: WatchTextStream | null;
  stderr: WatchTextStream | null;
  on(ev: "exit", cb: (code: number | null, signal: string | null) => void): unknown;
  on(ev: "error", cb: (err: Error) => void): unknown;
}

export type SpawnFn = (
  cmd: string,
  args: string[],
  opts: { cwd: string; env: NodeJS.ProcessEnv },
) => WatchChildLike;

export interface WatchCoreDeps {
  root: string; // 项目根（qwbuddy/ 的父目录）
  paneId: string | undefined; // 本进程 HERDR_PANE_ID
  intervalMs: number; // QWB_WAKE_INTERVAL_MS（退避基数）
  spawnChild: SpawnFn;
  sendMessage: (text: string) => unknown; // pi.sendUserMessage 适配
  schedule: (ms: number, fn: () => void) => { cancel(): void };
  readLockOwner: (root: string) => string | null;
  writeWatch: (root: string, pid: number | undefined, cmd: string) => void;
  clearWatch: (root: string) => void;
  appendErr: (root: string, line: string) => void;
  nowIso?: () => string;
}

export const WAKE_PREFIX = "[qwb-wake]";

export function createWatchCore(d: WatchCoreDeps) {
  const wakeBin = resolve(d.root, "qwbuddy", "bin", "qwb-wake.sh");
  const cap = Math.max(d.intervalMs * 8, 1); // 退避上限：interval × 8
  let child: WatchChildLike | null = null;
  let childIsProbe = false;
  let restartTimer: { cancel(): void } | null = null;
  let failures = 0;
  let warned = false; // 退避到顶告警只发一次
  let idleAfterZero = false; // exit 0 后闲置，等 turn_end 探测
  let generation = 0; // 会话代际：被单飞替换的旧子进程的 exit 回调不作数

  function ownsLock(): boolean {
    if (!d.paneId) return false;
    return d.readLockOwner(d.root) === d.paneId;
  }

  function killChild() {
    if (!child) return;
    try {
      child.kill();
    } catch {
      // 已死的子进程 kill 报错无所谓
    }
    child = null;
  }

  function startChild(args: string[], isProbe: boolean, onStdout?: (text: string) => void) {
    killChild(); // 单飞：起新的先杀旧的（session_start 重复触发）
    generation += 1;
    const gen = generation;
    idleAfterZero = false;
    let out = "";
    const c = d.spawnChild("bash", [wakeBin, ...args], { cwd: d.root, env: process.env });
    child = c;
    childIsProbe = isProbe;
    if (!isProbe) {
      d.writeWatch(d.root, c.pid, `bash ${wakeBin} ${args.join(" ")}`.trim());
    }
    c.stdout?.setEncoding("utf8");
    c.stdout?.on("data", (chunk: string) => {
      out += chunk;
    });
    c.stderr?.setEncoding("utf8");
    c.stderr?.on("data", () => {
      // stderr 目前只进 .pi-watch.err 的场景不截取内容，保持丢弃
    });
    c.on("exit", (code) => {
      if (gen !== generation || child !== c) return; // 已被单飞替换 / shutdown 杀掉
      child = null;
      onExit(code == null ? -1 : code, isProbe, out);
    });
    c.on("error", (err) => {
      if (gen !== generation) return; // 旧子进程的迟来 error
      // ENOENT 等同步类失败：exit 事件可能不来，这里按故障退避处理
      if (child === c) {
        child = null;
      }
      fail(-1, `spawn 失败：${err?.message ?? err}`);
    });
    if (onStdout) onStdout(out);
  }

  function startBlock() {
    startChild(["--block"], false);
  }

  function fail(code: number, note?: string) {
    failures += 1;
    const ts = d.nowIso ? d.nowIso() : new Date().toISOString();
    d.appendErr(d.root, `${ts} exit=${code} 连续失败 ${failures} 次${note ? ` ${note}` : ""}`);
    const raw = d.intervalMs * 2 ** (failures - 1);
    const delay = Math.min(raw, cap);
    if (raw >= cap && !warned) {
      warned = true; // 退避到顶：叫醒主控去修（恰一次）
      try {
        Promise.resolve(
          d.sendMessage(
            `${WAKE_PREFIX} 值守故障：qwb-wake.sh 连续 ${failures} 次异常退出（最近 exit=${code}），` +
              `重启退避已达上限 ${cap}ms，请查 qwbuddy/.pi-watch.err`,
          ),
        ).catch(() => {
          d.appendErr(d.root, `${ts} 告警注入失败`);
        });
      } catch {
        d.appendErr(d.root, `${ts} 告警注入失败`);
      }
    }
    restartTimer = d.schedule(delay, () => {
      restartTimer = null;
      startBlock();
    });
  }

  function onExit(code: number, wasProbe: boolean, out: string) {
    if (code === 2) {
      failures = 0;
      warned = false;
      const summary = out.trim() || "（空摘要）";
      try {
        Promise.resolve(d.sendMessage(`${WAKE_PREFIX} ${summary}`)).catch(() => {
          d.appendErr(d.root, `exit=2 摘要注入失败`);
        });
      } catch {
        d.appendErr(d.root, `exit=2 摘要注入失败`);
      }
      startBlock(); // 立即重启下一轮
      return;
    }
    if (wasProbe) {
      // turn_end 探测：2 已按普通唤醒处理；0 = 无未结项；124 = 有未结项。
      if (code === 124) startBlock();
      else if (code === 0) idleAfterZero = true;
      else fail(code);
      return;
    }
    if (code === 0) {
      // 账本无未结项：不注入不重启，清登记；turn_end 时再探测
      d.clearWatch(d.root);
      idleAfterZero = true;
      return;
    }
    fail(code);
  }

  return {
    onSessionStart() {
      if (!ownsLock()) return; // 非锁主：不动
      startBlock();
    },
    onTurnEnd() {
      if (child || restartTimer) return; // 值守在跑或退避等待中：不动
      if (!idleAfterZero) return; // 只有 exit-0 闲置态才探测
      if (!ownsLock()) {
        idleAfterZero = false;
        return;
      }
      startChild(["--block", "--max-ms", "1"], true);
    },
    shutdown() {
      generation += 1; // 迟来的 exit 回调全部作废
      if (restartTimer) {
        restartTimer.cancel();
        restartTimer = null;
      }
      killChild();
      idleAfterZero = false;
      childIsProbe = false;
    },
    // 测试观察用
    get child() {
      return child;
    },
    get childIsProbe() {
      return childIsProbe;
    },
    get failures() {
      return failures;
    },
  };
}

// —— 默认实现（真机路径）——

function readLockOwnerDefault(root: string): string | null {
  try {
    const raw = readFileSync(resolve(root, "qwbuddy", ".controller.lock", "owner"), "utf8");
    const line = raw.split("\n")[0] ?? "";
    const i = line.indexOf(" ");
    return i < 0 ? line : line.slice(i + 1);
  } catch {
    return null;
  }
}

// QWB_WAKE_INTERVAL_MS 取值序：环境变量 > qwbuddy/config.sh > 120000（与 qwb-wake.sh 缺省一致）。
// config.sh 是 bash 文件，这里只做一行赋值的最小解析，只用于退避基数，不参与值守判定。
function readIntervalMs(root: string): number {
  const fromEnv = Number(process.env.QWB_WAKE_INTERVAL_MS);
  if (Number.isInteger(fromEnv) && fromEnv > 0) return fromEnv;
  try {
    const conf = readFileSync(resolve(root, "qwbuddy", "config.sh"), "utf8");
    const m = conf.match(/^\s*(?:export\s+)?QWB_WAKE_INTERVAL_MS=["']?([0-9]+)/m);
    if (m && Number(m[1]) > 0) return Number(m[1]);
  } catch {
    // 无 config.sh：用缺省
  }
  return 120000;
}

export default function (pi: ExtensionAPI) {
  const root = process.cwd();
  const core = createWatchCore({
    root,
    paneId: process.env.HERDR_PANE_ID,
    intervalMs: readIntervalMs(root),
    spawnChild: (cmd, args, opts) => spawn(cmd, args, { ...opts, stdio: ["ignore", "pipe", "pipe"] }),
    sendMessage: (text) => pi.sendUserMessage(text, { deliverAs: "followUp" }),
    schedule: (ms, fn) => {
      const t = setTimeout(fn, ms);
      return { cancel: () => clearTimeout(t) };
    },
    readLockOwner: readLockOwnerDefault,
    writeWatch: (r, pid, cmd) => {
      writeFileSync(
        resolve(r, "qwbuddy", ".watch"),
        `kind=pi-ext pid=${pid ?? 0} started=${new Date().toISOString()} cmd=${cmd}\n`,
      );
    },
    clearWatch: (r) => {
      rmSync(resolve(r, "qwbuddy", ".watch"), { force: true });
    },
    appendErr: (r, line) => {
      appendFileSync(resolve(r, "qwbuddy", ".pi-watch.err"), `${line}\n`);
    },
  });

  pi.on("session_start", async () => {
    core.onSessionStart();
  });
  pi.on("session_shutdown", async () => {
    core.shutdown();
  });
  pi.on("turn_end", async () => {
    core.onTurnEnd();
  });
  // pi 进程退出保底：session_shutdown 覆盖常规路径，这里兜住 SIGKILL 之外的直接退出
  process.once("exit", () => {
    core.shutdown();
  });
}
