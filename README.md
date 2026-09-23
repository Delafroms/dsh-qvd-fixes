# DeepSeek Harness QVD 安全修复补丁、红队测试与验证脚本

[English](README.en.md) | 简体中文

| 项目 | 值 |
|---|---|
| Target（目标版本） | DeepSeek Harness **0.1.2-alpha.2**（基线）+ **0.1.5-rc.2**（补充补丁） |
| Status（性质） | Community patch（社区补丁，非官方） |
| Scope（源码修复范围） | QVD-2026-52631 / 52632 / 52644 / 52646 |
| Partially-fixed（部分修复） | QVD-2026-57410 |
| 对抗验证 | 33 个红队用例（3 个套件） |

## 30 秒版

| 问题 | 答案 |
|---|---|
| 这是什么 | DeepSeek Harness 公开漏洞的**社区补丁 + 对抗测试 + 验证脚本**。非官方，非完整审计 |
| 我该用哪个 | **0.1.5-rc.2 → `fixes-0.1.5-rc.2.patch`（单一补丁，一条命令）**；0.1.2-alpha.2 → `fixes.patch` |
| 怎么装 | 跑 `apply-dsh-fixes.bat`（先 `--check` 预检、再询问、后写入），或手动 `git apply --check` → `git apply` |
| 装完怎么验 | 跑 `verify-dsh-fixes.bat`（只读、不联网），再用 `-tests` 跑回归 |
| 修了什么 | 52631 / 52632 / 52644 / 52646 四个漏洞有源码修复；57410 由上游 token 部分修复，本仓库补 TCP peer 判据 |
| 还有什么没修 | 硬链接绕过、进程级沙箱读面、52631 的 env 全量投影 —— 见 [REDTEAM.md](./REDTEAM.md)「已知绕过汇总」 |
| 我不该期待什么 | 它**不解决间接提示注入**，也**不保证没有其它未发现的问题**；升级官方版本前请先看 [FIXES.md](./FIXES.md) |

本仓库提供针对 DeepSeek Harness 公开披露漏洞的**社区补丁**、**对抗测试**与验证脚本。

- **基线补丁**（`fixes.patch`）基于上游 **0.1.2-alpha.2**，修复 52631 / 52632 / 52644 / 52646 四个漏洞。
- **补充补丁**（5 个）针对 **0.1.5-rc.2**：上游在 0.1.2 → 0.1.5 的三个版本区间里**没有修复任何一个 QVD**，且 57410 只被**部分**修复。补充补丁闭合了残留面与红队发现的新缺陷。
- **红队套件**（33 个用例）主动尝试绕过本仓库自己的补丁，结果与已知绕过见 [REDTEAM.md](./REDTEAM.md)。

> 本仓库**不是官方安全更新，也不是完整安全审计**；不保证不存在其它未发现、未覆盖或与版本相关的安全问题。**已知绕过与未验证边界在 `REDTEAM.md` 中明确列出，未隐藏。**

## Quick Start

**基线（0.1.2-alpha.2）：**

1. 确认你的 DSH 检出基于 **0.1.2-alpha.2**；
2. 下载 `fixes.patch` 与 `verify-dsh-fixes.bat`；
3. 运行 `verify-dsh-fixes.bat` 查看当前修复状态；
4. `git apply --check fixes.patch` 补丁预检；
5. 确认无误后 `git apply fixes.patch` 应用。

