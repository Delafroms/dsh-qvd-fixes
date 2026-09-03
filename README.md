# DeepSeek Harness QVD 安全修复补丁与验证脚本（0.1.2-alpha.2）

本仓库提供针对 DeepSeek Harness 公开披露漏洞的**社区补丁**与验证脚本，基于上游 **0.1.2-alpha.2** 基线。其中 **4 个漏洞（52631 / 52632 / 52644 / 52646）有源码修改**；**57410 是对该基线内已有修复的版本核验，本仓库未修改它**。

> 本仓库**不是官方安全更新，也不是完整安全审计**；不保证不存在其它未发现、未覆盖或与版本相关的安全问题。

## 目录内容

| 文件 | 说明 |
|---|---|
| `fixes.patch` | 相对 0.1.2-alpha.2 的统一 diff，修复 52631/52632/52644/52646（15 个文件，+668 / −44）；57410 上游已内置，无改动 |
| `FIXES.md` | 每个漏洞的逐项说明、涉及文件、应用与验证方法 |
| `verify-dsh-fixes.bat` | Windows 只读验证脚本（静态检测修复标记，可选回归测试/重建） |
| `README.md` | 本说明 |
| `LICENSE` | MIT 许可 |

## ⚠️ 安全与责任声明

- `verify-dsh-fixes.bat` 是**只读验证脚本**：不联网、不下载、不执行任何外部程序、不修改你的系统；可选 `-tests` / `-build` 只调用你自己机器上的 `pnpm`，且需手动输入 `Y` 确认。
- `fixes.patch` 是否应用由你决定：`git apply fixes.patch` 会修改 DSH 源码，请先 `git apply --check` 校验并自行备份。
- 本仓库内容按 **AS-IS** 提供；MIT 许可自带免责（见 `LICENSE`），作者对使用后果不承担责任。请先在测试环境核对。
- 本仓库**与 DeepSeek 官方无关**，不是官方修复或官方发布；以上游官方仓库为准。

## 五个漏洞

### QVD-2026-52631 — loader 配置表达式注入
- **成因**：loader 对 `cordis.yml` 里的 `!!js` 表达式用 `with (ctx) { eval(expr) }` 包在 `new Function` 中求值；表达式经 `ctx` 落到宿主全局作用域，可拿到 `process` / `require` / `module`。
- **影响**：加载配置文件阶段即可在宿主进程执行任意代码（读文件、执行命令、访问凭证）。
- **修复**：改为 `node:vm` 隔离求值；上下文以单个 JSON 字符串注入并在 vm 内重建（宿主对象零注入）；`process` 只暴露 `env/platform/arch/version/execPath/cwd` 与 `getBuiltinModule('node:url')`；`runInContext(..., { timeout: 1000 })` 限时。

### QVD-2026-52632 — fs-sandbox 读逃逸
- **成因**：`fs-sandbox` 只约束了写入，读取可越过工作区读取任意路径。
- **影响**：受限会话读到本不该访问的文件（凭据、配置、其它项目文件）。
- **修复**：读方法（`readText` / `streamText` / `readBytes`）在执行点按策略校验目标；越界抛结构化 `FS_SANDBOX_DENIED`；`tool-fs` 读前解析会话策略并传入，denial 经 `mapError` 映射。
- **已知残留**：本补丁只收窄了**进程内**读取；**进程级**沙箱（bwrap `--ro-bind / /`、landlock `readOnly: ['/']`、seatbelt allow-default）仍把整个宿主只读暴露给受限 shell 子进程。即只读会话里的 bash/pwsh 仍可能读取 `~/.ssh`、`.env` 等。详见 `FIXES.md`「已知残留与限制」。

### QVD-2026-52644 — cordis 沙箱工具逃逸
- **成因**：沙箱内自定义工具的 `execute` 拿到的执行上下文携带真实的 `agent` / `ctx` / `session` 等对象。
- **影响**：模型可通过这些对象调用宿主能力，逃出沙箱。
- **修复**：新增 `sandboxToolExec` 白名单执行视图，仅含 `name` / `callId` / `arguments`（JSON clone）/ `signal`。

### QVD-2026-52646 — bash/pwsh 子进程逃逸
- **成因**：受限策略下 bash/pwsh 仍可直接 spawn 子进程，绕过沙箱。
- **影响**：在受限会话内执行任意系统命令。
- **修复**：`SubprocessSpawnSpec` 增加 `sandboxPolicy` 与 `argvConfined`；受限策略未声明 `argvConfined` 即拒绝启动；`bash-local` / `pwsh-local` 在受限时 stamp `argvConfined: true`。

