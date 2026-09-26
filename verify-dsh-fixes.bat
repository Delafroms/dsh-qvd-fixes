@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
rem ============================================================
rem  verify-dsh-fixes.bat
rem  一键验证 DeepSeek Harness 五个 QVD 漏洞修复是否生效
rem  （静态检测源码修复标记，可选回归测试与重建）
rem  （含 2026-09-26 的 0.1.7-rc.2 轮次检查项）
rem ============================================================

set "FAIL=0"
set "SKIPPED=0"
set "MODE_TESTS="
set "MODE_BUILD="

for %%a in (%*) do (
    if /I "%%~a"=="-tests"  set "MODE_TESTS=1"
    if /I "%%~a"=="-build"  set "MODE_BUILD=1"
    if /I "%%~a"=="-all"    set "MODE_TESTS=1"
    if /I "%%~a"=="-all"    set "MODE_BUILD=1"
    if /I "%%~a"=="-h"      goto :usage
    if /I "%%~a"=="-help"   goto :usage
)

rem ---------- 定位仓库根 ----------
set "ROOT=%~dp0"
if exist "%ROOT%\package.json" goto :root_ok
rem 也接受当前工作目录（要求同时存在 DSH 的包目录，避免误判）。
if exist "%CD%\package.json" if exist "%CD%\packages\fs\fs-sandbox" (
    set "ROOT=%CD%"
    goto :root_ok
)
rem 延迟展开（!VAR!）是必须的：if 块在解析时就展开了 %ROOT%，会让这里的检查
rem 查的是脚本自身目录而不是 DSH_REPO，从而永远失败。
if defined DSH_REPO (
    set "ROOT=!DSH_REPO!"
    if exist "!ROOT!\package.json" goto :root_ok
)
rem DSH_REPO 未设置时，向上两级找检出（脚本常被放在检出根或工具目录）
for %%D in ("%~dp0.." "%~dp0..\..") do (
    if exist "%%~fD\package.json" (
        set "ROOT=%%~fD"
        goto :root_ok
    )
)
echo.
echo  [错误] 未找到 DeepSeek Harness 检出根目录。
echo         用法：把本脚本放到 DSH 检出根目录再运行；
echo         或在运行前设置环境变量：set DSH_REPO=你的检出路径
exit /b 2

:root_ok
if not "%ROOT%"=="" if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
echo.
echo ============================================================
echo   QVD 修复验证器 - DeepSeek Harness
echo   仓库根: %ROOT%
echo ============================================================
echo.

rem ---------- QVD-2026-52631 loader JS 注入 -> node:vm 隔离求值 ----------
call :CHECK "QVD-2026-52631  vm 隔离求值 - createContext/runInContext" "%ROOT%\vendor\loader\src\config\utils.ts" "node:vm" "createContext" "runInContext"
call :CHECK "QVD-2026-52631  process 白名单 - 仅暴露 node:url" "%ROOT%\vendor\loader\src\config\utils.ts" "getBuiltinModule" "node:url" ""

rem ---------- QVD-2026-52632 fs-sandbox 读逃逸 -> 读路径策略校验 ----------
call :CHECK "QVD-2026-52632  fs-sandbox 越界读 / 策略校验" "%ROOT%\packages\fs\fs-sandbox\src\index.ts" "checkedReadTarget" "FS_SANDBOX_DENIED" ""
call :CHECK "QVD-2026-52632  tool-fs 读取传入策略并映射拒绝" "%ROOT%\packages\fs\tool-fs\src\read.ts" "sandboxPolicy" "mapError" ""

rem ---------- QVD-2026-52644 cordis 工具逃逸 -> 白名单执行视图 ----------
call :CHECK "QVD-2026-52644  cordis 沙箱工具逃逸 / 白名单 exec" "%ROOT%\packages\extensions\cordis-host-runner\src\guard.ts" "sandboxToolExec" "sandboxDefineTool" "cloneJson"

rem ---------- QVD-2026-52646 bash/pwsh 子进程逃逸 -> argvConfined ----------
call :CHECK "QVD-2026-52646  子进程受限策略声明 - subprocess types" "%ROOT%\packages\subprocess\subprocess\src\types.ts" "argvConfined" "" ""
call :CHECK "QVD-2026-52646  子进程执行点强制校验 - spawn" "%ROOT%\packages\subprocess\subprocess-local\src\spawn.ts" "assertConfinedUnderPolicy" "" ""
call :CHECK "QVD-2026-52646  bash-local 受限策略 stamped argvConfined" "%ROOT%\packages\shell\bash-local\src\index.ts" "argvConfined: true" "" ""
call :CHECK "QVD-2026-52646  pwsh-local 受限策略 stamped argvConfined" "%ROOT%\packages\shell\pwsh-local\src\index.ts" "argvConfined: true" "" ""

rem ---------- QVD-2026-57410 未授权访问 -> 内建 browser-token 鉴权（审计确认）----------
call :CHECK "QVD-2026-57410  browser-token 会话鉴权 - 审计确认" "%ROOT%\packages\client\connection\src\browser-auth.ts" "launchToken" "401" "timingSafeEqual"
call :CHECK "QVD-2026-57410  API 请求信任门禁 401/403 - 审计确认" "%ROOT%\packages\client\connection\src\rpc-host.ts" "isTrustedApiRequest" "403" "401"

