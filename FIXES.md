# 修复改动清单（QVD 五个漏洞）

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

### QVD-2026-52644 — cordis 沙箱工具逃逸
- 新增 `sandboxToolExec(exec)`：向外提供**白名单化**执行视图，仅含 `name` / `callId` / `arguments`（JSON clone）/ `signal`，不含 agent 或真实宿主对象。
- `sandboxDefineTool` 的模型可写 `execute` 改为 `rawExecute(args, sandboxToolExec(exec))` 调用。

### QVD-2026-52646 — bash/pwsh 子进程逃逸
- `SubprocessSpawnSpec` 增加可选 `sandboxPolicy` 与 `argvConfined`。
- `subprocess-local` 新增 `assertConfinedUnderPolicy(spec)`：受限 policy 且非 `argvConfined` → 抛错拒绝，`spawnSubprocess` 入口调用。
- `bash-local` / `pwsh-local` 在受限 policy 下 stamp `{ sandboxPolicy, argvConfined: true }`。

### QVD-2026-57410 — 未授权访问 / 伪造 Host
- 审计结论：本树版本（`0.1.2-alpha.2`）已含上游 browser-token 会话鉴权（`packages/client/connection/src/browser-auth.ts`、`rpc-host.ts` 401/403 门禁）。伪造 Host 或缺失合法 token 的请求返回 401/403。本补丁未改动此文件。

## 验证方法

1. 静态检测：运行本目录 `verify-dsh-fixes.bat`，五项应全部 `[PASS]`。
2. 回归测试：`pnpm exec vitest run packages/fs/fs-sandbox/tests/fs-sandbox.spec.ts packages/extensions/cordis-host-runner/tests/sandbox-context.spec.ts packages/boot/app-boot/tests/user-patches.spec.ts`。
3. 全量构建：`pnpm run build`（三方：host / client / web 均通过）。
