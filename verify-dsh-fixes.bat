@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
rem ============================================================
rem  verify-dsh-fixes.bat
rem  一键验证 DeepSeek Harness 五个 QVD 漏洞修复是否生效
rem  （静态检测源码修复标记，可选回归测试与重建）
rem ============================================================

set "FAIL=0"
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
if defined DSH_REPO (
    set "ROOT=%DSH_REPO%"
    if exist "%ROOT%\package.json" goto :root_ok
)
rem 本机回退路径（该机器上的 DSH 检出）
set "ROOT=D:\deepseek-harness-master\deepseek-harness-master\deepseek-harness"
if exist "%ROOT%\package.json" goto :root_ok
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

echo.
echo ------------------------------------------------------------
if "%FAIL%"=="0" (
    echo   [结果] 全部 PASS：五个 QVD 的修复点均已就位。
) else (
    echo   [结果] !FAIL! 项 FAIL：仓库可能基于未修复版本，或文件路径已变动。
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