rem ---------- 补充补丁（0.1.5-rc.2 批次，可选）----------
rem 这些标记只在应用了对应补充补丁的树上出现。缺失记为 [SKIP] 而非 [FAIL]，
rem 因为补充补丁是可选增量：未应用它们不代表基线补丁有问题。
call :CHECK_OPT "补充 57410  传输围栏 - peer 地址判据" "%ROOT%\packages\client\connection\src\api-request-trust.ts" "isLoopbackAddress" "trustedProxies" ""
call :CHECK_OPT "补充 57410  token 交换的 peer 校验" "%ROOT%\packages\client\connection\src\browser-auth.ts" "peerMayCarryAuthority" "" ""
call :CHECK_OPT "补充 52632  编辑器读栅栏 - view 带策略" "%ROOT%\packages\fs\tool-str-replace-editor\src\index.ts" "policy.resolve(exec)" "" ""
call :CHECK_OPT "补充 52632  插件 fs 围栏 - 门面注入策略" "%ROOT%\packages\extensions\cordis-host-runner\src\guard.ts" "fencedFsService" "FENCED_FS_READS" ""
call :CHECK_OPT "补充 52646  受限 spawn fail-closed" "%ROOT%\packages\subprocess\subprocess-local\src\spawn.ts" "sandboxPolicy === undefined" "danger-full-access" ""

rem ---------- 红队测试是否就位（可选）----------
call :CHECK_OPT "红队 52632  读栅栏对抗套件" "%ROOT%\packages\fs\fs-sandbox\tests\redteam-read-fence.spec.ts" "KNOWN BYPASS" "CANARY" ""
call :CHECK_OPT "红队 52646  受限 spawn 对抗套件" "%ROOT%\packages\subprocess\subprocess-local\tests\redteam-confined-spawn.spec.ts" "assertConfinedUnderPolicy" "" ""
call :CHECK_OPT "红队 AgentLoop  终止性探测套件" "%ROOT%\packages\core\agent-loop\tests\redteam-loop-termination.spec.ts" "terminates after ONE request" "" ""
call :CHECK_OPT "补充 守卫  纯文本重复检测包" "%ROOT%\packages\guard\repeat-text-reminder\src\index.ts" "repeat-text-reminder" "minChars" ""
rem ---------- 0.1.7-rc.2 轮次（2026-09-26，可选）----------
rem 这批标记只在应用了 fixes-0.1.7-rc.2.patch 的 0.1.7 树上出现。与上一批同理，
rem 缺失记 [SKIP] 而非 [FAIL]：在 0.1.2 / 0.1.5 树上它们本就不存在，不影响基线结论。
call :CHECK_OPT "0.1.7 52632  搜索根栅栏 - glob/grep 先判策略" "%ROOT%\packages\fs\tool-fs-search\src\search-sandbox.ts" "SearchSandboxFence" "fenceSearchRoot" "deniedSearchRoot"
call :CHECK_OPT "0.1.7 52632  搜索栅栏用例 - spawn 之前拒绝" "%ROOT%\packages\fs\tool-fs-search\tests\search-root-fence.spec.ts" "before any spawn" "danger-full-access leaves the search unconfined" ""
call :CHECK_OPT "0.1.7 凭据  判据单点导出 - isProtectedReadPath" "%ROOT%\packages\fs\fs\src\index.ts" "isProtectedReadPath" ".credentials" ""
call :CHECK_OPT "0.1.7 凭据  fs-sandbox 任何模式都拒绝" "%ROOT%\packages\fs\fs-sandbox\src\index.ts" "isProtectedReadPath" "FS_PERMISSION_DENIED" ""
call :CHECK_OPT "0.1.7 凭据  搜索栅栏同样拒绝凭据" "%ROOT%\packages\fs\tool-fs-search\src\search-sandbox.ts" "isProtectedReadPath" "FS_PERMISSION_DENIED" ""
call :CHECK_OPT "0.1.7 run_code  宿主对象包装 - detachedHostSurface" "%ROOT%\packages\ptc-runtime\ptc-runtime-node\src\bootstrap.ts" "detachedHostSurface" "Reflect.construct" "WeakSet"
call :CHECK_OPT "0.1.7 /api/file  只读根白名单与结构化码" "%ROOT%\packages\api\session-controller\src\media-references.ts" "MEDIA_PATH_OUTSIDE_ROOTS" "defaultReadRoots" "workspaceRegistry"
call :CHECK_OPT "0.1.7 session.export  工作区绑定鉴权" "%ROOT%\packages\session-query\session-log-export\src\index.ts" "SESSION_LOG_EXPORT_OUTSIDE_WORKSPACE" "requestRejection" ""
call :CHECK_OPT "0.1.7 /plugins/events  SSE 信任围栏" "%ROOT%\packages\client\hmr\src\index.ts" "browserTrustFence" "requestRejection" ""
call :CHECK_OPT "0.1.7 /plugins  模块路由信任围栏" "%ROOT%\packages\client\modules\src\index.ts" "browserTrustFence" "PLUGIN_ROUTE" ""
call :CHECK_OPT "0.1.7 duplicate Host  结构化拒绝 code" "%ROOT%\packages\client\connection\src\api-request-trust.ts" "ApiRequestTrustRefusalCode" "host-repeated" "host-authority-mismatch"
call :CHECK_OPT "0.1.7 搜索包  依赖声明 dsh-sandbox-policy" "%ROOT%\packages\fs\tool-fs-search\package.json" "dsh-sandbox-policy" "" ""


