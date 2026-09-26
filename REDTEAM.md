# Red Team Report — DSH QVD 补丁对抗测试

> **关于文中出现的 `qvd-2026-*.patch`**：5 个分项补丁已于 2026-09-23 并入 `fixes-0.1.5-rc.2.patch` 并从仓库移除；文中引用保留作审计记录。

> 本文件记录**主动攻击自己的补丁**的结果。目标不是证明"补丁看起来没问题"，而是用可复核的证据说明**哪些攻击被阻断、哪些仍然成功**。

## 测试环境

| 项目 | 值 |
|---|---|
| 目标 | DeepSeek Harness `0.1.5-rc.2`（本地检出 `D:\deepseek-harness-master\dsh-0.1.5-rc.2`）；**2026-09-26 轮次目标为本地 `0.1.7-rc.2` 检出** |
| 补丁 | 本仓库 `fixes.patch` + **五个**补充补丁（2026-09-23 起 0.1.5-rc.2 亦可用单一补丁 `fixes-0.1.5-rc.2.patch`）；2026-09-26 轮次用 `fixes-0.1.7-rc.2.patch` |
| 平台 | Windows 11 x64，Node v24.20.0，非管理员账户 |
| 隔离方式 | 每个用例使用 `mkdtemp` 临时目录；workspace 与 outside 为同级目录；canary 为测试专用文件 |
| 外部副作用 | **无**。不联网、不触碰真实账号/服务器/数据；subprocess 守卫测试为纯谓词，不启动任何进程 |
| 测试日期 | 2026-09-18（第一、二、三、四节）；**2026-09-26（第五节）** |

## 证据分级

每个用例记录它实际到达的阶段，而不是只记"成功/失败"：

| 级别 | 含义 |
|---|---|
| `Blocked` | 攻击在守卫处被拒绝 |
| `Bypassed` | 攻击穿过守卫并到达受控 Sink |
| `NotReached` | 攻击因环境限制（如权限）根本没跑到守卫 |
| `Current Behavior` | 记录现状，**不声称安全** |

---

## 一、读栅栏（QVD-2026-52632）

测试文件：`packages/fs/fs-sandbox/tests/redteam-read-fence.spec.ts`
结果：**16 个用例全部按预期通过**（实际分布：**14 Blocked / 1 Bypassed / 1 Current Behavior**，见下表）。

> 口径说明："通过"指**用例断言与当前行为一致**，**不等于** 16 次攻击都被阻断 —— 其中 1 次是已承认的绕过（硬链接），1 次是记录现状（`danger-full-access` 语义即无限制）。

Canary 为 workspace 外同级目录中的 `CANARY-8f3a2b-do-not-exfiltrate`。

| # | 攻击向量 | 结果 | 级别 |
|---|---|---|---|
| 1 | 绝对路径（基线） | 拒绝 | Blocked |
| 2 | `..` 遍历 | 拒绝 | Blocked |
| 3 | 重复分隔符 `///../` | 拒绝 | Blocked |
| 4 | 尾随 `.` 段 | 拒绝 | Blocked |
| 5 | 混合 `./.././` | 拒绝 | Blocked |
| 6 | `..` 越根再折返 | 拒绝 | Blocked |
| 7 | 反斜杠分隔遍历（Windows） | 拒绝 | Blocked |
| 8 | **目录 junction 指向外部** | 拒绝 | Blocked |
| 9 | **junction 链跳转** | 拒绝 | Blocked |
| 10 | junction + `..` 折返 | 拒绝 | Blocked |
| 11 | 大小写变体 | 拒绝 | Blocked |
| 12 | Unicode 除号 U+2215 伪装分隔符 | 不泄露 | Blocked |
| 13 | workspace-write 模式下同样攻击 | 拒绝 | Blocked |
| 14 | canary 内容从不出现在拒绝结果中 | 通过 | Blocked |
| 15 | **硬链接 canary 放进工作区** | **读取成功** | **Bypassed** |
| 16 | danger-full-access 不设栅栏 | 读取成功 | Current Behavior |

### 关键发现 1：Windows symlink 是环境限制，不是漏洞

最初 4 个 symlink 用例失败，一度像是绕过。**实测根因是 `EPERM`**：Windows 创建符号链接需要管理员权限或开发者模式，本机两者皆无（`AllowDevelopmentWithoutDevLicense` 为空、非管理员）。

改用**非特权攻击者真正可用的原语**重测：

