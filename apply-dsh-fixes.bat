@echo off
setlocal enabledelayedexpansion
rem ============================================================
rem  Apply DSH QVD fixes to a DeepSeek Harness 0.1.5-rc.2 tree
rem  Read-only pre-check first: nothing is written unless you say Y.
rem ============================================================
set "HERE=%~dp0"
set "ROOT="

if exist "%HERE%package.json" set "ROOT=%HERE%"
if not defined ROOT if exist "%CD%\package.json" set "ROOT=%CD%\"
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
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [FAIL] git not found on PATH.
  exit /b 2
)

set "P15=%HERE%fixes-0.1.5-rc.2.patch"
set "PZD=%HERE%code-runtime-isolation.patch"

if not exist "%P15%" (
  echo [FAIL] missing %P15%
  exit /b 2
)

echo [1/3] Pre-check fixes-0.1.5-rc.2.patch ...
git -C "%ROOT%" apply --check "%P15%"
if errorlevel 1 (
  echo [FAIL] patch does not apply to this tree. Nothing was written.
  echo        The tree must be an unmodified 0.1.5-rc.2 checkout.
  exit /b 1
)
echo       OK - applies cleanly.
echo.

set "ANS="
set /p "ANS=Apply the 0.1.5-rc.2 fixes now? [y/N] "
if /i not "%ANS%"=="y" (
  echo Aborted. Nothing was written.
  exit /b 0
)
echo.
echo [2/3] Applying fixes-0.1.5-rc.2.patch ...
git -C "%ROOT%" apply "%P15%"
if errorlevel 1 (
  echo [FAIL] apply failed.
  exit /b 1
)
echo       Done.

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
  echo [FAIL] code-runtime-isolation.patch does not apply. The 0.1.5 fixes are applied; nothing else changed.
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