echo.
echo ------------------------------------------------------------
if "%FAIL%"=="0" (
    echo   [结果] 基线 PASS：五个 QVD 的修复点均已就位。
) else (
    echo   [结果] !FAIL! 项 FAIL：仓库可能基于未修复版本，或文件路径已变动。
)
if not "%SKIPPED%"=="0" (
    echo   [说明] !SKIPPED! 项 SKIP：0.1.5 补充补丁 / 红队套件 / 0.1.7 轮次项未就位（不影响基线结论）。
)
echo ------------------------------------------------------------
echo.

if not "%FAIL%"=="0" exit /b 1

rem ---------- 可选：回归测试 ----------
if defined MODE_TESTS (
    set /p "go=是否运行 3 组回归测试（fs-sandbox / sandbox-context / user-patches）？[Y/N] "
    if /I "!go!"=="Y" (
        echo.
        echo === 运行回归测试 ===
        cd /d "%ROOT%"
        pnpm exec vitest run "packages/fs/fs-sandbox/tests/fs-sandbox.spec.ts" "packages/extensions/cordis-host-runner/tests/sandbox-context.spec.ts" "packages/boot/app-boot/tests/user-patches.spec.ts"
        echo.
        echo 测试退出码: !errorlevel!（0 = 全部通过）
    ) else (
        echo 已跳过回归测试。
    )
)

rem ---------- 可选：全量重建 ----------
if defined MODE_BUILD (
    set /p "go2=是否运行 pnpm run build 全量重建（耗时较长）？[Y/N] "
    if /I "!go2!"=="Y" (
        echo.
        echo === 开始全量重建 ===
        cd /d "%ROOT%"
        pnpm run build
        echo.
        echo 构建退出码: !errorlevel!（0 = 成功）
    ) else (
        echo 已跳过重建。
    )
)

echo.
echo 验证完成。退出码 0 表示静态验证全部通过。
exit /b 0

:usage
echo.
echo 用法: verify-dsh-fixes.bat [选项]
echo.
echo   不带参数  : 仅静态验证五个 QVD 修复点（默认）
echo   检查范围  : 基线 11 项 + 0.1.5 补充与红队 9 项 + 0.1.7 轮次 12 项（后两类缺失记 SKIP）
echo   -tests    : 静态验证通过后，询问是否运行 3 组回归测试
echo   -build    : 静态验证通过后，询问是否运行全量重建
echo   -all      : 以上两者都要
echo   -h / -help: 显示本帮助
echo.
echo 环境变量 DSH_REPO 可指定仓库根目录（不设置时自动探测本机路径）。
exit /b 0

:CHECK
rem 子程序：%1 显示名  %2 文件  %3/%4/%5 需同时存在的标记（可空）
set "C_LBL=%~1"
set "C_FILE=%~2"
set "ok=1"
if not exist "%C_FILE%" set "ok=0"
if "%ok%"=="1" if not "%~3"=="" findstr /C:"%~3" "%C_FILE%" >nul 2>nul || set "ok=0"
if "%ok%"=="1" if not "%~4"=="" findstr /C:"%~4" "%C_FILE%" >nul 2>nul || set "ok=0"
if "%ok%"=="1" if not "%~5"=="" findstr /C:"%~5" "%C_FILE%" >nul 2>nul || set "ok=0"
if "%ok%"=="1" (
    echo   [PASS] %C_LBL%
) else (
    echo   [FAIL] %C_LBL%
    set /a FAIL+=1
)
exit /b

:CHECK_OPT
rem 同 :CHECK，但缺失记为 [SKIP]（可选补充补丁未应用），不计入 FAIL。
set "C_LBL=%~1"
set "C_FILE=%~2"
set "ok=1"
if not exist "%C_FILE%" set "ok=0"
if "%ok%"=="1" if not "%~3"=="" findstr /C:"%~3" "%C_FILE%" >nul 2>nul || set "ok=0"
if "%ok%"=="1" if not "%~4"=="" findstr /C:"%~4" "%C_FILE%" >nul 2>nul || set "ok=0"
if "%ok%"=="1" if not "%~5"=="" findstr /C:"%~5" "%C_FILE%" >nul 2>nul || set "ok=0"
if "%ok%"=="1" (
    echo   [PASS] %C_LBL%
) else (
    echo   [SKIP] %C_LBL%
    set /a SKIPPED+=1
)
exit /b