- **junction**（`symlink(…, 'junction')`，无需特权）→ 被阻断
- **hardlink**（`fs.link`，无需特权）→ 见下

> 教训：不能把"测试跑不起来"当成"漏洞存在"，也不能把"没观察到"当成"安全"。

### 关键发现 2：硬链接是真实的已知绕过（Bypassed）

```ts
await link(canary, join(workspace, 'hard.txt'))   // 同一 inode 的第二个名字
await fs.readText(target, undefined, policy)      // 路径在工作区内 → 栅栏放行
// → 返回 CANARY 内容
```

**根因**：栅栏是**基于路径**的（`isPathUnder` 比较 lexical 前缀与 inode 身份，但比较的是**目标路径**与 root）。硬链接让"工作区内的路径"指向"工作区外的 inode"，路径判定无法察觉。

**为什么是限制而非独立漏洞**：利用它需要攻击者**已经能在工作区内创建硬链接**（即已有写原语）。此时读取该 inode 是既有写权限的延伸，而不是凭空提权。

**缓解**：不要把敏感文件放在与 agent 工作区**同一卷**上（硬链接不能跨卷）。这是本补丁**未解决**的边界。

### 关键发现 3：测试自身的假设错误（已修正）

`danger-full-access` 用例最初失败，原因是 `attempt()` 把 policy 硬编码为 `mode: 'read-only'`，与部署模式无关。修正为跟随 `boot()` 的模式后通过。

**这不是补丁缺陷，是测试写错。** 记录在此以说明：失败用例必须查清是"补丁问题"还是"测试问题"。

---

## 二、受限子进程守卫（QVD-2026-52646）

测试文件：`packages/subprocess/subprocess-local/tests/redteam-confined-spawn.spec.ts`
结果：**13 通过 / 0 失败**（修复后）

| # | 攻击向量 | 结果 |
|---|---|---|
| 1 | `read-only` 无 `argvConfined` | 拒绝 |
| 2 | `workspace-write` 无 `argvConfined` | 拒绝 |
| 3 | `danger-full-access` 无 `argvConfined` | 放行（设计如此） |
| 4 | 完全无 policy | 放行（宿主自有 spawn） |
| 5 | 正确 confined 的受限 spawn | 放行 |
| 6 | `argvConfined` 省略 / `false` / `0` / `''` / `null` | **全部拒绝**（要求字面 `true`，无 truthy 捷径） |
| 7 | 未知 mode 字符串（如 `readonly`） | 拒绝（fail-closed） |
| 8 | **`sandboxPolicy: {}`（mode 缺失）** | **原本放行 → 已修复为拒绝** |
| 9 | 拒绝信息包含 mode 名 | 通过 |

### 关键发现 4：fail-open 缺陷（已修复）

**原始实现**：

```ts
const mode = spec.sandboxPolicy?.mode
if (mode !== undefined && mode !== 'danger-full-access' && spec.argvConfined !== true) { throw … }
//  ↑ 这个前置条件让 sandboxPolicy: {} 直接放行
```

`sandboxPolicy` 存在但 `mode` 为 `undefined` 时，守卫**静默放行**——正是它本该防止的"策略静默失效"。

**修复**（`qvd-2026-52646-confined-spawn-fail-closed.patch`）：改为 fail-closed——**policy 一旦存在，只有字面 `danger-full-access` 才豁免**。

**严重度评估（诚实）**：`SubprocessSpawnSpec.sandboxPolicy.mode` 在类型上必填，所以这是**类型系统之外的输入**。它不是可被远程触发的漏洞，而是**纵深防御的缺口**：守卫存在的意义就是兜住"调用方忘了"的情况，而它在这个形状上没兜住。

---

## 三、Agent Loop 重复输出（Model / Harness 分离）

测试文件：`packages/core/agent-loop/tests/redteam-loop-termination.spec.ts`
结果：**4 通过 / 0 失败**

### 观察到的现象

```
好。 → 执行。 → 好。 → （输出。） → 好。 → 执行。 → …
```

### 代码路径（逐行核对）

`packages/core/agent-loop/src/agent.ts`：

- L227 `while (await this.turn()) {}` — 外层 turn 循环
- L286 `while (true)` — 内层 step 循环
- L319 `if (turnEnds && this.inbox.nextStep.length === 0) break` — 正常退出
- L486-492：
  ```ts
  const toolCalls = message.content.filter(block => block.type === 'tool-call')
  if (toolCalls.length === 0) return { kind: 'completed' }   // 无工具调用 → turn 结束
  const { concluded } = await executeToolCalls(…)
  return concluded ? { kind: 'completed' } : null            // 有工具调用未结束 → 继续
  ```

