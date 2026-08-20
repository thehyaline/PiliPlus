@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================
echo   PiliPlus Android 一键打包
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
echo [1/4] 生成版本信息: lib\scripts\build.ps1 android
powershell -NoProfile -ExecutionPolicy Bypass -File "lib\scripts\build.ps1" android
if errorlevel 1 goto :fail_ver

REM ---------- 4. Flutter SDK / material_ui 补丁 ----------
echo.
echo [2/4] 应用补丁: lib\scripts\patch.ps1 android
powershell -NoProfile -ExecutionPolicy Bypass -File "lib\scripts\patch.ps1" android
if errorlevel 1 goto :fail_patch

REM ---------- 5. 签名检查 ----------
echo.
if exist "android\key.properties" goto :key_ok
echo [警告] 未找到 android\key.properties，release 包将使用 debug 签名
echo        此 APK 仅可自用安装，无法上架 Google Play
echo.
echo        生成自己的签名 key:
echo          keytool -genkeypair -v -keystore android\app\key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias piliplus
echo        然后创建 android\key.properties，密钥库路径相对 android\app:
echo          storePassword=你的密码
echo          keyPassword=你的密码
echo          keyAlias=piliplus
echo          storeFile=key.jks
echo        以上文件均已被 .gitignore 忽略，不会提交到 git
echo.
goto :key_check_done
:key_ok
echo [信息] 签名配置: android\key.properties
:key_check_done

REM ---------- 6. 构建 ----------
echo.
echo [3/4] 构建 Android release APK，split-per-abi ...
call "%FLUTTER_ROOT%\bin\flutter.bat" build apk --release --split-per-abi --dart-define-from-file=pili_release.json --no-pub
if errorlevel 1 goto :fail_build

REM ---------- 7. 复制产物到 dist\android ----------
echo.
echo [4/4] 复制产物到 dist\android ...
if not exist "build\app\outputs\flutter-apk\" goto :fail_noprod
set "RELEASE_VERSION="
for /f "tokens=2 delims==" %%v in ('type "%GITHUB_ENV%" 2^>nul') do set "RELEASE_VERSION=%%v"
if not defined RELEASE_VERSION set "RELEASE_VERSION=unknown"

if not exist "dist\android" mkdir "dist\android"
for %%f in ("build\app\outputs\flutter-apk\app-*-release.apk") do (
    set "ABI=%%~nf"
    set "ABI=!ABI:app-=!"
    set "ABI=!ABI:-release=!"
    copy /y "%%f" "dist\android\PiliPlus_android_%RELEASE_VERSION%_!ABI!.apk" >nul
    if errorlevel 1 goto :fail
    call :report_apk "!ABI!"
)
goto :build_done
:report_apk
echo [信息] 产物: dist\android\PiliPlus_android_%RELEASE_VERSION%_%~1.apk
goto :eof
:build_done

echo.
echo ============================================
echo   打包完成，产物位于 dist\android\ 目录
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

:fail_build
echo [错误] 构建失败，请查看上方 Flutter 输出定位问题
echo 若提示 JDK 相关错误: 请安装 JDK 17 并设置 JAVA_HOME，或用 Android Studio 自带的 JBR
echo 若提示 Android SDK 缺失: 请安装 Android SDK 并在 flutter doctor 中确认
goto :fail

:fail_noprod
echo [错误] 未找到构建产物 build\app\outputs\flutter-apk
goto :fail

:fail
echo.
echo [错误] 打包失败，请根据上方信息排查
echo 诊断信息已写入 build_android.log
(
    echo [build_android.bat 诊断] %date% %time%
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
    echo --- android\key.properties ---
    if exist android\key.properties type android\key.properties
) > build_android.log 2>&1
pause
exit /b 1
