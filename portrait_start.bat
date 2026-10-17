@echo off
REM ============================================================
REM 竖屏启动脚本（plan-2026.10.15.a）：窗口 720x1280，宽<高，
REM Layout 判竖屏，内容基准自动切到 720x1280（上棋盘 / 下信息区）。
REM
REM 用法：双击本文件即可；追加参数原样传给 Godot，例如：
REM   portrait_start.bat -f        （全屏竖屏）
REM   portrait_start.bat -- auto   （AI 接管人类座位，自动演示）
REM
REM exe 按本机约定（rule-godot-命令与验证指南 §2.2）放在仓库
REM 上一级目录 E:/project_godot/，不进 git。
REM ============================================================
setlocal
set "EXE=%~dp0..\Godot_v4.7.2-stable_win64.exe"

if not exist "%EXE%" (
    echo [portrait_start] 找不到 Godot: %EXE%
    echo [portrait_start] 请把 Godot_v4.7.2-stable_win64.exe 拷到 E:/project_godot/
    pause
    exit /b 1
)

"%EXE%" --path "%~dp0" --resolution 720x1280 %*