### QVD-2026-57410 — 未授权访问 / 伪造 Host（版本核验，非本仓库修复）
- **成因**：历史版本缺少浏览器会话鉴权，伪造 Host 或未带凭据即可访问。
- **影响**：未授权调用 web 接口。
- **处理**：审计确认 0.1.2-alpha.2 已内置 browser-token 会话鉴权（launch token + 签名 cookie + 401/403 门禁）。本仓库**未改动**该文件，仅记录该基线中的现有鉴权实现。

## 运行 verify-dsh-fixes.bat 会发生什么

脚本逻辑固定，行为可预期：

- **只读检测**：用 `findstr` 逐个比对源码中的修复标记（9 项），输出 `[PASS]` / `[FAIL]` 与汇总。
- **三种结果**：
  1. 定位到检出且修复齐全 → 9 项 `[PASS]`，退出码 0；
  2. 定位到检出但缺修复 → 对应项 `[FAIL]`，退出码 1（只输出信息，不改文件）；
  3. 未定位到检出 → 提示"未找到检出根目录"，退出码 2（无副作用）。
- **定位规则**：脚本所在目录含 `package.json` 即视为检出根；否则读环境变量 `DSH_REPO`；再否则用脚本内写死的本机回退路径。
- **可选 `-tests` / `-build`**：需手动输入 `Y` 才执行，且调用的是**你自己机器上的 `pnpm`**（跑 DSH 回归测试 / 重建）。未安装 `pnpm` 或依赖时会报错退出，不产生破坏。
- 全程**不联网、不上传、不下载、不执行外部程序**。

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

## 安全建议

- **插件即代码**：不要加载来源不明、未经审查的插件；它们在宿主进程内执行。
- **网页/搜索内容不受信任**：对"抓取网页 / 搜索"类工具返回的内容保持警惕，它可能诱导后续危险操作。
- **保持本地监听**：DSH Web 应只绑定 `127.0.0.1`，不要设为 `0.0.0.0` 暴露到局域网/公网。
- **只用官方来源**：从 DeepSeek Harness 官方仓库获取与更新代码。
- **优先升级官方修复版**：本补丁基于 0.1.2-alpha.2；官方后续版本可能已修复这五个漏洞，以官方 changelog 为准，条件允许时优先升级官方版。
- **只读模式不保护敏感文件**：本补丁收窄了进程内读取，但进程级沙箱仍把整个宿主只读暴露给受限 shell；处理不可信内容时请把 `.ssh`、`.env`、云凭据等移出 agent 可读目录。
- 应用补丁前先 `--check` 并在测试环境验证。

## 文件校验表（防篡改核对）

核对命令（大小写不敏感）：

```bat
certutil -hashfile "verify-dsh-fixes.bat" SHA256
certutil -hashfile "fixes.patch" SHA256
certutil -hashfile "FIXES.md" SHA256
certutil -hashfile "LICENSE" SHA256
```

| 文件 | SHA-256 |
|---|---|
| `verify-dsh-fixes.bat` | `CC35A3D559D7E271DB55DAD5D7E1582DDA437FFD0D3B4E851DE4A379221E11CE` |
| `fixes.patch` | `727290C97B539F4988A83803A6B4AE5E9F44F10FC1DC5D8A0981F466D3F13D0E` |
| `FIXES.md` | `DF47B70B86E289133A0E5ACC6171F183012B55846D203D3ECF8D283754ECE4BA` |
| `LICENSE` | `B546772903BAEBAFB411FD4A5E1A5B91855659BF38C56165A7096712615C8AF9` |

说明：
- 表中不含 README 自身（它无法自证，请以其它文件为准）。
- 脚本不做自我校验：把哈希写进自身会形成自指、且攻击者可连校验代码一起改，故采用"外部公布值 + certutil 手工核对"。
- 作者每次修改文件后需同步更新上表。

## 许可证与归属

- 本仓库的脚本与文档：MIT License，版权人 **Delafroms**，见 `LICENSE`。
- DeepSeek Harness 上游：MIT License（© 其作者）。补丁是对上游 MIT 源码的修改，分发时需保留上游版权声明并注明修改，不得将上游代码标为原创。
- 建议只分发本补丁与说明，不要整包上传整个 DSH 检出或 `node_modules`。

## 参考

- DeepSeek Harness 官方仓库：https://github.com/deepseek-ai/DeepSeek-Harness
- 逐项修复说明：见 `FIXES.md`。
