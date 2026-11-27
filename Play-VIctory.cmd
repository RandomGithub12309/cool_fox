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
if not defined VICTORY_AMBIENT_MOST set "VICTORY_AMBIENT_MOST=2"
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
rem Scrub NaN/Inf on pixel color outputs and float image stores so bad values
rem never smear through bloom, blur, or temporal upscaling on NVIDIA.
if not defined VICTORY_NAN_SCRUB set "VICTORY_NAN_SCRUB=1"
rem Skip walking stale/unbuilt BVH nodes while the ray-tracing builder is off.
if not defined VICTORY_BVH_MISS set "VICTORY_BVH_MISS=1"
rem NVIDIA caps shader-visible view heaps at 1,000,000; expand dynamic slots so
rem complex scenes never drop draws.
if not defined VICTORY_DYNAMIC_SLOTS set "VICTORY_DYNAMIC_SLOTS=458752"
rem The write guard misses some titles' writes: skin on a guard's arms and the
rem phone's frame read garbage (colour noise) until every check hashed the
rem texture again. Costs some CPU; the frame rate held at 5-7 fps here.
if not defined VICTORY_TEXTURE_GUARD set "VICTORY_TEXTURE_GUARD=0"
rem Dedicated P-core submission thread (VICTORY_ASYNC_SUBMIT=1) decouples game
rem recording from GPU preparation/submission so CPU recording, CPU prep, GPU
rem execution, and relay readback all overlap simultaneously (eliminates the
rem 48-73%% GPU idle gaps while keeping THIN=0 / JOIN_PARTS=0 for full accuracy).
if not defined VICTORY_ASYNC_SUBMIT set "VICTORY_ASYNC_SUBMIT=1"
if not defined VICTORY_LAND_SKIP set "VICTORY_LAND_SKIP=1"
if not defined VICTORY_THIN set "VICTORY_THIN=0"
if not defined VICTORY_JOIN_PARTS set "VICTORY_JOIN_PARTS=0"
if not defined VICTORY_WIDE_SPIN set "VICTORY_WIDE_SPIN=100"
if not defined VICTORY_D3D12_BACKGROUND set "VICTORY_D3D12_BACKGROUND=0"
rem Hair strand shaders run by default (DexNom/Belobug accuracy); set VICTORY_HAIR=0
rem only if you want to skip strand shaders for troubleshooting.
if not defined VICTORY_HAIR set "VICTORY_HAIR=1"
rem Renderer Ports 1, 5, 6, 7 (zero-copy 32-bit graphics heap, zero-copy root
rem CBVs, shared-lock/per-block write guards + parallel planning, partitioned
rem journal & early sync). Port 2 (VICTORY_PORT_DESCRIPTORS) stays opt-in (=0)
rem matching Belobug: unhooked cutscene/streaming descriptor writes can leave
rem stale descriptors and trigger NVIDIA DXGI_ERROR_DEVICE_RESET (0x887A0007).
if not defined VICTORY_PORT_CONSTANTS set "VICTORY_PORT_CONSTANTS=1"
if not defined VICTORY_PORT_DESCRIPTORS set "VICTORY_PORT_DESCRIPTORS=0"
if not defined VICTORY_PORT_CBV set "VICTORY_PORT_CBV=1"
if not defined VICTORY_PORT_GUARD set "VICTORY_PORT_GUARD=1"
if not defined VICTORY_PORT_JOURNAL set "VICTORY_PORT_JOURNAL=1"
rem GPU/CPU throughput engines adapted for RTX 5050 8 GB + Arrow Lake:
rem batch consecutive D3D12 barriers, overlap buffer uploads on high-priority
rem COPY queue (auto-capped at 128 MiB bounce VRAM on <=10 GiB GPUs), fuse
rem AVX2 under-write compare+copy, and hold newly allocated textures until
rem prior submissions finish (prevents NVIDIA GPU page faults).
if not defined VICTORY_JOIN_BARRIERS set "VICTORY_JOIN_BARRIERS=1"
if not defined VICTORY_UP_QUEUE set "VICTORY_UP_QUEUE=1"
if not defined VICTORY_UNDER_FUSED set "VICTORY_UNDER_FUSED=1"
if not defined VICTORY_SHOW_NEW_LATER set "VICTORY_SHOW_NEW_LATER=1"
if not defined VICTORY_AMBIENT_SETTLE set "VICTORY_AMBIENT_SETTLE=250,3"
if not defined VICTORY_UPLOAD_AHEAD set "VICTORY_UPLOAD_AHEAD=1"
if not defined VICTORY_LEVELS_ON_DEMAND set "VICTORY_LEVELS_ON_DEMAND=1"
if not defined VICTORY_CARD_BUFFERS_MIN_KB set "VICTORY_CARD_BUFFERS_MIN_KB=64"
rem Eliminate 200+ ms pipeline-library save hitches and keep 16 GB RAM / 8 GB VRAM
rem headroom steady during long sessions without affecting visual quality.
if not defined VICTORY_LIBRARY_STORE_LATER set "VICTORY_LIBRARY_STORE_LATER=1"
if not defined VICTORY_LIST_IDLE_TRIM_S set "VICTORY_LIST_IDLE_TRIM_S=15"
if not defined VICTORY_STAGING_IDLE_MS set "VICTORY_STAGING_IDLE_MS=15000"
if not defined VICTORY_WINDOW_IDLE_MS set "VICTORY_WINDOW_IDLE_MS=15000"
if not defined VICTORY_READ_KEEP_MB set "VICTORY_READ_KEEP_MB=8"
rem Series S default: force Rockstar's own temporal upscaler (VICTORY_UPSCALER=6)
rem instead of AMD FidelityFX FSR (7), which fails Wave32 translation on NVIDIA,
rem smears postprocessing like a watercolor painting, and crashes before gameplay.
rem Output stays native 1920x1080 (2/3 internal = 1280x720, retail Series S).
rem Redirect up to 256 MiB of loose title windows into Resizable BAR GDDR7
rem (leaving ~6.9 GiB of the 7.14 GiB DXGI VRAM budget free for Series S render
rem targets, card buffers, and streamed textures without WDDM eviction thrash).
if /i "%console_profile%"=="series-s" (
  if not defined VICTORY_OUTPUT set "VICTORY_OUTPUT=1920x1080"
  if not defined VICTORY_UPSCALER set "VICTORY_UPSCALER=6"
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
