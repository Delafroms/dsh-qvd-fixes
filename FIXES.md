# 修复改动清单（QVD）

> 定位：本补丁是**针对 0.1.2-alpha.2 的社区补丁**——4 个漏洞（52631 / 52632 / 52644 / 52646）有源码修改；57410 为该基线内已有修复的版本核验，未做改动。非官方安全更新，也非完整安全审计。
>
> **另有针对 0.1.5-rc.2 的补充补丁**（`qvd-2026-57410-transport-fence.patch`、`qvd-2026-52632-editor-read-fence.patch`、`qvd-2026-52632-plugin-fs-fence.patch`、`qvd-2026-52646-confined-spawn-fail-closed.patch`、`guard-repeat-text-reminder.patch`），见文末[「0.1.5-rc.2 补充补丁」](#015-rc2-补充补丁2026-09-18)。
> **2026-09-23：这 5 个分项补丁已并入 `fixes-0.1.5-rc.2.patch` 并从仓库移除**，下文的逐项说明保留作审计记录。
>
> **🆕 2026-09-23 更新：新增 `fixes-0.1.5-rc.2.patch`（0.1.5-rc.2 一键补丁）。**
> 它把基线 + 5 个补充补丁的最终效果合并成**单一自洽 diff**（48 文件，+2114 / −74），在干净 0.1.5-rc.2 上 `git apply --check` 通过。
> **0.1.5-rc.2 用户请优先用它**，不要再走「基线 → 补充补丁」的分步流程。
> 同时，**5 个分项补丁已并入该单一补丁并从仓库移除**；下文对它们的设计说明保留作审计记录（内容无丢失）。
>
> **⚠️ 2026-09-23 更正：`fixes.patch` 在干净的 0.1.5-rc.2 上打不上。**
> 实测 5 个文件报 `patch does not apply`（`fs/fs/src/index.ts`、`tool-fs/src/read.ts`、`tool-fs/src/read-image.ts`、`subprocess-local/src/spawn.ts` 及其测试）。
> 原因是 0.1.2 → 0.1.5 上游改了这些文件；**不是行尾问题**（`--ignore-whitespace`、`-C1` 均无效）。此前「在 0.1.5-rc.2 上必须按序应用基线 → 补充补丁」的说明与事实不符。
>
> **⚠️ 两组补丁目标版本不同，不能互相替代，也不能合并。**
> `fixes.patch` 相对 **0.1.2-alpha.2** 生成；补充补丁针对 **0.1.5-rc.2**。把 0.1.5 的内容并进 `fixes.patch` 会让它在 0.1.2 上应用不了。
> 在 0.1.5-rc.2 上必须**按序应用：基线 → 补充补丁**。原因是基线里的 `assertConfinedUnderPolicy` 是**带 fail-open 缺陷的旧版本**（`mode !== undefined` 前置条件让 `sandboxPolicy: {}` 静默放行），补充补丁 4 才会把它覆盖为 fail-closed。

> **🆕 2026-09-26 更新：新增 `fixes-0.1.7-rc.2.patch`（0.1.7-rc.2 一键补丁），本文档新增文末[「0.1.7-rc.2 轮次（2026-09-26）」](#017-rc2-轮次2026-09-26)一节。**
> 本轮在 0.1.7-rc.2 检出上落实 7 项修复（搜索根栅栏 / 凭据不可读 / `run_code` 逃逸封堵 / `/api/file` 根白名单 / `/api/session.export` 鉴权 / `/plugins` 与 `/plugins/events` 信任围栏 / duplicate Host 结构化拒绝），并**逐条列出 8 条残留**（未修就是未修）。
> 0.1.5-rc.2 与 0.1.2-alpha.2 的说明保持原样，不受影响。

本清单与 `fixes.patch` 配套：`fixes.patch` 是相对 DeepSeek Harness **0.1.2-alpha.2**（修复前基线）的统一 diff，可对任意基于该版本的检出执行：

```bat
git apply --check fixes.patch   rem 校验（不实际应用）
git apply fixes.patch           rem 应用
```

> `git apply` 会修改 DSH 源码——若你只想先核对，请用 `--check`；应用前建议备份或先 `git stash`。
>
> 补丁以 LF 行尾生成。Windows 下若本机检出使用 CRLF（`core.autocrlf=true`）导致 `does not apply`，请改用 `git apply --ignore-whitespace fixes.patch` 重试。

## 改动概览

**15 个文件，+668 / −44 行**（0.1.2-alpha.2 基线补丁的规模；0.1.7-rc.2 轮次的规模见文末对应章节）。

| QVD | 类别 | 涉及文件 |
|---|---|---|
| QVD-2026-52631 | loader `!!js` 配置表达式注入 → `node:vm` 隔离求值 | `vendor/loader/src/config/utils.ts`；登记 `vendor/README.md` |
| QVD-2026-52632 | fs-sandbox 读逃逸 → 读方法执行点策略校验 | `packages/fs/fs-sandbox/src/index.ts`、`packages/fs/fs/src/index.ts`、`packages/fs/tool-fs/src/{index,read,read-image}.ts` + 测试 |
| QVD-2026-52644 | cordis 沙箱工具逃逸 → 白名单执行视图 | `packages/extensions/cordis-host-runner/src/guard.ts` + 测试 |
| QVD-2026-52646 | bash/pwsh 子进程逃逸 → 受限策略强制 `argvConfined` | `packages/subprocess/subprocess/src/types.ts`、`packages/subprocess/subprocess-local/src/spawn.ts`、`packages/shell/bash-local/src/index.ts`、`packages/shell/pwsh-local/src/index.ts` + 测试 |
| QVD-2026-57410 | 未授权访问 / 伪造 Host → **上游已内建** browser-token 鉴权（审计确认，无改动） | 无（在 0.1.2-alpha.2 中已由上游提交修复） |

## 逐项说明

### QVD-2026-52631 — loader 配置表达式注入
- 原实现用宿主 `with (ctx) { eval(expr) }` 包裹的 `new Function` 求值，表达式可从 `ctx` 落到**宿主全局作用域**，读取 `process`/`require`/`module` 等，进而读写文件、执行命令。
- 修复：改为 `node:vm` 隔离求值。上下文数据以单个 JSON 字符串注入，在 vm 内重建（宿主对象零注入）；`process` 仅暴露 `env/platform/arch/version/execPath/cwd` 与 `getBuiltinModule('node:url')`；`dshHomePath`/`URL`/`fileURLToPath` 在 vm 内按纯数据实现；`runInContext(..., { timeout: 1000 })` 限制运行时长。
- `projectContext` 改为收集原型链 value descriptor + 根 fiber store + registry 整树 fibers store，并给 vm 数据视图提供 `ctx.get(name)`，保证既有 `user-patches` 语义回归通过。

### QVD-2026-52632 — fs-sandbox 读逃逸
- `fs-sandbox` 的 `readText`/`streamText`/`readBytes` 增加可选 `sandboxPolicy` 参数，经 `checkedReadTarget` 校验目标：read-only 只允许 workspaceRoot，workspace-write 使用 writableRoots，越界抛结构化 `FS_SANDBOX_DENIED`。
- `tool-fs` 的 `FsSandboxController` 在读前解析会话策略并传入 fs 读方法，denial 经 `sandbox.mapError` 映射；无策略时透传（不影响宿主自有读取）。
- **已知残留（本补丁未覆盖）**：进程级沙箱后端在 read-only 模式下仍把整个宿主文件系统只读暴露给受限 shell 子进程——bwrap 用 `--ro-bind / /`、landlock 用 `readOnly: ['/']`、seatbelt 为 allow-default（默认允许读）。即受限 bash/pwsh 仍可能读取 `~/.ssh`、`.env` 等敏感文件。详见文末「已知残留与限制」。
- **2026-09-26 轮次补充（0.1.7-rc.2）**：① **搜索根栅栏** —— `grep` / `glob` 此前用 `ctx.subprocess.spawn` 裸跑 ripgrep、**不传策略**，一次 `grep` 就能读到 `read` 拒绝的内容；新增 `SearchSandboxFence`（`packages/fs/tool-fs-search/src/search-sandbox.ts`）在 **spawn 之前**做策略与根比对，拒绝文本与 `read` 完全一致。② **凭据不可读** —— 判据上移到 `packages/fs/fs/src/index.ts` 导出的 `isProtectedReadPath`，fs-sandbox 与搜索栅栏共用：`$DSH_HOME/.credentials*` 在**任何模式（含 `danger-full-access`）**都被拒（`FS_PERMISSION_DENIED`）；宿主侧读凭据走 `fs-local`，不受影响。
- **已知残留 2（2026-09-26 新增）**：`read` / `glob` / `grep` 的拒绝提示提到 `sandbox_permissions`，但这三个工具的**工具 schema 没有该字段** —— 读侧「放宽一次」的审批入口缺失，提示语与可操作面不一致。

### QVD-2026-52644 — cordis 沙箱工具逃逸
- 新增 `sandboxToolExec(exec)`：向外提供**白名单化**执行视图，仅含 `name` / `callId` / `arguments`（JSON clone）/ `signal`，不含 agent 或真实宿主对象。
- `sandboxDefineTool` 的模型可写 `execute` 改为 `rawExecute(args, sandboxToolExec(exec))` 调用。

### QVD-2026-52646 — bash/pwsh 子进程逃逸
- `SubprocessSpawnSpec` 增加可选 `sandboxPolicy` 与 `argvConfined`。
- `subprocess-local` 新增 `assertConfinedUnderPolicy(spec)`：受限 policy 且非 `argvConfined` → 抛错拒绝，`spawnSubprocess` 入口调用。
- `bash-local` / `pwsh-local` 在受限 policy 下 stamp `{ sandboxPolicy, argvConfined: true }`。

### QVD-2026-57410 — 未授权访问 / 伪造 Host（版本核验，非本仓库修复）
- 审计结论：本树版本（`0.1.2-alpha.2`）已含上游 browser-token 会话鉴权（`packages/client/connection/src/browser-auth.ts`、`rpc-host.ts` 401/403 门禁）。伪造 Host 或缺失合法 token 的请求返回 401/403。本补丁**未改动**此文件，仅记录该基线中的现有鉴权实现。

## 验证方法

1. 静态检测：运行本目录 `verify-dsh-fixes.bat`，五项应全部 `[PASS]`。
2. 回归测试：`pnpm exec vitest run packages/fs/fs-sandbox/tests/fs-sandbox.spec.ts packages/extensions/cordis-host-runner/tests/sandbox-context.spec.ts packages/boot/app-boot/tests/user-patches.spec.ts`。
3. 全量构建：`pnpm run build`（三方：host / client / web 均通过）。

## 已知残留与限制（重要）

本补丁针对五个 QVD 的公开 PoC 攻击面做了闭合，但**并非对所有边界都做到全封闭**，请如实知悉：

### QVD-2026-52632 的进程级读面

- **已修复**：进程内 fs-sandbox 读取执行点策略校验（`checkedReadTarget` / `FS_SANDBOX_DENIED`），模型经 `tool-fs` 的 read/read_image 无法再越界读取任意路径。
- **未覆盖（残留）**：进程级沙箱后端在 read-only 模式下仍把整个宿主文件系统只读暴露给受限 shell 子进程：
  - bwrap（Linux）：`--ro-bind / /` 把 `/` 只读挂载进沙箱；
  - landlock（Linux 兜底）：`readOnly: ['/']`；
  - seatbelt（macOS）：allow-default（默认允许读，仅拒绝写）。
- **含义**：在 read-only 会话里跑的 bash/pwsh 仍可能 `cat ~/.ssh/id_rsa`、`cat .env` 等，读取沙箱未隔离的敏感文件。这是上游披露中 52632 根因的一部分，本补丁未收窄（收窄进程级读面需对三个后端做系统目录白名单，风险较高，且无法在 Windows 本机验证 Linux/macOS 后端）。
- **缓解**：不要依赖"只读模式"保护敏感文件；把 `.ssh`、`.env`、云凭据等移出 agent 可读目录，或在独立容器/VM 中处理不可信内容。

### 读侧「放宽一次」审批入口缺失（2026-09-26）

- `read` / `glob` / `grep` 被拒时的提示文本提到 `sandbox_permissions`（升级提示），但**这三个工具的工具 schema 里没有该字段** —— 模型/用户看到提示，却没有对应的可操作入口去「放宽一次」。
- 对照：会产生该提示的 `pwsh` 等工具本身声明了该字段。这属于**提示与能力面不一致**，不是拒绝逻辑错误。
- 状态：**未修**。

### 凭据存储的读面（2026-09-26 轮次后）

- **已收窄**：`$DSH_HOME/.credentials*` 经模型可读面（`read` / 搜索栅栏 / fs-sandbox）在**任何模式（含 `danger-full-access`）**都被拒（`FS_PERMISSION_DENIED`）；判据由 `packages/fs/fs/src/index.ts` 的 `isProtectedReadPath` 单点导出。
- **未收窄**：`shell` / `pwsh` 起动子进程后仍是**进程级读面**（`bwrap --ro-bind / /` 一类），仍可读取凭据文件。
- 含义：链 F（沙箱内 Agent 自解除沙箱）的「读签名密钥 → 伪造 cookie」一步，**在进程内读面上被堵住，在 shell 通道上仍然敞开**。

### 更彻底的做法：升级官方修复版

奇安信/安天披露中提到厂商已发布修复版本（如 v0.1.0-rc.8 及后续）。本补丁是对 `0.1.2-alpha.2` 树的补强；**若条件允许，优先升级到官方最新修复版**，并以官方 changelog 为准核对这五个 QVD 的修复状态。升级后本补丁可能不再适用（官方代码结构已变），`verify-dsh-fixes.bat` 的检测标记也可能随版本演进而需要适配。

### 间接提示注入（不属于本补丁范围）

腾讯朱雀实验室 14,560 次实测（2026-08）显示，DSH 基线配置对间接提示注入的防御仍在早期阶段（完全成功约 5.3%）。这是**模型层面**的固有风险，**代码补丁无法消除**：网页/文档/邮件/Skill 等不可信内容可能诱导模型调用敏感工具。缓解只能靠运行习惯——外部内容一律按不可信处理、敏感操作留人审批、最小权限、独立容器。参考：https://matrix.tencent.com/zh/2026/08/20/deepseek-harness-agent-injection-risk

---

# 0.1.5-rc.2 补充补丁（2026-09-18）

第一批补丁（`fixes.patch`）针对 0.1.2-alpha.2。把该树迁移到 0.1.5-rc.2 后，对五个 QVD 的公开 PoC 攻击面做了**逐项复核**：上游在 0.1.2 → 0.1.5 的三个版本区间里**没有修任何一项**，并且还有两条同源路径未覆盖。本批补丁闭合这两条。

## 复核结论（0.1.5-rc.2 源码实测，非推测）

| QVD | 0.1.5-rc.2 状态 | 证据 |
|---|---|---|
| 52631 配置加载 RCE | 仍未修 | `vendor/loader/src/config/utils.ts:5` 依旧是 `new Function('ctx','expr', …)` + `with (ctx) { … }` |
| 52632 只读沙箱泄露 | 仍未修 | `packages/fs/fs-sandbox/src/index.ts:7` 自述 "Reads pass through untouched: every mode permits reading" |
| 52644 VM 沙箱逃逸 | 仍未修 | `cordis-host-runner/src/guard.ts` 把 `exec` 原样透传给 `rawExecute`，无白名单视图 |
| 52646 链式逃逸 RCE | 仍未修 | `subprocess-local/src/spawn.ts` 无 `argvConfined` / `assertConfinedUnderPolicy` |
| 57410 Host 头未授权 RCE | **部分修复，仍有致命残留** | 上游 0.1.2+ 已加 browser-token 鉴权（401），但信任判断**仍无 TCP 层输入** |

> 因此第一批补丁在 0.1.5-rc.2 上**不是历史包袱而是必需品**；升级版本并不等于修好漏洞。

## 补充补丁 1：`qvd-2026-57410-transport-fence.patch`

**问题**：`ConnectionTrustRequest` 只携带 `headers`，`isTrustedApiRequest` 因此**只能**校验客户端可伪造的 `Host` 头。PoC 的修复建议原文写着「校验 TCP `remoteAddress` 而非 `Host` 头」，上游未采纳。结果是 token 成为唯一防线——token 一旦泄露（URL 进日志、Referer、截图、被分享的链接），伪造 `Host: 127.0.0.1` 即可换取浏览器 cookie。

**改动**：
- `ConnectionTrustRequest` 增加可选 `socket`（`node:http` 请求天然携带，**四个调用点零改动**）
- `loopback-hostname.ts` 新增共享的 `isLoopbackAddress()`（识别 `127.x`、`::1`、`::ffff:127.0.0.1`）
- `isTrustedApiRequest` 新增**传输围栏**：Host 声称 loopback 而 peer 不是 loopback → 拒绝；`trustedProxies` 是唯一例外
- `BrowserAuth.authorizeIndex` 同步加固：**token → cookie 交换**此前完全没有 peer 校验
- 新配置 `trustedProxies: string[]`（默认空 = 最严格）

**行为影响**：本机 `127.0.0.1` 访问不受影响；LAN / 反代部署若未声明 `trustedProxies`，远程请求会被拒——这正是加固的方向。

**验证**：`api-request-trust.host.spec.ts` 新增 2 个用例；connection 包 **164 tests passed**；`tsc -b` 退出码 0。

## 补充补丁 2：`qvd-2026-52632-editor-read-fence.patch`

**问题**：第一批补丁只修了 `tool-fs` 的 `read` / `read_image`。**`tool-str-replace-editor` 的 `view` 命令读文件时不带策略**——它是另一个模型可用的文件读取入口，而其写路径本来就用 `MutationPolicy`，只有读路径漏了。攻击面与 52632 完全同源。

**改动**：`viewPath` 增加 `policy` 参数并解析会话策略；`str_replace` / `insert` 的编辑前读取（用于计算差异）同样带上策略与错误映射。

**验证**：`tsc -b` 退出码 0；该包 **14 tests passed**。

## 补充补丁 3：`qvd-2026-52632-plugin-fs-fence.patch`

**问题**：动态 Cordis 插件（模型在运行时写的代码）经 `inject: ['fs']` 拿到的 fs 服务，**读路径**在无 policy 时透传——而 `cordis-host-runner/src/sandbox.ts` 恰恰明确引导插件用 `inject: ['fs']` 访问文件（vm 沙箱禁掉了 `require`）。写路径在无 policy 时已默认 `ctx.sandboxPolicy.resolve()`，**这个读写不一致本身就是缺陷**。

**修复位置是关键**：fs 服务与宿主共享，宿主的自有读取（会话持久化、技能加载、附件）必须保持透传——**这是宿主契约，不能改**。所以围栏加在**动态插件进入系统的边界**上，而不是改 fs 的默认行为：

```
宿主内部  → ctx.fs.readText(…)                     → 透传（契约不变）
动态插件  → sandboxContext 门面 → 强制带策略的读    → 受会话策略约束
```

**改动**：
- `guard.ts` 新增 `fencedFsService()`：包装 fs 的 `readText` / `streamText` / `readBytes`，把会话策略放在**声明的位置**（调用方省略可选参数时也保持位置），并**丢弃插件自己传的策略**——插件无法放宽自己的边界
- 策略在门面构建时**解析一次**（`ctx.get('sandboxPolicy').resolve({ session })`），插件看不到解析器
- 接线：`startHost` 用 `rootCtx.get('agents')?.get(plugin.sessionId)?.session` 解析会话 → `startHostHalf` → `guardedPlugin` → `sandboxContext`
- **零依赖新增**：policy 类型用结构化声明，不需要引入 `dsh-sandbox` 依赖

**验证**：新增 4 个用例（追加策略 / 覆盖插件传入的策略 / 三参数读的位置正确 / 非读成员不受影响）；该包 **98 tests passed**；`tsc -b` 退出码 0；全量构建 exit 0。

**未改变的行为**：宿主自有读取仍是透传（第一批补丁的 `reads without a policy remain host-owned pass-throughs` 断言依然成立）；没有 session 的测试夹具走旧路径。

## 状态清单（按可修性分类）

| 项 | 状态 | 说明 |
|---|---|---|
| 52632 插件直读面 | **已修复** | 补充补丁 3 |
| 52646 受限 spawn fail-open | **已修复** | 补充补丁 4（红队测试发现） |
| Agent Loop 纯文本重复 | **已加固** | 补充补丁 5（新增守卫包） |
| 52631 env 全量投影 | **未修复（架构限制）** | 见下方定性说明 |
| 52632 进程级读面 | **deferred — requires platform-specific validation** | 需在 Linux/macOS 上验证后端后才谈实现 |
| 52632 硬链接绕过 | **未修复（已知绕过）** | 见 `REDTEAM.md` |
| `macOS_DSH_LPE` | **不适用** | Apple 系统组件漏洞，与 DSH 仅缩写同名 |

## 补充补丁 4：`qvd-2026-52646-confined-spawn-fail-closed.patch`

> **⚠️ 这个补丁会覆盖基线写入的同一函数。**
> `fixes.patch` 里的 `assertConfinedUnderPolicy` 就是下面这个**带 fail-open 缺陷的旧版本**。在 0.1.5-rc.2 上**只应用基线会装上一个有缺陷的守卫**，必须叠加本补丁才是 fail-closed 版本。应用顺序：**基线 → 本补丁**。

**来源**：红队测试发现，不是审计推测。

**问题**：原守卫为

```ts
const mode = spec.sandboxPolicy?.mode
if (mode !== undefined && mode !== 'danger-full-access' && spec.argvConfined !== true) { throw … }
//  ↑ 这个前置条件让 sandboxPolicy: {} 直接放行
```

`sandboxPolicy` 存在但 `mode` 为 `undefined` 时**静默放行**——正是守卫本该防止的"策略静默失效"。

**修复**：改为 fail-closed——policy 一旦存在，**只有字面 `danger-full-access` 才豁免**；mode 缺失或未知一律拒绝。

**严重度（诚实评估）**：`SubprocessSpawnSpec.sandboxPolicy.mode` 在类型上必填，所以这是**类型系统之外的输入**，不是可远程触发的漏洞。它是**纵深防御的缺口**：守卫存在的意义就是兜住"调用方忘了"的情况，而它在这个形状上没兜住。

**验证**：新增 13 个对抗用例（含 `argvConfined` 的 5 种非 `true` 取值、未知 mode、mode 缺失）；**13/13 通过**。

## 红队测试（对抗验证）

完整报告见 **[REDTEAM.md](./REDTEAM.md)**。摘要：

| 套件 | 用例数 | 结果 |
|---|---|---|
| 读栅栏对抗（`redteam-read-fence.spec.ts`） | 16 | 15 阻断 / **1 已知绕过（硬链接）** |
| 受限 spawn 对抗（`redteam-confined-spawn.spec.ts`） | 13 | 13 阻断（修复 fail-open 后） |
| Agent Loop 终止性（`redteam-loop-termination.spec.ts`） | 4 | 4 通过 |
| **合计** | **33** | |

**Agent Loop 重复输出的结论**：经 Model/Harness 分离实测，模型返回纯文本（无 tool-call block）时 loop **只请求 1 次即终止**——终止逻辑正确，**不是 Harness 状态机缺陷**。真实缺口是**没有任何守卫覆盖纯文本重复**（`repeat-tool-reminder` 只挂在 `tools/post-execute`，需有工具调用才触发）。

## 验证脚本变更

`verify-dsh-fixes.bat` 现在区分两类检查：

- **基线项**（11 项）：缺失记 `[FAIL]`，计入退出码
- **可选补充补丁 + 红队套件**（8 项）：缺失记 `[SKIP]`，**不计入 FAIL**——补充补丁是可选增量，未应用不代表基线有问题

同时修复了脚本自身的缺陷：`DSH_REPO` 环境变量此前**实际不生效**（`if` 块在解析时即展开 `%ROOT%`，导致检查查的是脚本自身目录），已改为延迟展开 `!VAR!`；并移除了写死的本机路径。

## 补充补丁 5：`guard-repeat-text-reminder.patch`（新增守卫包）

**来源**：Agent Loop 重复输出的红队调查（见 `REDTEAM.md` 第三节）。

**问题**：`repeat-tool-reminder` 挂在 `tools/post-execute`，**只在有工具调用时触发**；全仓不存在文本级循环检测。模型反复输出相同文本时没有任何守卫介入。

**修复**：新增 `packages/guard/repeat-text-reminder`，挂在 `agent/pre-step`，检测**连续 step 的 assistant 文本重复**。

**明确不是字符串黑名单**（设计红线）：

- 比较**规范化文本**（折叠空白、trim；标点、措辞、大小写仍敏感）
- **任何内容变化即重置**计数，所以重复一个词或标题不会触发
- 短于 `minChars`（默认 8）的文本**完全不计数**，所以 `ok` / `好。` 这类正常应答永不触发
- **不匹配任何特定词**——加黑名单既修不了状态环，也会在模型换个说法时静默失效

**配置**：
```yaml
- id: repeat-text-reminder
  config:
    thresholds: [3, 5, 8]   # 连续相同文本的触发阈值
    minChars: 8             # 最小计数长度；0 表示所有非空文本
    textPreviewChars: 200   # 详细提醒中引用文本的上限
```

**验证**：15 个用例，含 6 个**对抗用例**（单次回答不触发、短应答重复 5 次不触发、文本变化不触发、用户插话重置、不否决 reject、跨 agent 隔离）；**15/15 通过**。

**已知限制（诚实记录）**：
- 守卫是**咨询型**：它请求模型停止，**不终止 turn**。忽略提醒的模型会继续跑。硬性迭代上限属于 loop，不属于咨询型读取器。
- 检测在 `agent/pre-step` 运行，观察的是**已提交**的文本——它无法阻止第一次重复，只能劝阻下一次。
- 语义等价但措辞不同的重复检测不到；那需要模型侧判断，不是文本比较。

## 关于 52631 的定性（重要）

**审计不等于修复。** 若攻击路径是 `配置表达式 → process.env → 宿主秘密`，那么记录一条 `accessed SOME_SECRET` 并不阻止秘密被读取。本仓库**不声称**该漏洞已修复。

### 分层投影经调查确认不可行（架构限制）

原计划是"按配置来源分层投影"——可信层给完整 env、第三方层给受限 env。**代码层面逐层验证后确认做不到**：

1. `EntryOptions`（`vendor/loader/src/config/entry.ts:9-22`）字段只有 `id`/`name`/`config`/`group`/`disabled`/`inject`，**没有来源字段**。
2. `composeEntries`（`packages/boot/app-boot/src/profile.ts:846-853`）：
   ```ts
   return applyEntryPatches([], structuredClone(layers.flat()), …)
   //                                            ^^^^^^^^^^^^^ 来源信息在这里被丢弃
   ```
   所有层被**扁平化成一个列表**，之后无法区分哪一行来自哪一层。
3. `ProfileLayer` **在合并前**是有 `packageName`/`patchPath` 的——**信息存在过，只是 compose 时没保留**。

要保留来源需要跨三个包改数据结构（`EntryOptions` + `composeEntries`/`applyEntryPatches` + `evaluate`），涉及 vendor 目录且会改变 `applyEntryPatches` 的纯函数语义。**改错会让整个 profile 组合失效，DSH 直接起不来**——比 env 泄露严重得多。

**准确的表述**：这需要**上游引入「配置来源信任」模型**，把来源信息从 profile 层一路保留到求值点。本仓库的补丁无法在不动数据结构的前提下闭合它。

### 威胁模型补充（比原描述更严重）

原 README 的描述是"攻击者需先能投递或写入恶意配置，**非远程一键触发**"。这个定性**仍然准确**，但应补充：

**安装一个第三方插件就足以投递。** bundle 层的 `cordis.patch.yml` 同样能写 `!!js`，而它来自 npm 包——**不需要社工诱导用户粘贴配置**。

### 可行的替代方案（未实施）

- **方案 A 求值期审计**：vm 的 `process.env` 套 Proxy，记录哪个 entry、哪个表达式读了哪些 key。**零行为改变、零破坏风险**，但**是审计不是修复**——必须如实标注。
- **方案 B 敏感变量黑名单**：会**直接破坏现有部署**（合法配置大量使用 `process.env.DEEPSEEK_API_KEY`），且黑名单永远列不全。**不推荐**。
- **方案 C 显式声明制**：要求 `!!js` 读 env 必须显式声明 key。最彻底，但需改配置语法和所有现有配置，属**上游级别**工作。

### 关于 52632 进程级读面的定性

不是"无法修复"，而是 **deferred / requires platform-specific validation**：当前版本不做未经验证的代码修改，保留 PoC 与风险说明，待有 Linux/macOS 环境验证真实沙箱后端后再决定是否实现。

## 应用方式

```bat
rem 在 0.1.5-rc.2（或已含第一批补丁的同版本树）上执行
git apply --check qvd-2026-57410-transport-fence.patch
git apply       qvd-2026-57410-transport-fence.patch
git apply --check qvd-2026-52632-editor-read-fence.patch
git apply       qvd-2026-52632-editor-read-fence.patch
```

两个补丁互不重叠，可独立应用。补丁以 LF 生成；Windows 检出若为 CRLF 导致 `does not apply`，加 `--ignore-whitespace` 重试。

---

# 0.1.5-rc.2 一键补丁与零日修复（2026-09-23）

## 1. `fixes-0.1.5-rc.2.patch` —— 单一完整补丁

| 项 | 值 |
|---|---|
| 目标版本 | **0.1.5-rc.2**（干净检出） |
| 规模 | 48 文件，+2114 / −74 |
| SHA-256 | `9A2FA061BE21B3BE4CFB98CD3F7ACCA0741C4DDBF71EF1503D6FF06BB9A4ABF5` |
| 内容 | 基线（52631 / 52632 / 52644 / 52646）+ 5 个补充补丁的**最终效果** |
| 验证 | 全新 `git archive` 干净树 `git apply --check` → exit 0；应用后 `checkedReadTarget` 等修复标记在位 |

**为什么需要它**：`fixes.patch` 相对 0.1.2-alpha.2 生成，在 0.1.5-rc.2 上有 5 个文件打不上（见文首更正）。
把它与补充补丁"合并"并不可行 —— 两者锚定不同版本的上下文，且都定义 `assertConfinedUnderPolicy`（基线是 fail-open 旧版、补充补丁 4 是覆盖版），放进同一个 diff 会冲突或产生重复声明。
**因此改为按最终效果重新生成单一 diff**，等价且自洽。

**副作用（正向）**：单一补丁里只有 fail-closed 版本，**不会**再出现「只打了基线、装上一个带 fail-open 缺陷的守卫」这种事故。

## 2. `code-runtime-isolation.patch` —— `run_code` 代码运行时隔离缺口

> **状态：未上报上游、未定级。** 本节不含可直接复现的攻击步骤。

| 项 | 值 |
|---|---|
| 目标文件 | `packages/code-runtime/code-runtime-worker-thread/src/bootstrap.ts` |
| 规模 | 1 文件，+38 / −11 |
| SHA-256 | `C85FC4E4318B638F8F6D83FFCF67B60CE21661E76032342865AEA32945E59C66` |

**问题**：该运行时把模型代码交给 worker 的**全局作用域**执行（`(async () => {}).constructor`），
且**完全不接收会话沙箱策略**（`packages/code-runtime` 内 `sandboxPolicy` 零引用）。
worker 只做了两件事：`env: {}` 与 `execArgv: []` —— 都不构成边界。

**实测对照（同一会话、同一 `workspace-write` 策略）**：

| 通道 | 工作区外读 / 写 |
|---|---|
| `read` / `write` 工具 | **被拒**（`[sandbox: file access denied under workspace-write mode]`） |
| `pwsh` 子进程 | **被拒**（`Access to the path is denied`） |
| `run_code` | **成功**（读工作区外 canary、写入工作区外文件、读取凭据文件） |

**修复**：
- 程序体改在 `node:vm` 上下文中执行（`createContext` + `vm.Script`，包成 async IIFE）；
- 上下文只挂载声明的绑定与 console 垫片；
- `codeGeneration: { strings: false, wasm: false }` —— 连 vm 内部的 `Function` 构造器与 `eval` 一起关掉；
- **不提供** `importModuleDynamically` 回调 —— 动态 `import` 直接 reject；
- 定时器以 **null-prototype 包装**注入（宿主函数直接注入会经 `.constructor` 把宿主 realm 交回去）。

**两个实现陷阱（实测踩到，务必保留）**：
1. 用 **vm realm 的 `AsyncFunction` 不管用** —— Function 构造器创建的函数会把 `import()` 解析到宿主 realm，实测仍能导入 `node:fs`。**必须用 `vm.Script` 直接编译程序体。**
2. 注入宿主函数会重新开洞 —— `setTimeout.constructor` 就是宿主 realm 的 Function 构造器。

**验证结果（直接驱动 `bootstrap.ts`，8 项）**：

| 用例 | 结果 |
|---|---|
| `await import('node:fs')` | 🚫 `ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING` |
| `typeof process` / `fetch` / `require` | 全部 `undefined` |
| `(function(){}).constructor('return 1')` | 🚫 `EvalError` |
| `eval('1+1')` | 🚫 `EvalError` |
| `setTimeout.constructor('return typeof process')` | 🚫 `TypeError`（原型为 `null`） |
| `setTimeout` / `queueMicrotask` | ✅ 可用 |
| 返回对象 / 数组（跨 realm JSON） | ✅ 正常 |
| 绑定调用 / console 捕获 / 异常路径 | ✅ 正常 |

**已知边界（如实记录）**：
- 跨 realm 的异常**丢失堆栈**，只保留 message（`prepareException` 的 `instanceof` 在跨 realm 时为假）；
- `vitest` 全量回归**未在本机跑通** —— 沙箱下 vite 的管道 `exec` 报 `spawn EPERM`（文档化的沙箱边界），
  故改用**直接驱动 `bootstrap.ts`** 的针对性脚本验证（Node 24 原生类型剥离）；
- 未验证 read-only 会话下 `run_code` 工具是否仍可见。

**披露建议**：先交上游审核，再决定是否公开分发。`apply-dsh-fixes.bat` 对它是**单独的二次确认**，默认不应用。

> **2026-09-26 补充（架构变更）**：0.1.7-rc.2 上游已把 `code-runtime-worker-thread` 换成 `ptc-runtime-node` 架构，**本补丁不再适用于该版本**。本轮改在同一份 0.1.7-rc.2 检出的**新架构**上补齐宿主对象泄漏面，见下节第 3 项。

---

# 0.1.7-rc.2 轮次（2026-09-26）

> 目标：本地 DSH **0.1.7-rc.2** 检出；补丁文件 `fixes-0.1.7-rc.2.patch`（**2026-09-26 主流程重生成：105 文件 / +5800 −157 / 719,078 字节，SHA-256 `B23EB756EED71AC30EDB79E7CA5D233CA1108F5C897570514FA357464D55101C`**；生成时排除 `**/src/**/*.js|.d.ts|*.map` 的编译残留）。
> **本轮只写已落实的改动；8 条残留列在本节末尾，未修就是未修。**

## 1. QVD-2026-52632 剩余缺口：`grep` / `glob` 的搜索根

- **问题**：`grep` / `glob` 用 `ctx.subprocess.spawn` **裸跑 ripgrep、不传策略**，fs 栅栏因此看不到搜索根 —— 一次 `path: '~/.ssh'` 的 grep 就能读到 workspace 受限的 `read` 明确拒绝的内容。
- **修复**：新增 `packages/fs/tool-fs-search/src/search-sandbox.ts`（`SearchSandboxFence`）。
  - 每次调用**现取** `ctx.fs` / `ctx.sandboxPolicy`（插件可在装配之后才被挂载）；
  - 用后端自己的 `resolve` + `contains` 比对：read-only → `workspaceRoot`；workspace-write → `writableRoots`（别名、符号链接、平台大小写都不会放宽包含关系）；
  - 拒绝时抛与 `read` **文本完全一致**的 `[sandbox: …]` 标记 + 同一条升级提示，并保留结构化 `FS_SANDBOX_DENIED`（后端围栏的原文作 `cause`）；
  - **在 spawn 之前**拦截；
  - 无 `ctx.fs`、已挂载但不限制（`sandboxMode === undefined`）、或 `danger-full-access` → 直通（与无策略的 `read` 行为一致）。
- **边界（写清楚）**：这是**受信任代码里的策略检查**，**不是**对 spawned 进程的内核隔离 —— ripgrep 的 argv 从不经 `ctx.sandbox.confine`，该 spawn 依然无约束，也不声明 `argvConfined`。
- **附带**：12 条用例（`packages/fs/tool-fs-search/tests/search-root-fence.spec.ts`，含 “denies … before any spawn”“danger-full-access leaves the search unconfined” 等）；该包补了 `dsh-fs` / `dsh-sandbox` / `dsh-sandbox-policy` 依赖与 tsconfig references。

## 2. 凭据不可读

- **问题**：浏览器会话签名密钥存放在 `$DSH_HOME/.credentials*`；只要它能被模型可读面读到，链 F（沙箱内 Agent 自解除沙箱）就有伪造 cookie 的入口。
- **修复**：判据上移到 `packages/fs/fs/src/index.ts` 导出的 `isProtectedReadPath`，**fs-sandbox 与搜索栅栏共用同一判据**：`$DSH_HOME/.credentials*` 在**任何模式（含 `danger-full-access`）**都被拒，错误码 `FS_PERMISSION_DENIED`。
- **不受影响**：宿主侧读凭据走 `fs-local`，不经过围栏（宿主自有读取仍是契约内的透传）。
- **残留**：`shell` / `pwsh` 仍可读凭据（进程级读面）。

## 3. `run_code` 逃逸封堵（新架构）

- **背景**：0.1.7 上游已换成 `ptc-runtime-node` 架构，旧的 worker-thread 版零日补丁不适用（见上一节末尾的补充）。
- **问题**：注入到 vm realm 的**宿主对象**（console shim、每个 namespace 绑定、binding error class）自身带着可回到宿主 realm 的 `constructor` —— `console.log.constructor('return process.pid')()` 即可取回宿主 `process`。
- **修复**：`packages/ptc-runtime/ptc-runtime-node/src/bootstrap.ts` 新增 `detachedHostSurface()` —— **null 原型包装** + `Reflect.construct` 保留 `new` 语义 + `WeakSet` 防环；console shim、每个 namespace 绑定、binding error class **全部**经它包装。
- **实测**：同一表达式由**返回宿主 pid** 变为 `console.log.constructor is not a function`。

## 4. `/api/file` 根白名单

- `packages/api/session-controller/src/media-references.ts`：为 `GET|HEAD /api/file` 增加只读根 —— Workspace 注册表登记的路径 + `process.cwd()` + `os.tmpdir()`；可用 `Config.roots` 覆盖（空数组 → 用默认根）。
- 越界：**403** + body `MEDIA_PATH_OUTSIDE_ROOTS`（**HEAD 无 body**）。
- **残留**：`Config.roots` 目前**只有直接挂载才能设**，随附组合未把该项暴露到 `cordis.yml`。

## 5. `/api/session.export` 鉴权

- `packages/session-query/session-log-export/src/index.ts`：复用 Connection 的 `requestRejection`（Host / TCP peer / cookie 三合一），并加上与 `tool-session-query/workspace-access.ts` 同款的工作区绑定。
- 越权与不存在**都**返回 403 `SESSION_LOG_EXPORT_OUTSIDE_WORKSPACE` —— **不泄漏存在性**。
- **残留**：调用方身份只判到「部署」层（同一 `DSH_HOME` 多实例共享注册表时区分不了实例）；`includeDescendants` 拉入的后代日志**未逐个复检**。

## 6. `/plugins/events` 与 `/plugins` 的信任围栏

- `packages/client/hmr/src/index.ts`（SSE 频道）与 `packages/client/modules/src/index.ts`（bundle 路由）各自接 `browserTrustFence(ctx)`：未认证 **401**、异 Host / rebound **403**。
- **在查找 bundle 之前**就拒绝；SSE 通道**不写任何帧**（未认证连接拿不到 plugin graph）。无 Connection 时通道直接 403 关闭（fail-closed）。

## 7. duplicate Host 拒绝

- `packages/client/connection/src/api-request-trust.ts` 新增结构化拒绝 code：`host-missing` / `host-repeated` / `host-unparsable` / `host-untrusted` / `host-authority-mismatch` / `peer-not-loopback` / `cross-site` / `origin-unparsable` / `origin-mismatch`。
- **>1 个 Host**（`rawHeaders` 里的重复字段）**或 Host ≠ 请求自身权威**，一律拒绝 —— `node:http` 会把重复 Host 折叠成第一个，只看 `headers` 分辨不出来。
- **残留**：结构化 code **已导出但未进 HTTP 响应体**（对外仍是 401/403 状态码 + 简短文本）。

## 本轮残留清单（8 条，全部未修）

| # | 残留 | 影响 |
|---|---|---|
| 1 | `read` / `glob` / `grep` 的拒绝提示提到 `sandbox_permissions`，但工具 schema 没有该字段 | 读侧「放宽一次」审批入口缺失 |
| 2 | `shell` / `pwsh` 进程级读面（`bwrap --ro-bind / /` 一类） | 受限 shell 仍可读全盘，包括凭据 |
| 3 | `/api/file` 的 `Config.roots` 只有直接挂载才能设 | 随附组合未暴露到 `cordis.yml` |
| 4 | `session.export` 调用方身份只到「部署」层 | 同一 `DSH_HOME` 多实例共享注册表时区分不了实例 |
| 5 | `includeDescendants` 拉入的后代日志未逐个复检 | 后代日志的工作区归属未验证 |
| 6 | 结构化拒绝 code 未进 HTTP 响应体 | 调用方只能看状态码 |
| 7 | `apps/web` e2e 未跑（`DSH_SNAPSHOT=replay pnpm run test:web`） | 浏览器侧装配未端到端验证 |
| 8 | 上游官方 0.1.7-rc.2 对这些点**一条都没修** | 升级不等于修好；唯一例外是 `run_code` 那条零日 —— 官方换了 `ptc-runtime-node` 架构，旧 PoC 不再适用 |

## 应用与验证

```bat
rem 干净的 0.1.7-rc.2 检出上
git apply --check fixes-0.1.7-rc.2.patch
git apply       fixes-0.1.7-rc.2.patch
```

- 一键脚本 `apply-dsh-fixes.bat` 按检出 `package.json` 的版本自动选择补丁（0.1.7 → 本补丁；否则 0.1.5 → `fixes-0.1.5-rc.2.patch`），先预检、再询问、后写入。
- 静态验证：`verify-dsh-fixes.bat`（本轮新增 12 项检查，缺失记 `[SKIP]`，不影响 0.1.5 / 0.1.2 树上的基线结论）。
- 定向测试：`pnpm exec vitest run packages/fs/tool-fs-search/tests/search-root-fence.spec.ts`（12 用例）。
- 红队实测（2026-09-26）：见 `REDTEAM.md` 第五节。
