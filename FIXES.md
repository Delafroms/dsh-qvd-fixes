# 修复改动清单（QVD）

> 定位：本补丁是**针对 0.1.2-alpha.2 的社区补丁**——4 个漏洞（52631 / 52632 / 52644 / 52646）有源码修改；57410 为该基线内已有修复的版本核验，未做改动。非官方安全更新，也非完整安全审计。

本清单与 `fixes.patch` 配套：`fixes.patch` 是相对 DeepSeek Harness **0.1.2-alpha.2**（修复前基线）的统一 diff，可对任意基于该版本的检出执行：

```bat
git apply --check fixes.patch   rem 校验（不实际应用）
git apply fixes.patch           rem 应用
```

> `git apply` 会修改 DSH 源码——若你只想先核对，请用 `--check`；应用前建议备份或先 `git stash`。
>
> 补丁以 LF 行尾生成。Windows 下若本机检出使用 CRLF（`core.autocrlf=true`）导致 `does not apply`，请改用 `git apply --ignore-whitespace fixes.patch` 重试。

## 改动概览

**15 个文件，+668 / −44 行。**

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

### 更彻底的做法：升级官方修复版

奇安信/安天披露中提到厂商已发布修复版本（如 v0.1.0-rc.8 及后续）。本补丁是对 `0.1.2-alpha.2` 树的补强；**若条件允许，优先升级到官方最新修复版**，并以官方 changelog 为准核对这五个 QVD 的修复状态。升级后本补丁可能不再适用（官方代码结构已变），`verify-dsh-fixes.bat` 的检测标记也可能随版本演进而需要适配。

### 间接提示注入（不属于本补丁范围）

腾讯朱雀实验室 14,560 次实测（2026-08）显示，DSH 基线配置对间接提示注入的防御仍在早期阶段（完全成功约 5.3%）。这是**模型层面**的固有风险，**代码补丁无法消除**：网页/文档/邮件/Skill 等不可信内容可能诱导模型调用敏感工具。缓解只能靠运行习惯——外部内容一律按不可信处理、敏感操作留人审批、最小权限、独立容器。参考：https://matrix.tencent.com/zh/2026/08/20/deepseek-harness-agent-injection-risk
