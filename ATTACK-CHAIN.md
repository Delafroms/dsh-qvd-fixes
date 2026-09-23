# 攻击链与阻断点

> 本文件回答一个问题：**把已披露的攻击路径逐项摊开，每一步究竟被哪个补丁、哪个用例掐断？**
>
> 它**不是**"证明系统安全"的文件。每条链都给出三态判定，其中必然包含**没被掐断的步骤**。

## 怎么读这份文档

| 判定 | 含义 |
|---|---|
| **已阻断** | 该步骤在补丁后无法成立，且有对应用例或源码证据 |
| **部分缓解** | 该步骤在特定前提下仍可成立（前提会写明） |
| **未验证 / 未覆盖** | 没有证据支持任何一种结论 —— **不写成"安全"** |

证据一律指向本仓库的补丁文件、测试用例或上游源码位置。

---

## 总览

```
链 A  配置加载 !!js → 宿主 RCE              QVD-2026-52631   7.8
链 B  只读沙箱读逃逸 → 密钥泄露              QVD-2026-52632   7.5
链 C  动态插件 vm 逃逸 → 拿到宿主 exec        QVD-2026-52644   高危
链 D  C 续 → 无约束 spawn → 宿主 RCE          QVD-2026-52646   10.0
链 E  Host 伪造 → 未授权管理 RPC → RCE        QVD-2026-57410   9.8
链 F  沙箱内 Agent 自解除沙箱                 CVE-2026-82533   9.6
链 G  run_code 代码运行时隔离缺口            未上报 · 已提供修复
```

---

## 链 A — 配置加载表达式注入（52631）

| 项 | 内容 |
|---|---|
| 前置 | 攻击者能投递或写入一份配置（诱导克隆恶意仓库、**或安装一个第三方插件** —— bundle 层的 `cordis.patch.yml` 同样能写 `!!js`） |
| 步骤 | `cordis.yml` 的 `!!js` 表达式 → `with (ctx) { eval(expr) }` → 落到宿主全局作用域 → 读写文件 / 执行命令 / 读取环境变量 |
| 阻断点 | `fixes.patch`：改为 `node:vm` 隔离求值；上下文以单个 JSON 字符串注入并在 vm 内重建；`process` 只暴露白名单字段；`runInContext(..., { timeout: 1000 })` |
| 判定 | **部分缓解** —— vm 内的 `process.env` 仍是**全量投影**，`!!js process.env.<KEY>` 可读任意环境变量，并可经抛错把值带进错误信息（日志/UI 可见）。**本仓库无法修复**：按配置来源分层投影需要来源信息，而它在 `composeEntries` 的 `layers.flat()` 处已被丢弃 |
| 需要上游 | 引入「配置来源信任」模型 |

## 链 B — 只读沙箱读逃逸（52632）

| 项 | 内容 |
|---|---|
| 前置 | 无（只读会话即可） |
| 步骤 | 进程内：模型经 `tool-fs` / `tool-str-replace-editor` 读工作区外任意路径；进程级：受限 shell 子进程读整个宿主文件系统 |
| 阻断点 | `fixes-0.1.5-rc.2.patch`：① 读方法执行点策略校验 + `FS_SANDBOX_DENIED`；② `tool-str-replace-editor` 的 `view` 命令补策略；③ 动态插件 fs 门面强制携带会话策略 |
| 判定 | **部分缓解** |
| 残留 1 | **硬链接绕过**（红队实测确认）：工作区内指向外部 inode 的硬链接，路径判定无法察觉。前提是攻击者**已有工作区写原语**，故属限制而非独立漏洞。缓解：敏感文件不要与工作区同卷 |
| 残留 2 | **进程级读面**（deferred）：bwrap `--ro-bind / /`、landlock `readOnly: ['/']`、seatbelt allow-default 仍把整个宿主只读暴露给受限 shell。需 Linux/macOS 环境验证后端后再谈实现 |

## 链 C — 动态插件 vm 逃逸（52644）

