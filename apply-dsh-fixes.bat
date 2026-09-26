@echo off
setlocal enabledelayedexpansion
rem ============================================================
rem  Apply DSH QVD fixes to a DeepSeek Harness checkout.
rem  Picks the patch from the checkout version: the 0.1.7-rc.2
rem  round patch, or the 0.1.5-rc.2 consolidated patch.
rem  Read-only pre-check first: nothing is written unless you say Y.
rem ============================================================
set "HERE=%~dp0"
set "ROOT="

if exist "%HERE%package.json" set "ROOT=%HERE%"
if not defined ROOT if exist "%CD%\package.json" if exist "%CD%\packages\fs\fs-sandbox" set "ROOT=%CD%\"
if not defined ROOT if defined DSH_REPO if exist "%DSH_REPO%\package.json" set "ROOT=%DSH_REPO%\"
if not defined ROOT if exist "%HERE%..\package.json" set "ROOT=%HERE%..\"
if not defined ROOT if exist "%HERE%..\..\package.json" set "ROOT=%HERE%..\..\"
rem A trailing backslash would escape the closing quote of "%ROOT%" below.
if defined ROOT if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

echo.
echo === DSH QVD fixes - apply ===
echo.
if not defined ROOT (
  echo [FAIL] Could not locate a DSH checkout root.
  echo        Put this .bat in the checkout root, or set DSH_REPO.
  exit /b 2
)
echo Checkout : %ROOT%

where git >nul 2>nul
if errorlevel 1 (
  echo [FAIL] git not found on PATH.
  exit /b 2
)

set "P17=%HERE%fixes-0.1.7-rc.2.patch"
set "P15=%HERE%fixes-0.1.5-rc.2.patch"
set "PZD=%HERE%code-runtime-isolation.patch"

rem ---------- pick the patch that matches the checkout version ----------
set "TREE07="
if exist "%ROOT%\package.json" findstr /C:"0.1.7-rc.2" "%ROOT%\package.json" >nul 2>nul
if not errorlevel 1 if exist "%ROOT%\packages\ptc-runtime\ptc-runtime-node" set "TREE07=1"

if defined TREE07 (
  set "PATCH=%P17%"
  set "PATCHNAME=fixes-0.1.7-rc.2.patch"
  set "ROUND=0.1.7-rc.2 - 2026-09-26 round"
  set "MARKFILE=%ROOT%\packages\fs\tool-fs-search\src\search-sandbox.ts"
  set "MARKTEXT=SearchSandboxFence"
) else (
  set "PATCH=%P15%"
  set "PATCHNAME=fixes-0.1.5-rc.2.patch"
  set "ROUND=0.1.5-rc.2 - baseline plus supplementary fixes"
  set "MARKFILE=%ROOT%\packages\client\connection\src\api-request-trust.ts"
  set "MARKTEXT=trustedProxies"
)

echo Round    : %ROUND%
echo Patch    : %PATCHNAME%
echo.

if not exist "%PATCH%" (
  echo [FAIL] missing %PATCH%
  exit /b 2
)

echo [1/3] Pre-check %PATCHNAME% ...
git -C "%ROOT%" apply --check "%PATCH%"
if errorlevel 1 (
  set "APPLIED="
  if exist "!MARKFILE!" findstr /C:"!MARKTEXT!" "!MARKFILE!" >nul 2>nul
  if not errorlevel 1 set "APPLIED=1"
  if defined APPLIED (
    echo [SKIP] This tree already carries the round fixes. Nothing was written.
    echo        Re-running is a no-op by design.
    exit /b 0
  )
  echo [FAIL] patch does not apply to this tree. Nothing was written.
  echo        The tree must be an unmodified checkout of the matching version.
  echo        Check the version with: findstr version "%ROOT%\package.json"
  exit /b 1
)
echo       OK - applies cleanly.
echo.

set "ANS="
set /p "ANS=Apply %PATCHNAME% now? [y/N] "
if /i not "%ANS%"=="y" (
  echo Aborted. Nothing was written.
  exit /b 0
)
echo.
echo [2/3] Applying %PATCHNAME% ...
git -C "%ROOT%" apply "%PATCH%"
if errorlevel 1 (
  echo [FAIL] apply failed.
  exit /b 1
)
echo       Done.

if defined TREE07 (
  echo.
  echo [3/3] code-runtime-isolation.patch is NOT applied on 0.1.7.
  echo        Upstream replaced the worker-thread runtime with ptc-runtime-node,
  echo        so the old patch does not apply. The host-object leak of that
  echo        architecture is closed by the detachedHostSurface change that is
  echo        already part of %PATCHNAME%.
  echo.
  echo Finished. Run verify-dsh-fixes.bat to confirm the fix markers.
  exit /b 0
)

if not exist "%PZD%" (
  echo.
  echo [3/3] code-runtime-isolation.patch not present - skipped.
  echo.
  echo Finished. Run verify-dsh-fixes.bat to confirm the fix markers.
  exit /b 0
)

echo.
echo [3/3] Optional: code-runtime-isolation.patch
echo       This closes an UNREPORTED isolation gap in run_code.
echo       It targets the 0.1.2-0.1.5 worker-thread architecture only.
echo       Do not publish it before the vendor has reviewed the finding.
set "ANS2="
set /p "ANS2=Apply it too? [y/N] "
if /i not "%ANS2%"=="y" (
  echo       Skipped.
  echo.
  echo Finished. Run verify-dsh-fixes.bat to confirm the fix markers.
  exit /b 0
)
git -C "%ROOT%" apply --check "%PZD%"
if errorlevel 1 (
  echo [FAIL] code-runtime-isolation.patch does not apply. The round fixes are applied; nothing else changed.
  exit /b 1
)
git -C "%ROOT%" apply "%PZD%"
if errorlevel 1 (
  echo [FAIL] apply failed.
  exit /b 1
)
echo       Done.
echo.
echo Finished. Run verify-dsh-fixes.bat to confirm the fix markers.
exit /b 0
