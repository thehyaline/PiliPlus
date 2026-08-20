@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================
echo   PiliPlus 一键同步 GitHub (本地为准)
echo ============================================

REM ---------- 1. 检查 git ----------
where git >nul 2>nul
if errorlevel 1 goto :fail_git

REM ---------- 2. 检查 origin 远端 ----------
git remote get-url origin >nul 2>nul
if errorlevel 1 goto :fail_origin

REM ---------- 3. 自动提交本地改动 ----------
git add -A
git diff --cached --quiet
if errorlevel 1 (
    for /f "delims=" %%d in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') do set "TS=%%d"
    git commit -m "sync: !TS!"
    if errorlevel 1 goto :fail_commit
    echo [信息] 已自动提交: sync: !TS!
) else (
    echo [信息] 没有未提交的改动
)

REM ---------- 4. 完整镜像推送 ----------
REM 强推本地所有分支，删除云端多余分支并同步标签，使云端与本地完全一致
echo [信息] 推送中: 强推本地分支 + 删除云端多余分支 + 同步标签
git push --prune --force origin +refs/heads/*:refs/heads/* +refs/tags/*:refs/tags/*
if errorlevel 1 goto :fail_push

echo ============================================
echo   同步完成，云端已与本地完全一致
echo ============================================
pause
exit /b 0

:fail_git
echo [错误] 未找到 git，请先安装 Git for Windows
goto :fail

:fail_origin
echo [错误] 未配置 origin 远端
goto :fail

:fail_commit
echo [错误] 自动提交失败
goto :fail

:fail_push
echo [错误] 推送失败，请检查网络或 GitHub 登录凭据
goto :fail

:fail
echo.
echo [错误] 同步失败
pause
exit /b 1