### 实测（scripted adapter = raw model output）

| 模型输出 | 实际请求次数 | 结论 |
|---|---|---|
| 纯文本 `好。` | **1** | loop 正确终止 |
| 纯文本 `执行。` | **1** | loop 正确终止 |
| 2 次工具调用 + 文本 | **3** | 按预期循环 |

### 结论

**Agent Loop 的终止逻辑是正确的。** 模型返回纯文本（无 tool-call block）时 `step()` 返回 `{kind:'completed'}`，turn 立即结束，**不会再次请求模型**。

因此该重复**不是** Harness 状态机缺陷，而是**模型侧生成异常**（raw model output 本身在重复）。

### 真实缺口：没有守卫覆盖纯文本重复

- `packages/guard/repeat-tool-reminder` 挂在 `tools/post-execute`（`src/index.ts:213`），**只在有工具调用时触发**
- 全仓搜索确认**不存在文本级循环检测**（`packages/guard` 仅 `repeat-tool-reminder` 与 `timeout-policy`）

**建议方向（明确反对字符串黑名单）**：在 turn 边界对连续 step 的 assistant 文本做**状态环检测**（相似度/重复度），而非匹配特定词；或增加 turn 级迭代上限。触发后走正常终止路径（`turn/end` 带 reason），而非静默丢弃。

---

## 四、回归测试

| 套件 | 结果 |
|---|---|
| `fs-sandbox` 全部（含红队） | 通过 |
| `subprocess-local` 红队 | 13/13 通过 |
| `agent-loop` 红队 | 4/4 通过 |
| `cordis-host-runner`（含插件 fs 围栏） | 98 通过 |
| `client/connection`（含传输围栏） | 164 通过 |
| 全量构建 | exit 0 |

### 预先存在的失败（与本补丁无关，已核实）

`packages/subprocess/subprocess-local/tests/spawn-runner.spec.ts` 有 2 个失败：

- `contains cleanup failures and removes a substituted symlink only`
- `resolves Windows executables with target-cwd and PATH search semantics`

**根因**：`EPERM: operation not permitted, symlink` —— 与第一节相同的 Windows 权限限制。

**核实方法**：把我的 `spawn.ts` 改动临时还原后重跑，**这 2 个失败依旧存在**，证明与本次补丁无关。

---

## 五、2026-09-26 实测（0.1.7-rc.2 轮次）

测试日期：**2026-09-26**。目标：本地 **0.1.7-rc.2** 检出 + 本轮 `fixes-0.1.7-rc.2.patch`。平台同上（Windows 11 x64，非管理员）。

> 口径：本节四组结果来自**源码标记核对 + 针对性驱动**。**`apps/web` 的浏览器 e2e（`DSH_SNAPSHOT=replay pnpm run test:web`）没有跑**（见第七节）。

### 1. `run_code` 逃逸（新架构）

| 探针 | 修复前 | 修复后 |
|---|---|---|
| `console.log.constructor('return process.pid')()` | 返回**宿主 pid** | `console.log.constructor is not a function` |

- **原理**：注入 vm realm 的宿主对象自带可回到宿主 realm 的 `constructor`；修复后 console shim、每个 namespace 绑定、binding error class **全部**经 `detachedHostSurface()`（null 原型包装 + `Reflect.construct` 保留 `new` + `WeakSet` 防环）包装。
- **证据**：`packages/ptc-runtime/ptc-runtime-node/src/bootstrap.ts` 中 `detachedHostSurface` 的定义与三处调用。
- **边界（如实记录）**：封的是**这一条逃逸面**；`shell` / `pwsh` 的进程级读面在本轮**未修**。

### 2. cookie 伪造（链 F 方向）

| 探针 | 结果 |
|---|---|
| token→cookie 交换：伪造 Host + peer 非 loopback | **拒绝**（peer 判据，2026-09-23 轮次引入） |
| duplicate Host（`rawHeaders` 里两个 Host 字段） | **拒绝**（本轮新增 `host-repeated`） |
| Host 与请求自身权威不一致 | **拒绝**（本轮新增 `host-authority-mismatch`） |

