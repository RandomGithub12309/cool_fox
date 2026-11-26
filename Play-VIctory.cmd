@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "console_profile=series-s"
if not "%~1"=="" (
  if /i "%~1"=="pareto-residency" (
    set "console_profile=series-s"
  ) else if /i "%~1"=="series-s" (
    set "console_profile=series-s"
  ) else if /i "%~1"=="series-x" (
    set "console_profile=series-x"
  ) else (
    echo Usage: Play-VIctory.cmd [series-s^|series-x^|pareto-residency] 1>&2
    exit /b 2
  )
)
if not defined VICTORY_GAME_DIR if exist "%~dp0..\GTA6.Xbox.v1.0.2.1\game_scarlett_master.exe" set "VICTORY_GAME_DIR=%~dp0..\GTA6.Xbox.v1.0.2.1"
if not defined VICTORY_GAME_DIR if exist "%~dp0..\..\config.json" call :read_launcher_cfg "%~dp0..\..\config.json"
if not defined VICTORY_GAME_DIR set "VICTORY_GAME_DIR=%~dp0..\GTA6.Xbox.v1.0.2.1"
if not exist "%VICTORY_GAME_DIR%\game_scarlett_master.exe" (
  echo Set VICTORY_GAME_DIR to your own dump folder containing game_scarlett_master.exe. 1>&2
  echo Checked: "%VICTORY_GAME_DIR%" 1>&2
  if not defined VICTORY_NO_PAUSE echo %CMDCMDLINE% | find /i "%~dpnx0" >nul && pause
  exit /b 2
)
set "runner=%~dp0victory-3d-rtx-pareto-residency.exe"
if not exist "%runner%" set "runner=%~dp0target\release\victory.exe"
if not exist "%runner%" (
  echo Extract the Windows release or run cargo build --release --locked -p victory. 1>&2
  if not defined VICTORY_NO_PAUSE echo %CMDCMDLINE% | find /i "%~dpnx0" >nul && pause
  exit /b 2
)
if not defined VICTORY_AMBIENT_AIR set "VICTORY_AMBIENT_AIR=1.5"
if not defined VICTORY_CACHE_DIR set "VICTORY_CACHE_DIR=%LOCALAPPDATA%\VIctory\cache-pareto"
if not defined VICTORY_TEXTURE_NO_WAIT set "VICTORY_TEXTURE_NO_WAIT=1"
if not defined VICTORY_RELAY set "VICTORY_RELAY=2"
if not defined VICTORY_WIDE_BACK set "VICTORY_WIDE_BACK=1"
if not defined VICTORY_CARD_REHASH_RUNS set "VICTORY_CARD_REHASH_RUNS=1"
if not defined VICTORY_JOIN_COPIES set "VICTORY_JOIN_COPIES=1"
if not defined VICTORY_INDIRECT_WINDOW set "VICTORY_INDIRECT_WINDOW=1"
if not defined VICTORY_RELAY_COPY set "VICTORY_RELAY_COPY=1"
if not defined VICTORY_CARD_STEPS set "VICTORY_CARD_STEPS=2"
if not defined VICTORY_INDIRECT_BATCH set "VICTORY_INDIRECT_BATCH=2"
if not defined VICTORY_MAP_THREADS set "VICTORY_MAP_THREADS=1"
if not defined VICTORY_CARD_AWAKE set "VICTORY_CARD_AWAKE=1"
if not defined VICTORY_SHOW_AFTER set "VICTORY_SHOW_AFTER=1"
rem A constant, not the frame estimate: walking into a bright doorway raised
rem the estimate and washed the whole frame out. constant:1.0 is even light.
if not defined VICTORY_AMBIENT set "VICTORY_AMBIENT=constant:0.8"
rem The write guard misses some titles' writes: skin on a guard's arms and the
rem phone's frame read garbage (colour noise) until every check hashed the
rem texture again. Costs some CPU; the frame rate held at 5-7 fps here.
if not defined VICTORY_TEXTURE_GUARD set "VICTORY_TEXTURE_GUARD=0"
rem The asynchronous submission paths stay off on NVIDIA: with THIN the head
rem skin of people in play is not drawn (eyes and teeth are), and JOIN_PARTS
rem repeats frames of the opening video. Set them to 1 to try instead.
rem Keep async submission preparation ON even with THIN off: without this,
rem setting VICTORY_THIN=0 accidentally turned off VICTORY_ASYNC_SUBMIT too,
rem blocking the title's render thread synchronously on every submission.
if not defined VICTORY_ASYNC_SUBMIT set "VICTORY_ASYNC_SUBMIT=1"
if not defined VICTORY_THIN set "VICTORY_THIN=0"
if not defined VICTORY_JOIN_PARTS set "VICTORY_JOIN_PARTS=0"
if not defined VICTORY_WIDE_SPIN set "VICTORY_WIDE_SPIN=50"
if not defined VICTORY_D3D12_BACKGROUND set "VICTORY_D3D12_BACKGROUND=0"
if not defined VICTORY_UPLOAD_AHEAD set "VICTORY_UPLOAD_AHEAD=1"
if not defined VICTORY_LEVELS_ON_DEMAND set "VICTORY_LEVELS_ON_DEMAND=1"
if not defined VICTORY_CARD_BUFFERS_MIN_KB set "VICTORY_CARD_BUFFERS_MIN_KB=64"
rem Series S default: native 1920x1080 output (prevents stale 4K settings.xml
rem from overflowing 8 GB VRAM) and 256 MiB Resizable BAR direct GDDR7 windows
rem (falls back automatically if unsupported). Pass "series-x" to run Series X.
if /i "%console_profile%"=="series-s" (
  if not defined VICTORY_OUTPUT set "VICTORY_OUTPUT=1920x1080"
  if not defined VICTORY_WINDOWS_BAR_MB set "VICTORY_WINDOWS_BAR_MB=256"
)
if not defined VICTORY_LOG if not defined RUST_LOG set "VICTORY_LOG=warn"
rem Controls: WASD (LAlt=walk), IJKL/Numpad (or F4 for Mouse Look + LMB/RMB),
rem LShift/Enter=A, R/Back=B, Space/X=X, F/Y=Y, Q/E=LB/RB, Z/U=LT, C/O=RT,
rem LCtrl/G=LS, V/H=RS, Arrows=D-Pad, Esc/P=Menu, Tab/M=View. Override via VICTORY_KEYMAP.
"%runner%" run "%VICTORY_GAME_DIR%\game_scarlett_master.exe" --console %console_profile% --execute
set "rc=%errorlevel%"
if not "%rc%"=="0" (
  echo VIctory exited with code %rc%. 1>&2
  if not defined VICTORY_NO_PAUSE echo %CMDCMDLINE% | find /i "%~dpnx0" >nul && pause
)
exit /b %rc%

:read_launcher_cfg
set "_victory_cfg=%~1"
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "try { $c = Get-Content -Raw -LiteralPath $env:_victory_cfg | ConvertFrom-Json; if ($c.GameFolder) { $c.GameFolder } } catch {}"`) do if not "%%D"=="" set "VICTORY_GAME_DIR=%%D"
set "_victory_cfg="
exit /b 0