| 项 | 内容 |
|---|---|
| 前置 | 模型被诱导调用 `cordis_define` + `cordis_run`（间接提示注入即可） |
| 步骤 | 沙箱内自定义工具的 `execute` 拿到真实 `agent` / `ctx` / `session` → 从"受限 vm 代码执行"升级为"访问宿主服务（含秘密存储）" |
| 阻断点 | `fixes.patch`：新增 `sandboxToolExec` 白名单执行视图，只含 `name` / `callId` / `arguments`(JSON clone) / `signal` |
| 判定 | **已阻断**（提示注入型链）；**对主动提权链无效** —— 见链 D 的说明 |

## 链 D — 链式沙箱逃逸 → 宿主 RCE（52646，10.0）

| 项 | 内容 |
|---|---|
| 前置 | 同链 C |
| 步骤 | vm 逃逸取得宿主 `exec` → `subprocess.spawn()` 起**无约束宿主进程** → 以 DSH 进程权限执行任意命令 |
| 阻断点 | `fixes.patch`：`SubprocessSpawnSpec` 增加 `sandboxPolicy` / `argvConfined`，受限策略未声明 `argvConfined` 即拒绝；`bash-local` / `pwsh-local` 在受限时 stamp `argvConfined: true`。fail-closed 加固（红队发现，现并入 `fixes-0.1.5-rc.2.patch`）：守卫改为 fail-closed —— policy 一旦存在，只有字面 `danger-full-access` 才豁免 |
| 判定 | **已阻断**（提示注入型链） |

### ⚠️ 这份补丁**挡不住**主动提权链（重要）

若攻击者能**先**把会话模式改成 `danger-full-access`（见链 E / 链 F），受限 spawn 守卫与 fs 读栅栏**按设计豁免**。也就是说：

- 52644 / 52646 的补丁真正挡的是**提示注入型**链（攻击者只能诱导模型，不能直接改会话状态）；
- 对**已经拿到管理 RPC 的攻击者**，这四个补丁不构成阻断 —— 阻断发生在链 E / 链 F 的入口。

## 链 E — Host 头伪造 → 未授权 RCE（57410，9.8）

| 项 | 内容 |
|---|---|
| 前置 | 服务暴露到非 loopback（Docker `-p 0.0.0.0`、nginx 透传 Host、云 LB 不改写） |
| 步骤 | 伪造 `Host: 127.0.0.1` 绕过"是否来自本机"的判定 → 调用高权限管理 RPC → 注册指向攻击者假模型服务器的临时提供者 → 用确定性工具调用驱动 bash → 拿到与 DSH 进程同级的权限 |
| 上游处理 | 0.1.2+ 已内建 browser-token 会话鉴权（launch token + 签名 cookie + 401/403 门禁） |
| 本仓库补充 | **传输围栏**（现并入 `fixes-0.1.5-rc.2.patch`）：信任判断引入 **TCP peer 判据**（Host 声称 loopback 而 peer 不是 → 拒绝）；`BrowserAuth.authorizeIndex` 的 token→cookie 交换补 peer 校验；新增 `trustedProxies`（默认空 = 最严格） |
| 判定 | **已阻断**（远程攻击者）；前提是未声明 `trustedProxies` |
| 未验证 | 反代实景未测（只在单测里模拟 peer 字符串）；`trustedProxies` 一旦非空，该来源即不受此围栏约束 |

## 链 F — 沙箱内 Agent 自解除沙箱（CVE-2026-82533，9.6）

| 项 | 内容 |
|---|---|
| 根因 | 与链 E **同一个**（只信 Host、不看 TCP 来源），但方向相反：不是外面打进来，而是**沙箱内的 Agent 自己把沙箱拆了** |
| 步骤 | DSH 启动时把控制接口地址与会话 ID 交给 agent 的 shell → 沙箱内一条命令调本地控制面 API，把会话模式设为 `danger-full-access` → **不弹审批、不留异常记录**（"改模式"不算"申请提权"，审批钩子不触发） |
| 上游处理 | 0.1.2-alpha.2 起加 token（本机实测：任何端点、含裸 body 与不存在的方法，一律 401，且**鉴权先于路由**） |
| 本仓库补丁是否有效 | **transport fence 挡不住这条** —— peer 就是 loopback，判据天然放行。真正相关的是**链 B 的读面**：token 的签名密钥存在 `$DSH_HOME/.credentials.yaml`，agent 若能读到它即可伪造 cookie |
| 判定 | **部分缓解** —— token 闸门是唯一防线，而密钥存储对 agent 可读 |
| 建议 | 把凭据存储纳入沙箱读面保护（密钥对 agent 不可读），而不是继续在 HTTP 层加判据 |