- 本轮新增的是**结构化拒绝 code**；**code 未进 HTTP 响应体**（对外仍是状态码 + 简短文本）—— 这是残留，不是已完成项。
- 凭据（浏览器会话签名密钥）经 `read` / 搜索栅栏 / fs-sandbox **已不可读**（任何模式，含 `danger-full-access`，错误码 `FS_PERMISSION_DENIED`）；但 `shell` / `pwsh` 起动子进程后**仍可读**。即：链 F 的「读密钥 → 伪造 cookie」一步，**进程内读面被堵住，shell 通道仍然敞开**。

### 3. `/plugins/events` 未认证

| 探针 | 修复前 | 修复后 |
|---|---|---|
| 未认证 GET `/plugins/events` | 可读到 plugin graph 的 SSE 帧 | **401**，且**不写任何帧** |
| 异 Host / rebound 请求 | 同上 | **403**（在查找 bundle 之前就拒绝） |
| 无 Connection 的装配 | —— | 403，通道 fail-closed 关闭 |

- **证据**：`packages/client/hmr/src/index.ts` 中 `browserTrustFence` + `requestRejection` 的调用位于 `connect(res)` **之前**；对应用例「refuses an unfenced or untrusted /plugins/events request and streams the graph to nobody」。
- 同一围栏也接在 `/plugins`（bundle 路由）上：`packages/client/modules/src/index.ts`。

### 4. 上游 A/B 对照（官方 0.1.7-rc.2）

| 本轮修复点 | 官方 0.1.7-rc.2 |
|---|---|
| `grep` / `glob` 搜索根不传策略 | **未修** |
| `$DSH_HOME/.credentials*` 经模型可读面可读 | **未修** |
| `/api/file` 没有读根白名单 | **未修** |
| `/api/session.export` 没有工作区绑定/鉴权 | **未修** |
| `/plugins`、`/plugins/events` 没有信任围栏 | **未修** |
| duplicate Host / Host 与权威不一致 | **未修** |
| `run_code` 宿主对象泄漏 | **架构已换**（`ptc-runtime-node`），旧 PoC 不再适用；本轮的 `detachedHostSurface` 是在新架构之上补的 |

> 结论与 0.1.5 轮次一致：**升级官方版本不等于修好漏洞**。本轮 7 项里官方对 6 项**一条都没修**，第 7 项（`run_code`）只是换了架构。

---

## 六、已知绕过汇总

| 绕过 | 影响 | 状态 |
|---|---|---|
| **硬链接读取工作区外 inode** | 需先有工作区写权限；同卷敏感文件可被读取 | **未修复**（路径栅栏的固有边界） |
| 无 policy 的读取透传 | 宿主契约；插件面已由 `cordis-host-runner` 围栏覆盖 | 设计如此 |
| `danger-full-access` 不设栅栏 | 该模式语义即"无限制" | 设计如此 |
| 进程级沙箱读面（bwrap/landlock/seatbelt） | read-only 会话的 shell 仍可读宿主文件 | **deferred**（需 Linux/macOS 验证） |
| 52631 env 全量投影 | `!!js process.env.X` 可读任意环境变量 | **未修复**（需按配置来源分层投影） |
| 凭据经 `shell` / `pwsh` 可读 | 受限 shell 仍是进程级全盘只读面 | **未修复**（2026-09-26 轮次未动） |
| 读侧「放宽一次」审批入口 | `read` / `glob` / `grep` schema 无 `sandbox_permissions` | **缺失**（提示与能力面不一致） |
| `/api/file` 读根不可配置 | `Config.roots` 只有直接挂载才能设 | **未修复**（随附组合未暴露到 `cordis.yml`） |
| `session.export` 多实例区分 | 身份只到「部署」层；后代日志未逐个复检 | **未修复** |
| 结构化拒绝 code 进响应体 | 已导出，未进 HTTP body | **未实现** |
| `apps/web` e2e | `DSH_SNAPSHOT=replay pnpm run test:web` | **未跑**（未验证） |

---

## 七、尚未验证（Unknown / Not Verified）

- loader `!!js` vm 隔离的绕过尝试（未做）
- 真实模型（非 scripted adapter）下的重复输出复现
- 跨卷硬链接行为（硬链接不能跨卷，但未实测确认）
- TOCTOU：栅栏检查与读取之间的路径替换窗口（未做并发测试）
- Linux/macOS 上的进程级沙箱后端行为

> 本报告不把 `Not Tested` 写成 `Secure`，也不把 `Attack Not Observed` 写成 `Attack Impossible`。
