@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================
echo   PiliPlus Windows 一键打包
echo ============================================

where git >nul 2>nul
if errorlevel 1 goto :fail_git

REM ---------- 1. 定位 Flutter SDK ----------
REM 依次尝试: 环境变量 FLUTTER_ROOT / .fvm junction / fvm 缓存 / PATH 中的 flutter
if not defined FLUTTER_ROOT (
    for /f "delims=" %%t in ('powershell -NoProfile -Command "(Get-Item '.fvm\flutter' -ErrorAction SilentlyContinue).Target" 2^>nul') do set "FLUTTER_ROOT=%%t"
)
set "FVM_VERSION="
for /f "delims=" %%v in ('powershell -NoProfile -Command "try { (Get-Content '.fvmrc' -Raw | ConvertFrom-Json).flutter } catch {}" 2^>nul') do set "FVM_VERSION=%%v"
if not defined FLUTTER_ROOT (
    if defined FVM_VERSION if exist "%LOCALAPPDATA%\fvm\versions\!FVM_VERSION!" set "FLUTTER_ROOT=%LOCALAPPDATA%\fvm\versions\!FVM_VERSION!"
)
if not defined FLUTTER_ROOT (
    for /f "delims=" %%i in ('where flutter 2^>nul') do (
        if not defined FLUTTER_ROOT (
            for %%j in ("%%~dpi..") do set "FLUTTER_ROOT=%%~fj"
        )
    )
)
if not defined FLUTTER_ROOT goto :fail_root
if not exist "%FLUTTER_ROOT%\bin\flutter.bat" goto :fail_root_invalid
echo [信息] Flutter SDK: %FLUTTER_ROOT%
set "FLUTTER_VER="
for /f "delims=" %%v in ('type "%FLUTTER_ROOT%\version" 2^>nul') do (
    if not defined FLUTTER_VER set "FLUTTER_VER=%%v"
)
if defined FLUTTER_VER echo [信息] Flutter 版本: !FLUTTER_VER!
if defined FVM_VERSION if defined FLUTTER_VER if not "!FLUTTER_VER!"=="!FVM_VERSION!" goto :ver_warn
goto :ver_check_done
:ver_warn
echo [警告] Flutter 版本 ^(!FLUTTER_VER!^) 与 .fvmrc 要求的 !FVM_VERSION! 不一致
echo        补丁与构建可能失败，建议切换到 !FVM_VERSION!
:ver_check_done
set "PATH=%FLUTTER_ROOT%\bin;%PATH%"

REM ---------- 2. 供 lib/scripts/build.ps1 / patch.ps1 使用的 CI 环境变量 ----------
set "GITHUB_WORKSPACE=%CD%"
if not defined GITHUB_ENV (
    set "GITHUB_ENV=%TEMP%\pili_release_gh_env.txt"
    if exist "%GITHUB_ENV%" del /q "%GITHUB_ENV%"
)

REM ---------- 3. 版本生成 ----------
echo.
echo [1/4] 生成版本信息: lib\scripts\build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "lib\scripts\build.ps1"
if errorlevel 1 goto :fail_ver

REM ---------- 4. Flutter SDK / material_ui 补丁 ----------
echo.
echo [2/4] 应用补丁: lib\scripts\patch.ps1 windows
powershell -NoProfile -ExecutionPolicy Bypass -File "lib\scripts\patch.ps1" windows
if errorlevel 1 goto :fail_patch

REM ---------- 5. 构建 ----------
echo.
echo [3/4] 构建 Windows release ...
tasklist /fi "imagename eq piliplus.exe" 2>nul | find /i "piliplus.exe" >nul
if not errorlevel 1 goto :fail_running
call "%FLUTTER_ROOT%\bin\flutter.bat" build windows --release --dart-define-from-file=pili_release.json --no-pub
if errorlevel 1 goto :fail_build

REM ---------- 6. 便携版 zip ----------
echo.
echo [4/4] 打包便携版 ...
if not exist "build\windows\x64\runner\Release\" goto :fail_noprod
set "RELEASE_VERSION="
for /f "tokens=2 delims==" %%v in ('type "%GITHUB_ENV%" 2^>nul') do set "RELEASE_VERSION=%%v"
if not defined RELEASE_VERSION set "RELEASE_VERSION=unknown"

set "PORTABLE_DIR=dist\windows\PiliPlus-Win"
if exist "%PORTABLE_DIR%" rmdir /s /q "%PORTABLE_DIR%"
mkdir "%PORTABLE_DIR%"
xcopy "build\windows\x64\runner\Release\*" "%PORTABLE_DIR%\" /e /i /y >nul
if errorlevel 1 goto :fail_copy
powershell -NoProfile -Command "Compress-Archive -Path '%PORTABLE_DIR%\*' -DestinationPath 'dist\windows\PiliPlus_windows_%RELEASE_VERSION%_x64_portable.zip' -Force"
if errorlevel 1 goto :fail_zip
echo [信息] 便携版: dist\windows\PiliPlus_windows_%RELEASE_VERSION%_x64_portable.zip