## 链 G — `run_code` 代码运行时隔离缺口（未上报 · 已提供修复）

> **本节不含可复现的攻击步骤。** 该发现尚未上报上游、未定级；细节只提交给上游安全渠道。

| 项 | 内容 |
|---|---|
| 影响 | `packages/code-runtime/code-runtime-worker-thread` 把模型代码交给 worker 的**全局作用域**执行，且该运行时**不接收会话沙箱策略** |
| 前置 | **无** —— 不需要网络暴露、令牌、Host 伪造、插件，也不需要模型越狱 |
| 实测对照 | 同一会话、同一 `workspace-write` 策略下：`read` / `write` 工具与 `pwsh` 子进程对工作区外路径**全部被拒**，而 `run_code` 仍可读写工作区外文件 |
| 修复 | `code-runtime-isolation.patch`（改用 `node:vm` 上下文、禁用字符串代码生成、不提供 `importModuleDynamically`、定时器 null-prototype 注入） |
| 验证 | 动态 `import` 被拒；`process` / `fetch` / `require` 不可见；`Function` 构造器与 `eval` 抛 `EvalError`；正常功能不受影响 |
| 判定 | **已提供修复，未上报** —— 请勿在官方审核前公开分发该补丁 |

---

## 交叉表：每个补丁挡住了哪条链的哪一步

> 表中标注「同上」的改动均已并入 `fixes-0.1.5-rc.2.patch`（原分项补丁于 2026-09-23 从仓库移除，设计说明保留在 `FIXES.md`）。

| 改动 | 链 A | 链 B | 链 C | 链 D | 链 E | 链 F | 链 G |
|---|---|---|---|---|---|---|---|
| 52631 vm 化（同上） | 部分 | | | | | | |
| 52632 读栅栏（同上） | | 部分 | | | | 相关 | |
| 52644 白名单（同上） | | | **阻断** | **阻断** | | | |
| 52646 argvConfined + fail-closed（同上） | | | | **阻断** | | | |
| editor `view` 补策略（同上） | | 部分 | | | | | |
| 插件 fs 门面围栏（同上） | | 部分 | | | | | |
| 传输围栏（同上） | | | | | **阻断** | ✗ **挡不住** | |
| `code-runtime-isolation.patch` | | | | | | | **阻断** |

**读法**：链 C / 链 D 的"阻断"仅对**提示注入型**攻击成立；链 F 的 transport fence 一栏是 **✗**，因为该链的 peer 就是 loopback。

---

## 已知绕过与未验证边界（汇总）

| 项 | 状态 |
|---|---|
| 硬链接读取工作区外 inode | **未修复**（路径栅栏的固有边界；需先有工作区写权限） |
| 进程级沙箱读面 | **deferred**（需 Linux/macOS 后端验证） |
| 52631 env 全量投影 | **未修复**（架构限制，需上游引入配置来源信任模型） |
| 凭据存储对 agent 可读 | **未修复**（链 F 的实际入口） |
| `trustedProxies` 非空时的来源 | **未验证**（无反代实景测试） |
| loader `!!js` vm 隔离的绕过尝试 | **未验证** |
| TOCTOU（栅栏检查与读取之间的路径替换窗口） | **未验证** |
| Linux/macOS 上的进程级沙箱行为 | **未验证** |

> 本文件不把 `Not Tested` 写成 `Secure`，也不把 `Attack Not Observed` 写成 `Attack Impossible`。