**补充补丁（0.1.5-rc.2）：** 见下方[「0.1.5-rc.2 补充补丁」](#015-rc2-补充补丁)。

## 目录内容

| 文件 | 说明 |
|---|---|
| `fixes.patch` | 相对 0.1.2-alpha.2 的统一 diff，修复 52631/52632/52644/52646（15 个文件，+668 / −44）。**注意：其中的 `assertConfinedUnderPolicy` 是带 fail-open 缺陷的旧版本，在 0.1.5 上必须叠加补充补丁 4** |
| `fixes-0.1.5-rc.2.patch` | **0.1.5-rc.2 一键补丁（2026-09-23 新增，推荐）**：把基线 + 5 个补充补丁的最终效果合并为**单一自洽 diff**（48 文件，+2114 / −74）。**0.1.5-rc.2 用户请优先用它**，不要再用「基线 → 补充补丁」的分步流程 |
| `code-runtime-isolation.patch` | 零日修复：`run_code` 代码运行时的沙箱隔离缺口（见下文「未公开发现」）。**尚未上报上游，暂不建议公开分发** |
| `apply-dsh-fixes.bat` | 一键应用脚本：定位检出 → `--check` 预检 → 确认后应用（零日补丁单独二次确认） |
| ~~5 个分项补丁~~ | **已并入 `fixes-0.1.5-rc.2.patch` 并从仓库移除**（2026-09-23）；逐项设计说明保留在 `FIXES.md` 与本文历史章节 |
| `redteam-suites.patch` | 33 个红队对抗用例（3 个套件） |
| `ATTACK-CHAIN.md` | **攻击链与阻断点**：7 条链逐项映射到补丁与用例，含交叉表 |
| `REDTEAM.md` | 红队报告：攻击结果、已知绕过、未验证边界 |
| `FIXES.md` | 每个漏洞的逐项说明、涉及文件、应用与验证方法 |
| `verify-dsh-fixes.bat` | Windows 只读验证脚本（20 项检查，可选回归测试/重建） |
| `README.md` | 本说明 |
| `LICENSE` | MIT 许可 |

> **关于文中出现的 `qvd-2026-*.patch`**：这 5 个分项补丁已于 2026-09-23 并入 `fixes-0.1.5-rc.2.patch` 并**从仓库移除**。下文对它们的引用保留作**审计记录**（说明每条链当初是怎么被掐断的），文件本身不再分发。

## ⚠️ 安全与责任声明

- `verify-dsh-fixes.bat` 是**只读验证脚本**：不联网、不下载、不执行任何外部程序、不修改你的系统；可选 `-tests` / `-build` 只调用你自己机器上的 `pnpm`，且需手动输入 `Y` 确认。
- `fixes.patch` 是否应用由你决定：`git apply fixes.patch` 会修改 DSH 源码，请先 `git apply --check` 校验并自行备份。
- 本仓库内容按 **AS-IS** 提供；MIT 许可自带免责（见 `LICENSE`），作者对使用后果不承担责任。请先在测试环境核对。
- 本仓库**与 DeepSeek 官方无关**，不是官方修复或官方发布；以上游官方仓库为准。

## 五个漏洞

| QVD | CVSS | 本仓库处理 |
|---|---|---|
| QVD-2026-52646 | 10.0（严重） | 源码修复 + **fail-closed 加固**（红队发现） |
| QVD-2026-57410 | 9.8（极危） | **部分修复**：上游加了 token，本仓库补 TCP peer 判据 |
| QVD-2026-52644 | 高危（官方未给出具体数值） | 源码修复 |
| QVD-2026-52631 | 7.8（高危） | 源码修复（**env 投影面未闭合**，见下） |
| QVD-2026-52632 | 7.5（高危） | 源码修复（**含进程级读面与硬链接绕过残留**） |

> 分值来源：奇安信 CERT 披露及 CN-SEC 转述。52644 官方仅标注"高危"、未给出具体数值，此处不臆造数字。

### QVD-2026-52631 — loader 配置表达式注入（CVSS 7.8）
- **成因**：loader 对 `cordis.yml` 里的 `!!js` 表达式用 `with (ctx) { eval(expr) }` 包在 `new Function` 中求值；表达式经 `ctx` 落到宿主全局作用域，可拿到 `process` / `require` / `module`。
- **后果**：攻击者一旦把恶意 `!!js` 写进 `cordis.yml` / `cordis.patch.yml`（例如诱导克隆恶意仓库、应用被篡改的 profile），配置加载时即以宿主进程权限**同步执行任意 Node 代码**——读取文件、执行命令、窃取环境变量中的 API 密钥，并可借 HMR 监听形成"写入即执行、每次启动重放"的持久后门。前提：攻击者需先能投递或写入恶意配置，非远程一键触发。
- **修复**：改为 `node:vm` 隔离求值；上下文以单个 JSON 字符串注入并在 vm 内重建（宿主对象零注入）；`process` 只暴露 `env/platform/arch/version/execPath/cwd` 与 `getBuiltinModule('node:url')`；`runInContext(..., { timeout: 1000 })` 限时。
- **残留（未闭合，架构限制）**：vm 内的 `process.env` 是**全量投影**（`env: process.env`），`!!js process.env.<KEY>` 可读取任意环境变量。vm 内无网络与文件系统，但可通过抛错把值带进错误信息（日志 / UI 可见），构成完整的信息泄露链。
  **威胁模型比原描述更严重**：不只需要"诱导用户粘贴配置"——**安装一个第三方插件就足以投递**（bundle 层的 `cordis.patch.yml` 来自 npm 包，同样能写 `!!js`）。
  **为什么本仓库无法修复**：按配置来源分层投影需要来源信息，而它在 `composeEntries` 的 `layers.flat()` 处被丢弃（`EntryOptions` 无来源字段）。要保留需跨三个包改数据结构，**改错会让整个 profile 组合失效、DSH 起不来**。这需要上游引入「配置来源信任」模型。详见 `FIXES.md`。

### QVD-2026-52632 — fs-sandbox 读逃逸（CVSS 7.5）
- **成因**：`fs-sandbox` 只约束了写入，读取可越过工作区读取任意路径。
- **后果**：信息泄露。进程内面：模型可读取工作区之外的任意路径；进程级面：受限 shell 子进程可读整个宿主文件系统。攻击者可窃取 `~/.ssh` 私钥、`.env`、云凭据、API 密钥及其它项目源码。它不直接写文件或执行命令，但泄露的凭据可被用于横向移动或进一步入侵。
- **修复**：读方法（`readText` / `streamText` / `readBytes`）在执行点按策略校验目标；越界抛结构化 `FS_SANDBOX_DENIED`；`tool-fs` 读前解析会话策略并传入，denial 经 `mapError` 映射。
- **补充修复**：
  - `qvd-2026-52632-editor-read-fence.patch` —— `tool-str-replace-editor` 的 `view` 命令此前读文件**不带策略**（写路径本来就有），已补上。
  - `qvd-2026-52632-plugin-fs-fence.patch` —— 动态 Cordis 插件经 `inject: ['fs']` 拿到的 fs 服务，**读路径**在无 policy 时透传（写路径已默认 `resolve()`，**这个读写不一致本身就是缺陷**）。围栏加在**动态插件进入系统的边界**（`sandboxContext` 门面），**不改宿主契约**。
- **已知残留（未修复）**：
  1. **进程级读面**：bwrap `--ro-bind / /`、landlock `readOnly: ['/']`、seatbelt allow-default 仍把整个宿主只读暴露给受限 shell 子进程。只读会话里的 bash/pwsh 仍可能读取 `~/.ssh`、`.env` 等。**deferred — requires platform-specific validation**（需 Linux/macOS 验证后端）。
  2. **硬链接绕过**（红队实测确认）：工作区内指向外部 inode 的硬链接，**路径判定无法察觉**，读取成功。利用前提是攻击者**已能在工作区创建硬链接**（已有写原语），故属限制而非独立漏洞。**缓解**：敏感文件不要放在与工作区同一卷（硬链接不能跨卷）。
  详见 `REDTEAM.md` 与 `FIXES.md`。

### QVD-2026-52644 — cordis 沙箱工具逃逸（CVSS 高危）
- **成因**：沙箱内自定义工具的 `execute` 拿到的执行上下文携带真实的 `agent` / `ctx` / `session` 等对象。
- **后果**：沙箱逃逸的关键一环。模型代码经 `exec.agent.ctx` 拿到真实运行时 Context，从"受限 vm 代码执行"升级为"访问宿主服务（含秘密存储）"。它通常作为攻击链的一步，与 52646 串联后达成宿主机 RCE。
- **修复**：新增 `sandboxToolExec` 白名单执行视图，仅含 `name` / `callId` / `arguments`（JSON clone）/ `signal`。

### QVD-2026-52646 — bash/pwsh 子进程逃逸（CVSS 10.0）
- **成因**：受限策略下 bash/pwsh 仍可直接 spawn 子进程，绕过沙箱。
- **后果**：最严重的一条，链式达成**宿主机任意命令执行**。完整链路：间接提示注入 → 诱导模型调用 `cordis_define` + `cordis_run` → vm 逃逸取得宿主 exec → 无约束 `subprocess.spawn` → 以 DSH 进程的权限执行任意命令（公开演示可达 root）。默认组合下不依赖任何部署配置失误。
- **修复**：`SubprocessSpawnSpec` 增加 `sandboxPolicy` 与 `argvConfined`；受限策略未声明 `argvConfined` 即拒绝启动；`bash-local` / `pwsh-local` 在受限时 stamp `argvConfined: true`。
- **补充修复（红队发现）**：`qvd-2026-52646-confined-spawn-fail-closed.patch` —— 原守卫的 `mode !== undefined` 前置条件让 `sandboxPolicy: {}`（policy 存在但 mode 缺失）**静默放行**，正是守卫本该防止的"策略静默失效"。已改为 fail-closed：**policy 一旦存在，只有字面 `danger-full-access` 才豁免**。
  **严重度（诚实评估）**：`mode` 在类型上必填，这是**类型系统之外的输入**，不是可远程触发的漏洞，而是**纵深防御的缺口**。

### QVD-2026-57410 — 未授权访问 / 伪造 Host（CVSS 9.8，**部分修复**）
- **成因**：管理 RPC 仅通过 **HTTP `Host` 请求头**判断请求是否来自本机回环地址；而 `Host` 完全由客户端构造、可任意伪造。
- **后果**：**远程未认证 RCE**。攻击者伪造 Host 头解锁高权限 RPC，注册一个指向自身假模型服务器的临时 LLM 提供者，用确定性工具调用驱动 bash 工具——**无需真实模型、无需有效 API 密钥**，即可对暴露到公网的实例执行命令（公开 PoC 可拿下 root shell）。前提：服务暴露到非 loopback 网络；仅 `127.0.0.1` 本地监听不受此路径直接威胁。
- **上游处理（部分）**：0.1.2+ 已内置 browser-token 会话鉴权（launch token + 签名 cookie + 401/403 门禁）。
- **残留（本仓库补充修复）**：信任判断**仍无 TCP 层输入**——`ConnectionTrustRequest` 只携带 `headers`，且 `BrowserAuth.authorizeIndex`（token → cookie 交换）**完全没有 peer 校验**。上游 PoC 给出的修复建议原文就是「校验 TCP `remoteAddress` 而非 `Host` 头」，未被采纳。
  **含义**：token 成为唯一防线。token 一旦泄露（URL 进日志、Referer、截图、被分享的链接），伪造 `Host: 127.0.0.1` 即可换取浏览器 cookie。
- **补充修复**：`qvd-2026-57410-transport-fence.patch` —— 新增**传输围栏**（Host 声称 loopback 而 peer 不是 loopback → 拒绝），并给 token 交换加 peer 校验；新配置 `trustedProxies`（默认空 = 最严格）。

## 运行 verify-dsh-fixes.bat 会发生什么

脚本逻辑固定，行为可预期：

- **只读检测**：用 `findstr` 逐个比对源码中的修复标记，输出 `[PASS]` / `[FAIL]` / `[SKIP]` 与汇总。
- **两类检查**：
  - **基线项**（11 项）：缺失记 `[FAIL]`，计入退出码；
  - **可选补充补丁 + 红队套件**（9 项）：缺失记 `[SKIP]`，**不计入 FAIL**——补充补丁是可选增量，未应用不代表基线有问题。
- **三种结果**：
  1. 定位到检出且基线修复齐全 → 基线项全 `[PASS]`，退出码 0；
  2. 定位到检出但缺基线修复 → 对应项 `[FAIL]`，退出码 1（只输出信息，不改文件）；
  3. 未定位到检出 → 提示"未找到检出根目录"，退出码 2（无副作用）。
- **定位规则**：脚本所在目录含 `package.json` 即视为检出根；否则读环境变量 `DSH_REPO`；再否则向上两级查找。
- **可选 `-tests` / `-build`**：需手动输入 `Y` 才执行，且调用的是**你自己机器上的 `pnpm`**（跑 DSH 回归测试 / 重建）。未安装 `pnpm` 或依赖时会报错退出，不产生破坏。
- 全程**不联网、不上传、不下载、不执行外部程序**。

> **静态检测的边界（重要）**：`[PASS]` 只代表**修复标记字符串在位**，不代表逻辑正确——被注释掉的代码同样含该字符串。真正的证据是 `-tests` 跑的回归测试与 `REDTEAM.md` 记录的对抗结果。

## 应用 fixes.patch 会发生什么

```bat
git apply --check fixes.patch   rem 校验，不实际修改
git apply fixes.patch           rem 确认后应用
git apply -R fixes.patch        rem 撤销（反向应用）
```

- 版本匹配（0.1.2-alpha.2 且结构一致）→ 修改 15 个源码文件；
- 版本不匹配 → `git apply` 校验失败、**不写入任何文件**；
- 补丁以 LF 行尾生成；Windows 下若本机检出为 CRLF 导致 `does not apply`，改用 `git apply --ignore-whitespace fixes.patch`。

## 使用步骤

1. 验证：把 `verify-dsh-fixes.bat` 放到 DSH 检出根目录运行（或 `set DSH_REPO=路径` 后运行）。
2. 需要回归测试或重建：`verify-dsh-fixes.bat -tests` 或 `-build`（需本机已装 `pnpm` 与依赖）。
3. 应用修复：在基于 0.1.2-alpha.2 的检出上 `git apply --check fixes.patch` → `git apply fixes.patch`。

## 0.1.5-rc.2 一键安装（推荐）

> **⚠️ 2026-09-23 更正：`fixes.patch` 在干净的 0.1.5-rc.2 上打不上。**
>
> 实测（`git archive` 导出的干净树）有 5 个文件报 `patch does not apply`：
> `packages/fs/fs/src/index.ts`、`packages/fs/tool-fs/src/read.ts`、`packages/fs/tool-fs/src/read-image.ts`、
> `packages/subprocess/subprocess-local/src/spawn.ts`、`packages/subprocess/subprocess-local/tests/spawn.spec.ts`。
> 原因是 0.1.2 → 0.1.5 之间上游改了这些文件的注释与代码（例如 `read.ts` 的注释多了 "scope-aware" 一词），
> **不是行尾问题**（`--ignore-whitespace` 与 `-C1` 均无效）。本仓库此前「在 0.1.5-rc.2 上按序应用基线 → 补充补丁」的说明与事实不符，特此更正。

**0.1.5-rc.2 请改用单一补丁：**

```bat
rem 在干净的 0.1.5-rc.2 检出上
git apply --check fixes-0.1.5-rc.2.patch
git apply       fixes-0.1.5-rc.2.patch
```

或直接运行一键脚本 `apply-dsh-fixes.bat`（先预检、再询问、后写入）。

**它和「基线 + 补充补丁」的关系**：内容等价（基线 + 5 个补充的最终效果），但**单一自洽** —— 不会再出现「只打了基线、装上一个带 fail-open 缺陷的守卫」这种事故。`fixes.patch` 与 5 个补充补丁**保留**，供 0.1.2-alpha.2 用户与历史审计使用。

## 0.1.5-rc.2 分项补丁说明（已并入单一补丁 · 保留作审计记录）

> **2026-09-23：下列 5 个分项补丁已并入 `fixes-0.1.5-rc.2.patch`，并从仓库移除。**
> 本节保留它们的设计说明与 0.1.5-rc.2 复核证据作为审计记录；其中的 `git apply` 命令已作废。

> **⚠️ 先读这段：`fixes.patch` 与补充补丁的目标版本不同，不能互相替代。**
>
> | 补丁集 | 目标版本 | 说明 |
> |---|---|---|
> | `fixes.patch` | **0.1.2-alpha.2** | 相对该版本的统一 diff（15 文件） |
> | 5 个补充补丁 | **0.1.5-rc.2** | 各自独立，**不能合并进 `fixes.patch`** |
>
> **为什么不能合并**：`fixes.patch` 是相对 0.1.2-alpha.2 生成的 diff；把 0.1.5 的内容并进去，它在 0.1.2 上就应用不了了。
>
> **⚠️ 在 0.1.5-rc.2 上必须"基线 → 补充补丁"按序应用，不能只打基线。**
> 原因：`fixes.patch` 里的 `assertConfinedUnderPolicy` 是**带 fail-open 缺陷的旧版本**（`mode !== undefined` 前置条件让 `sandboxPolicy: {}` 静默放行）。**只应用基线会装上一个有缺陷的守卫**；补充补丁 4 才是 fail-closed 版本，且它会**覆盖**基线写入的同一函数。

把基线补丁迁移到 **0.1.5-rc.2**（当前 npm `latest`）后，对五个 QVD 的公开 PoC 攻击面做了**逐项复核**：

| QVD | 0.1.5-rc.2 状态 | 证据 |
|---|---|---|
| 52631 配置加载 RCE | 仍未修 | `vendor/loader/src/config/utils.ts:5` 依旧是 `new Function + with(ctx){eval}` |
| 52632 只读沙箱泄露 | 仍未修 | `fs-sandbox/src/index.ts:7` 自述 "Reads pass through untouched" |
| 52644 VM 沙箱逃逸 | 仍未修 | `guard.ts` 把 `exec` 原样透传给 `rawExecute` |
| 52646 链式逃逸 RCE | 仍未修 | `spawn.ts` 无 `argvConfined` / `assertConfinedUnderPolicy` |
| 57410 Host 头未授权 RCE | **部分修复** | 加了 token，但信任判断仍无 TCP 层输入 |

> **升级版本不等于修好漏洞。** 基线补丁在 0.1.5-rc.2 上**不是历史包袱而是必需品**。

**应用方式（已作废）**：这 5 个分项补丁已于 2026-09-23 并入 `fixes-0.1.5-rc.2.patch` 并从仓库移除。

下表保留为**设计记录** —— 它说明了为什么必须用单一补丁：基线与 fail-closed 补丁改的是**同一个函数**，分开应用会出现"只打了基线、装上带 fail-open 缺陷的守卫"的窗口。

| 补充补丁 | 与基线的关系 |
|---|---|
| `qvd-2026-52646-confined-spawn-fail-closed.patch` | **覆盖**基线写入的 `assertConfinedUnderPolicy`（旧版有 fail-open 缺陷） |
| `qvd-2026-52632-plugin-fs-fence.patch` | **扩展**基线改过的 `guard.ts`（基线只加 `sandboxToolExec`） |
| 其余 3 个 | 与基线不重叠，纯增量 |

补丁以 LF 生成；Windows 检出若为 CRLF 导致 `does not apply`，加 `--ignore-whitespace` 重试。

## 红队测试（对抗验证）

完整报告见 **[REDTEAM.md](./REDTEAM.md)**。摘要：

| 套件 | 用例数 | 结果 |
|---|---|---|
| 读栅栏对抗 | 16 | **14 阻断 / 1 已知绕过（硬链接） / 1 现状**（`danger-full-access` 语义即无限制） |
| 受限 spawn 对抗 | 13 | 13 阻断（修复 fail-open 后） |
| Agent Loop 终止性 | 4 | 4 通过 |
| **合计** | **33** | |

**Agent Loop 重复输出的结论**：经 Model/Harness 分离实测，模型返回纯文本（无 tool-call block）时 loop **只请求 1 次即终止**——终止逻辑正确，**不是 Harness 状态机缺陷**。真实缺口是**没有任何守卫覆盖纯文本重复**（`repeat-tool-reminder` 只挂在 `tools/post-execute`，需有工具调用才触发）。`guard-repeat-text-reminder.patch` 补上了这一层。

**测试环境**：Windows 11 x64、非管理员账户。所有攻击只在临时目录、测试文件、Canary 与 Mock Sink 上进行，**无外部副作用**。

### 已知绕过汇总（不隐藏）

| 绕过 | 影响 | 状态 |
|---|---|---|
| **硬链接读取工作区外 inode** | 需先有工作区写权限；同卷敏感文件可被读取 | **未修复** |
| 无 policy 的读取透传 | 宿主契约；插件面已由 `sandboxContext` 围栏覆盖 | 设计如此 |
| `danger-full-access` 不设栅栏 | 该模式语义即"无限制" | 设计如此 |
| 进程级沙箱读面 | read-only 会话的 shell 仍可读宿主文件 | **deferred** |
| 52631 env 全量投影 | `!!js process.env.X` 可读任意环境变量 | **未修复（架构限制）** |

### 尚未验证（Unknown / Not Verified）

- loader `!!js` vm 隔离的绕过尝试
- 真实模型（非 scripted adapter）下的重复输出复现
- TOCTOU：栅栏检查与读取之间的路径替换窗口
- Linux/macOS 上的进程级沙箱后端行为

> 本仓库不把 `Not Tested` 写成 `Secure`，也不把 `Attack Not Observed` 写成 `Attack Impossible`。

## 本补丁不覆盖：间接提示注入

间接提示注入（Indirect Prompt Injection）是**模型层面**的固有风险，**代码补丁无法消除**。腾讯朱雀实验室 14,560 次受控实测（2026-08）显示，DSH 在基线配置下对这类攻击的防御仍在早期阶段（完全成功约 5.3%）：网页、文档、邮件、Skill、PDF 元数据、隐藏 Unicode 等不可信内容，都可能诱导模型调用敏感工具。

本补丁只闭合五个 QVD 对应的代码/沙箱/鉴权漏洞，**不解决提示注入**。缓解只能靠运行习惯：外部内容一律按不可信处理、敏感操作留人审批、最小权限运行、在独立容器/VM 中处理不可信内容。

参考：腾讯朱雀实验室《A.I.G 红队实测 DeepSeek Harness》https://matrix.tencent.com/zh/2026/08/20/deepseek-harness-agent-injection-risk

## 未公开发现：`run_code` 代码运行时隔离缺口（已提供修复，尚未上报上游）

> **状态：未上报上游、未定级。** 本节只描述影响与修复，**不含可直接复现的攻击步骤**。

- **影响**：`packages/code-runtime/code-runtime-worker-thread` 把模型代码交给 worker 的**全局作用域**执行（`AsyncFunction`），而该运行时**不接收会话沙箱策略**。
- **实测对照**：同一会话、同一 `workspace-write` 策略下，`read` / `write` 工具与 `pwsh` 子进程对工作区外路径**全部被拒**，而 `run_code` 仍可读写工作区外文件、导入 `node:child_process`。
- **零前置**：不需要网络暴露、令牌、Host 伪造、插件，也不需要模型越狱。
- **修复**：`code-runtime-isolation.patch` —— 改用 `node:vm` 上下文执行程序体，禁用字符串代码生成（`codeGeneration: { strings: false, wasm: false }`），且**不提供** `importModuleDynamically` 回调；定时器以 null-prototype 包装注入（避免经 `.constructor` 回到宿主 realm）。
- **验证**：`await import('node:fs')` 被拒（`ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING`）；`process` / `fetch` / `require` 不可见；`Function` 构造器与 `eval` 抛 `EvalError`；正常功能（顶层 await、绑定调用、console 捕获、异常路径、返回对象/数组）不受影响。
- **已知边界（如实记录）**：跨 realm 的异常只保留 message、**丢失堆栈**；`vitest` 全量回归**未在本机跑通**（沙箱下 vite 的管道 `exec` 报 `spawn EPERM`），验证用的是直接驱动 `bootstrap.ts` 的针对性脚本。
- **披露建议**：先交上游审核，再决定是否公开分发本补丁。

## 安全建议

- **插件即代码**：不要加载来源不明、未经审查的插件；它们在宿主进程内执行。
- **网页/搜索内容不受信任**：对"抓取网页 / 搜索"类工具返回的内容保持警惕，它可能诱导后续危险操作。
- **保持本地监听**：DSH Web 应只绑定 `127.0.0.1`，不要设为 `0.0.0.0` 暴露到局域网/公网。
- **只用官方来源**：从 DeepSeek Harness 官方仓库获取与更新代码。
- **优先升级官方修复版**：本补丁基于 0.1.2-alpha.2（补充补丁针对 0.1.5-rc.2）；官方后续版本可能已修复这些漏洞，以官方 changelog 为准。**但注意**：截至 0.1.5-rc.2，上游**一个 QVD 都没修**，57410 也只修了一半——升级不等于安全。
- **只读模式不保护敏感文件**：本补丁收窄了进程内读取，但进程级沙箱仍把整个宿主只读暴露给受限 shell；处理不可信内容时请把 `.ssh`、`.env`、云凭据等移出 agent 可读目录，**并确保它们与工作区不在同一卷**（防硬链接绕过）。
- **不要把 DSH Web 暴露到非 loopback**：57410 的残留面意味着 token 是唯一防线，而 token 可能经日志/截图/分享链接泄露。
- 应用补丁前先 `--check` 并在测试环境验证。

## 文件校验表（防篡改核对）

核对命令（大小写不敏感）：

```bat
certutil -hashfile "verify-dsh-fixes.bat" SHA256
certutil -hashfile "fixes.patch" SHA256
certutil -hashfile "FIXES.md" SHA256
certutil -hashfile "REDTEAM.md" SHA256
certutil -hashfile "LICENSE" SHA256
```

**基线与脚本：**

| 文件 | SHA-256 |
|---|---|
| `verify-dsh-fixes.bat` | `6A0D8ECBF5B216347713A73D14437B3813FC043A2DB55685DD570EE9B731CD5B` |
| `fixes.patch` | `727290C97B539F4988A83803A6B4AE5E9F44F10FC1DC5D8A0981F466D3F13D0E` |
| `FIXES.md` | `D332DB66BDB47ECF2F13BD492D8328242367D300E78B154653F750CD35EED3E5` |
| `REDTEAM.md` | `A2BEAC9074F55517376481EBE5B4E768D19E6C39F162389021BEE12E45A03DF1` |
| `LICENSE` | `B546772903BAEBAFB411FD4A5E1A5B91855659BF38C56165A7096712615C8AF9` |

**已移除的分项补丁（2026-09-23 并入单一补丁；哈希保留供审计）：**

| 文件 | SHA-256 |
|---|---|
| `qvd-2026-57410-transport-fence.patch` | `280BE449C172D1165FD8BCF87F87F198E20293382CD948A00DD57B32A558C612` |
| `qvd-2026-52632-editor-read-fence.patch` | `81A7766AB9385125F45537482C8CB8883A6226A59627E39D841FDE6348B28531` |
| `qvd-2026-52632-plugin-fs-fence.patch` | `9DAD56A2603ADEB3BEDCE64DBB1996380471D16F1616BFD93F5D8BAC4A5EBFDC` |
| `qvd-2026-52646-confined-spawn-fail-closed.patch` | `B930F5E4F1AF615F9983588101CF84ECF3A1CD55F8E83D031DFE563DAE17D6F3` |
| `guard-repeat-text-reminder.patch` | `F9FD48F9D74132DD6879F9920FDC108532566D0189A1FB5CDB3502FC10E848E3` |
| `redteam-suites.patch` | `07C023D9C9B9859DF713C6F1777041F48E4BC06112E2FEAF19119994B2D552EB` |

**0.1.5-rc.2 一键补丁与零日修复（2026-09-23 新增）：**

| 文件 | SHA-256 |
|---|---|
| `fixes-0.1.5-rc.2.patch` | `9A2FA061BE21B3BE4CFB98CD3F7ACCA0741C4DDBF71EF1503D6FF06BB9A4ABF5` |
| `code-runtime-isolation.patch` | `C85FC4E4318B638F8F6D83FFCF67B60CE21661E76032342865AEA32945E59C66` |
| `apply-dsh-fixes.bat` | 见 README 变更记录（脚本每次修改后重新公布） |

说明：
- README（`README.md` / `README.en.md`）不纳入哈希表：哈希值就写在 README 文件自身内部，无法用 README 自身内容证明它未被修改；请以其它独立文件为准。
- 脚本不做自我校验：把哈希写进自身会形成自指、且攻击者可连校验代码一起改，故采用"外部公布值 + certutil 手工核对"。
- 作者每次修改文件后需同步更新上表。

## 许可证与归属

- 本仓库的脚本与文档：MIT License，版权人 **Delafroms**，见 `LICENSE`。
- DeepSeek Harness 上游：MIT License（© 其作者）。补丁是对上游 MIT 源码的修改，分发时需保留上游版权声明并注明修改，不得将上游代码标为原创。
- 建议只分发本补丁与说明，不要整包上传整个 DSH 检出或 `node_modules`。

## 参考

- DeepSeek Harness 官方仓库：https://github.com/deepseek-ai/DeepSeek-Harness
- 逐项修复说明：见 `FIXES.md`
- **攻击链与阻断点：见 `ATTACK-CHAIN.md`**
- 红队测试报告：见 `REDTEAM.md`
- QVD PoC 集合：https://github.com/Unclecheng-li/poc-lab
- 腾讯朱雀实验室《A.I.G 红队实测 DeepSeek Harness》：https://matrix.tencent.com/zh/2026/08/20/deepseek-harness-agent-injection-risk