REM ---------- 7. 安装包 ^(fastforge + Inno Setup, 可选^) ----------
echo.
echo [可选] 生成安装包 ...
set "HAVE_FASTFORGE="
where fastforge >nul 2>nul
if not errorlevel 1 set "HAVE_FASTFORGE=1"
if not defined HAVE_FASTFORGE (
    if exist "%LOCALAPPDATA%\Pub\Cache\bin\fastforge.bat" (
        set "HAVE_FASTFORGE=1"
        set "PATH=%LOCALAPPDATA%\Pub\Cache\bin;%PATH%"
    )
)
set "INNO_DIR=C:\Program Files (x86)\Inno Setup 6"
if not defined HAVE_FASTFORGE goto :skip_fastforge
if not exist "%INNO_DIR%\ISCC.exe" goto :skip_inno
if not exist "%INNO_DIR%\Languages\ChineseSimplified.isl" (
    copy /y "windows\packaging\exe\ChineseSimplified.isl" "%INNO_DIR%\Languages\" >nul 2>nul
    if errorlevel 1 echo [信息] Inno Setup 无中文语言文件, 安装包将改用项目内置语言文件
)
call fastforge package --platform windows --targets exe --flutter-build-args="dart-define-from-file=pili_release.json,no-pub" --skip-clean
if errorlevel 1 goto :warn_installer
REM 只移动 fastforge 生成的安装包 (dist\<版本>\ 下唯一的 setup exe)
REM 不能全盘 for /r dist: 便携版目录里的 piliplus.exe 会覆盖安装包
set "FF_SETUP="
for /r "dist\%RELEASE_VERSION%" %%f in (*setup.exe) do set "FF_SETUP=%%f"
if not defined FF_SETUP goto :warn_installer
move /y "!FF_SETUP!" "dist\windows\PiliPlus_windows_%RELEASE_VERSION%_x64_setup.exe" >nul
echo [信息] 安装包: dist\windows\PiliPlus_windows_%RELEASE_VERSION%_x64_setup.exe
goto :build_done
:skip_fastforge
echo [跳过] 未安装 fastforge，跳过安装包，安装: dart pub global activate fastforge
goto :build_done
:skip_inno
echo [跳过] 未安装 Inno Setup，跳过安装包，安装: choco install innosetup -y
goto :build_done
:warn_installer
echo [警告] 安装包生成失败, 便携版不受影响
:build_done

echo.
echo ============================================
echo   打包完成，产物位于 dist\windows\ 目录
echo   注意: build.ps1 改写了 pubspec.yaml 的 version
echo   如需恢复: git checkout pubspec.yaml
echo ============================================
pause
exit /b 0

:fail_git
echo [错误] 未找到 git，请先安装 Git 并加入 PATH
echo 安装: https://git-scm.com/download/win
goto :fail

:fail_root
echo [错误] 未找到 Flutter SDK
echo 已尝试以下方式定位:
echo   - 环境变量 FLUTTER_ROOT
echo   - .fvm\flutter junction
echo   - fvm 缓存目录 %LOCALAPPDATA%\fvm\versions\...
echo   - PATH 中的 flutter 命令
echo.
if defined FVM_VERSION goto :install_fvm
echo 请先安装 Flutter 3.47.1，推荐使用 fvm:
echo   fvm install 3.47.1
echo   fvm use
goto :install_tips_done
:install_fvm
echo 请先安装 Flutter !FVM_VERSION!，推荐使用 fvm:
echo   fvm install !FVM_VERSION!
echo   fvm use
:install_tips_done
echo 或设置环境变量 FLUTTER_ROOT 指向 Flutter SDK 目录后重试
goto :fail

:fail_root_invalid
echo [错误] FLUTTER_ROOT 无效: %FLUTTER_ROOT%
echo 请确认该目录是 Flutter SDK 根目录
goto :fail

:fail_ver
echo [错误] 版本生成失败
echo 请确认当前目录是 git 仓库且 git 可用
goto :fail

:fail_patch
echo [错误] 补丁应用失败
echo 常见原因:
echo   - Flutter SDK 版本不是 .fvmrc 指定的版本
echo   - Flutter SDK 不是 git 仓库，请用 fvm 或 git clone 方式安装
echo   - Flutter SDK 源码已被深度修改
goto :fail

:fail_running
echo [错误] 检测到 piliplus.exe 正在运行，可能藏在系统托盘，请先完全退出应用
echo        否则构建产物，如 WebView2Loader.dll，会被锁定导致构建失败
goto :fail

:fail_build
echo [错误] 构建失败，请查看上方 Flutter 输出定位问题
echo 若提示 "Unable to find suitable Visual Studio toolchain":
echo   请安装 Visual Studio 2022 或更新版本 ^(或 Build Tools^)，勾选"使用 C++ 的桌面开发"工作负载
echo   安装后运行 flutter doctor 确认，并重启终端再重试
goto :fail

:fail_noprod
echo [错误] 未找到构建产物 build\windows\x64\runner\Release
goto :fail

:fail_copy
echo [错误] 便携版文件复制失败
goto :fail

:fail_zip
echo [错误] 便携版压缩失败
goto :fail

:fail
echo.
echo [错误] 打包失败，请根据上方信息排查
echo 诊断信息已写入 build_windows.log
(
    echo [build_windows.bat 诊断] %date% %time%
    echo 工作目录: %CD%
    echo --- where git ---
    where git 2>nul
    echo --- where flutter ---
    where flutter 2>nul
    echo --- FLUTTER_ROOT ---
    echo FLUTTER_ROOT=%FLUTTER_ROOT%
    if defined FLUTTER_ROOT if exist "%FLUTTER_ROOT%\version" type "%FLUTTER_ROOT%\version"
    echo --- .fvmrc ---
    if exist .fvmrc type .fvmrc
    echo.
    echo --- GITHUB_ENV ---
    echo GITHUB_ENV=%GITHUB_ENV%
    if defined GITHUB_ENV if exist "%GITHUB_ENV%" type "%GITHUB_ENV%"
) > build_windows.log 2>&1
pause
exit /b 1
