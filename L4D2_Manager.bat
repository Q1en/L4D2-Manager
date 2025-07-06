@echo off
setlocal enabledelayedexpansion

:: =================================================================
:: L4D2 服务器与插件管理器 1010
:: 作者: Q1en
:: 功能: 安装/更新 SourceMod & MetaMod, 并管理插件。
:: 日志: 修复特殊字符&导致的命令错误
:: =================================================================

:: #################### 用户配置区 (请务必修改!) ####################
::
:: 请将 "SERVER_ROOT" 设置为您的L4D2服务器根目录 (包含 srcds.exe 的目录)
::
set "SERVER_ROOT=D:\L4D2Server"
::
:: #################################################################


:: --- 脚本变量定义 ---
set "L4D2_DIR=%SERVER_ROOT%\left4dead2"
set "SCRIPT_DIR=%~dp0"
set "INSTALLER_DIR=%SCRIPT_DIR%SourceMod_Installers"
set "PLUGIN_SOURCE_DIR=%SCRIPT_DIR%Available_Plugins"
set "RECEIPTS_DIR=%SCRIPT_DIR%Installed_Receipts"
set "SCRIPT_VERSION=1010"
set "SM_INSTALLED=false"

:: --- 初始化检查 ---
if not exist "%L4D2_DIR%" (
    echo.
    echo(  错误: 找不到求生之路2服务器的游戏目录!
    echo(  请编辑此脚本文件, 并正确设置 "SERVER_ROOT" 的值。
    echo(  期望的目录: %L4D2_DIR%
    echo.
    pause
    exit
)
if exist "%L4D2_DIR%\addons\sourcemod\bin\sourcemod_mm.dll" set "SM_INSTALLED=true"
if not exist "%INSTALLER_DIR%" mkdir "%INSTALLER_DIR%"
if not exist "%PLUGIN_SOURCE_DIR%" mkdir "%PLUGIN_SOURCE_DIR%"
if not exist "%RECEIPTS_DIR%" mkdir "%RECEIPTS_DIR%"

:menu
cls
echo ========================================================
echo(        L4D2 服务器与插件管理器 %SCRIPT_VERSION%
echo ========================================================
echo.
echo(  服务器根目录: %SERVER_ROOT%
echo.
if "%SM_INSTALLED%"=="true" (
    echo(  SourceMod 状态: 已安装
) else (
    echo(  SourceMod 状态: 未找到!
)
echo.
echo(  请选择操作:
echo.
echo(    1. 安装 / 更新 SourceMod 和 MetaMod
if "%SM_INSTALLED%"=="true" (
    echo(    2. 安装一个插件
    echo(    3. 移除一个插件
)
echo.
echo(    Q. 退出
echo.
echo ========================================================

set /p choice="请输入选项编号并按回车: "

if /i "%choice%"=="1" goto installSourceMod
if /i "%choice%"=="2" if "%SM_INSTALLED%"=="true" goto installPlugin
if /i "%choice%"=="3" if "%SM_INSTALLED%"=="true" goto uninstallPlugin
if /i "%choice%"=="q" goto :eof

echo( 无效的选项, 请重新输入。
pause
goto menu


:installSourceMod
cls
:: 【已修复】使用 ^ 对 & 进行转义, 防止其被识别为命令连接符
echo(==================== 安装 SourceMod ^& MetaMod ====================
echo.
echo(  此功能将自动解压并安装最新版的 SourceMod 和 MetaMod。
echo(  请确保您已完成以下步骤:
echo(  1. 从官网下载了 SourceMod 和 MetaMod:Source 的 Windows 版本。
echo(     - MetaMod: https://www.sourcemm.net/downloads.php
echo(     - SourceMod: https://www.sourcemod.net/downloads.php
echo(  2. 将下载的 .zip 文件放入以下目录:
echo(     %INSTALLER_DIR%
echo.
pause
echo.

:: 安装 MetaMod
set "metamod_zip="
for /f "delims=" %%f in ('dir /b /o-n "%INSTALLER_DIR%\mmsource-*.zip"') do (
    set "metamod_zip=%%f"
    goto :found_mm
)
:found_mm
if defined metamod_zip (
    echo( 发现 MetaMod 安装包: %metamod_zip%
    echo( 正在解压到服务器目录...
    powershell -Command "Expand-Archive -Path '%INSTALLER_DIR%\%metamod_zip%' -DestinationPath '%L4D2_DIR%' -Force"
    echo( 解压完成。
    echo.

    echo( 正在创建 'metamod.vdf' 以引导服务器加载...
    (
        echo "Plugin"
        echo {
        echo     "file"  "addons/metamod/bin/server"
        echo }
    ) > "%L4D2_DIR%\metamod.vdf"
    echo( 'metamod.vdf' 创建成功!
    echo.
) else (
    echo( 警告: 在 "%INSTALLER_DIR%" 中未找到 MetaMod 的 .zip 安装包。
    echo.
)

:: 安装 SourceMod
set "sourcemod_zip="
for /f "delims=" %%f in ('dir /b /o-n "%INSTALLER_DIR%\sourcemod-*.zip"') do (
    set "sourcemod_zip=%%f"
    goto :found_sm
)
:found_sm
if defined sourcemod_zip (
    echo( 发现 SourceMod 安装包: %sourcemod_zip%
    echo( 正在解压到服务器目录...
    powershell -Command "Expand-Archive -Path '%INSTALLER_DIR%\%sourcemod_zip%' -DestinationPath '%L4D2_DIR%' -Force"
    echo( 解压完成。
    echo.
) else (
    echo( 警告: 在 "%INSTALLER_DIR%" 中未找到 SourceMod 的 .zip 安装包。
    echo.
)

echo =======================================================
echo(  安装流程执行完毕!
echo(  请重启您的L4D2服务器以应用所有更改。
echo(  重启后, 您可以重新运行此脚本来管理插件。
echo =======================================================
echo.
pause
set SM_INSTALLED=true
goto menu


:: ######################################################################
:: #################### 插件管理功能 (与 v2.1 相同) ####################
:: ######################################################################

:installPlugin
cls
echo ==================== 安装插件 ====================
echo.
echo(  以下是 "Available_Plugins" 目录中找到的【未安装】插件:
echo.
set /a count=0
for /d %%d in ("%PLUGIN_SOURCE_DIR%\*") do (
    if not exist "%RECEIPTS_DIR%\%%~nd.receipt" (
        set /a count+=1
        echo(    !count!. %%~nd
        set "plugin[!count!]=%%~nd"
    )
)
if %count%==0 (
    echo(  没有找到可安装的新插件。
    pause
    goto menu
)
echo.
set /p choice="请输入要安装的插件编号 (输入其他则返回): "
if not defined plugin[%choice%] goto menu
call set "plugin_name=%%plugin[%choice%]%%"

echo( 正在为 "%plugin_name%" 创建文件清单并准备安装...
(for /r "%PLUGIN_SOURCE_DIR%\%plugin_name%\" %%f in (*) do (
    set "full_path=%%f"
    set "relative_path=!full_path:%PLUGIN_SOURCE_DIR%\%plugin_name%\=!"
    echo !relative_path!
)) > "%RECEIPTS_DIR%\%plugin_name%.receipt"
echo( 清单创建完毕。

echo( 正在将文件移动到服务器目录...
robocopy "%PLUGIN_SOURCE_DIR%\%plugin_name%" "%SERVER_ROOT%" /E /MOVE /NFL /NDL /NJH /NJS /nc /ns /np > nul
echo.
echo(  成功! 插件 "%plugin_name%" 已被【移动】至服务器目录。
echo.
pause
goto menu

:uninstallPlugin
cls
echo ==================== 移除插件 ====================
echo.
echo(  以下是【已安装】的插件:
echo.
set /a count=0
for %%f in ("%RECEIPTS_DIR%\*.receipt") do (
    set /a count+=1
    echo(    !count!. %%~nf
    set "plugin[!count!]=%%~nf"
)
if %count%==0 (
    echo(  当前没有任何已安装的插件。
    pause
    goto menu
)
echo.
set /p choice="请输入要移除的插件编号 (输入其他则返回): "
if not defined plugin[%choice%] goto menu
call set "plugin_name=%%plugin[%choice%]%%"

echo( 正在从 "%plugin_name%" 的安装回执中读取文件列表...
echo.
for /f "usebackq tokens=*" %%l in ("%RECEIPTS_DIR%\%plugin_name%.receipt") do (
    set "relative_path=%%l"
    set "server_file=%SERVER_ROOT%\!relative_path!"
    set "source_file=%PLUGIN_SOURCE_DIR%\%plugin_name%\!relative_path!"
    if exist "!server_file!" (
        echo(  - 正在移回: !relative_path!
        if not exist "!source_file!\.." mkdir "!source_file!\.."
        move "!server_file!" "!source_file!" > nul
    ) else (
        echo(  - 警告: 在服务器上找不到文件 !relative_path!
    )
)
del "%RECEIPTS_DIR%\%plugin_name%.receipt"
echo.
echo(  成功! 插件 "%plugin_name%" 的所有文件已被【移回】至 Available_Plugins 目录。
echo.
pause
goto menu