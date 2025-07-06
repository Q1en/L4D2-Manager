@echo off
setlocal enabledelayedexpansion

:: =================================================================
:: L4D2 ���������������� 1010
:: ����: Q1en
:: ����: ��װ/���� SourceMod & MetaMod, ����������
:: ��־: �޸������ַ�&���µ��������
:: =================================================================

:: #################### �û������� (������޸�!) ####################
::
:: �뽫 "SERVER_ROOT" ����Ϊ����L4D2��������Ŀ¼ (���� srcds.exe ��Ŀ¼)
::
set "SERVER_ROOT=D:\L4D2Server"
::
:: #################################################################


:: --- �ű��������� ---
set "L4D2_DIR=%SERVER_ROOT%\left4dead2"
set "SCRIPT_DIR=%~dp0"
set "INSTALLER_DIR=%SCRIPT_DIR%SourceMod_Installers"
set "PLUGIN_SOURCE_DIR=%SCRIPT_DIR%Available_Plugins"
set "RECEIPTS_DIR=%SCRIPT_DIR%Installed_Receipts"
set "SCRIPT_VERSION=1010"
set "SM_INSTALLED=false"

:: --- ��ʼ����� ---
if not exist "%L4D2_DIR%" (
    echo.
    echo(  ����: �Ҳ�������֮·2����������ϷĿ¼!
    echo(  ��༭�˽ű��ļ�, ����ȷ���� "SERVER_ROOT" ��ֵ��
    echo(  ������Ŀ¼: %L4D2_DIR%
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
echo(        L4D2 ���������������� %SCRIPT_VERSION%
echo ========================================================
echo.
echo(  ��������Ŀ¼: %SERVER_ROOT%
echo.
if "%SM_INSTALLED%"=="true" (
    echo(  SourceMod ״̬: �Ѱ�װ
) else (
    echo(  SourceMod ״̬: δ�ҵ�!
)
echo.
echo(  ��ѡ�����:
echo.
echo(    1. ��װ / ���� SourceMod �� MetaMod
if "%SM_INSTALLED%"=="true" (
    echo(    2. ��װһ�����
    echo(    3. �Ƴ�һ�����
)
echo.
echo(    Q. �˳�
echo.
echo ========================================================

set /p choice="������ѡ���Ų����س�: "

if /i "%choice%"=="1" goto installSourceMod
if /i "%choice%"=="2" if "%SM_INSTALLED%"=="true" goto installPlugin
if /i "%choice%"=="3" if "%SM_INSTALLED%"=="true" goto uninstallPlugin
if /i "%choice%"=="q" goto :eof

echo( ��Ч��ѡ��, ���������롣
pause
goto menu


:installSourceMod
cls
:: �����޸���ʹ�� ^ �� & ����ת��, ��ֹ�䱻ʶ��Ϊ�������ӷ�
echo(==================== ��װ SourceMod ^& MetaMod ====================
echo.
echo(  �˹��ܽ��Զ���ѹ����װ���°�� SourceMod �� MetaMod��
echo(  ��ȷ������������²���:
echo(  1. �ӹ��������� SourceMod �� MetaMod:Source �� Windows �汾��
echo(     - MetaMod: https://www.sourcemm.net/downloads.php
echo(     - SourceMod: https://www.sourcemod.net/downloads.php
echo(  2. �����ص� .zip �ļ���������Ŀ¼:
echo(     %INSTALLER_DIR%
echo.
pause
echo.

:: ��װ MetaMod
set "metamod_zip="
for /f "delims=" %%f in ('dir /b /o-n "%INSTALLER_DIR%\mmsource-*.zip"') do (
    set "metamod_zip=%%f"
    goto :found_mm
)
:found_mm
if defined metamod_zip (
    echo( ���� MetaMod ��װ��: %metamod_zip%
    echo( ���ڽ�ѹ��������Ŀ¼...
    powershell -Command "Expand-Archive -Path '%INSTALLER_DIR%\%metamod_zip%' -DestinationPath '%L4D2_DIR%' -Force"
    echo( ��ѹ��ɡ�
    echo.

    echo( ���ڴ��� 'metamod.vdf' ����������������...
    (
        echo "Plugin"
        echo {
        echo     "file"  "addons/metamod/bin/server"
        echo }
    ) > "%L4D2_DIR%\metamod.vdf"
    echo( 'metamod.vdf' �����ɹ�!
    echo.
) else (
    echo( ����: �� "%INSTALLER_DIR%" ��δ�ҵ� MetaMod �� .zip ��װ����
    echo.
)

:: ��װ SourceMod
set "sourcemod_zip="
for /f "delims=" %%f in ('dir /b /o-n "%INSTALLER_DIR%\sourcemod-*.zip"') do (
    set "sourcemod_zip=%%f"
    goto :found_sm
)
:found_sm
if defined sourcemod_zip (
    echo( ���� SourceMod ��װ��: %sourcemod_zip%
    echo( ���ڽ�ѹ��������Ŀ¼...
    powershell -Command "Expand-Archive -Path '%INSTALLER_DIR%\%sourcemod_zip%' -DestinationPath '%L4D2_DIR%' -Force"
    echo( ��ѹ��ɡ�
    echo.
) else (
    echo( ����: �� "%INSTALLER_DIR%" ��δ�ҵ� SourceMod �� .zip ��װ����
    echo.
)

echo =======================================================
echo(  ��װ����ִ�����!
echo(  ����������L4D2��������Ӧ�����и��ġ�
echo(  ������, �������������д˽ű�����������
echo =======================================================
echo.
pause
set SM_INSTALLED=true
goto menu


:: ######################################################################
:: #################### ��������� (�� v2.1 ��ͬ) ####################
:: ######################################################################

:installPlugin
cls
echo ==================== ��װ��� ====================
echo.
echo(  ������ "Available_Plugins" Ŀ¼���ҵ��ġ�δ��װ�����:
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
    echo(  û���ҵ��ɰ�װ���²����
    pause
    goto menu
)
echo.
set /p choice="������Ҫ��װ�Ĳ����� (���������򷵻�): "
if not defined plugin[%choice%] goto menu
call set "plugin_name=%%plugin[%choice%]%%"

echo( ����Ϊ "%plugin_name%" �����ļ��嵥��׼����װ...
(for /r "%PLUGIN_SOURCE_DIR%\%plugin_name%\" %%f in (*) do (
    set "full_path=%%f"
    set "relative_path=!full_path:%PLUGIN_SOURCE_DIR%\%plugin_name%\=!"
    echo !relative_path!
)) > "%RECEIPTS_DIR%\%plugin_name%.receipt"
echo( �嵥������ϡ�

echo( ���ڽ��ļ��ƶ���������Ŀ¼...
robocopy "%PLUGIN_SOURCE_DIR%\%plugin_name%" "%SERVER_ROOT%" /E /MOVE /NFL /NDL /NJH /NJS /nc /ns /np > nul
echo.
echo(  �ɹ�! ��� "%plugin_name%" �ѱ����ƶ�����������Ŀ¼��
echo.
pause
goto menu

:uninstallPlugin
cls
echo ==================== �Ƴ���� ====================
echo.
echo(  �����ǡ��Ѱ�װ���Ĳ��:
echo.
set /a count=0
for %%f in ("%RECEIPTS_DIR%\*.receipt") do (
    set /a count+=1
    echo(    !count!. %%~nf
    set "plugin[!count!]=%%~nf"
)
if %count%==0 (
    echo(  ��ǰû���κ��Ѱ�װ�Ĳ����
    pause
    goto menu
)
echo.
set /p choice="������Ҫ�Ƴ��Ĳ����� (���������򷵻�): "
if not defined plugin[%choice%] goto menu
call set "plugin_name=%%plugin[%choice%]%%"

echo( ���ڴ� "%plugin_name%" �İ�װ��ִ�ж�ȡ�ļ��б�...
echo.
for /f "usebackq tokens=*" %%l in ("%RECEIPTS_DIR%\%plugin_name%.receipt") do (
    set "relative_path=%%l"
    set "server_file=%SERVER_ROOT%\!relative_path!"
    set "source_file=%PLUGIN_SOURCE_DIR%\%plugin_name%\!relative_path!"
    if exist "!server_file!" (
        echo(  - �����ƻ�: !relative_path!
        if not exist "!source_file!\.." mkdir "!source_file!\.."
        move "!server_file!" "!source_file!" > nul
    ) else (
        echo(  - ����: �ڷ��������Ҳ����ļ� !relative_path!
    )
)
del "%RECEIPTS_DIR%\%plugin_name%.receipt"
echo.
echo(  �ɹ�! ��� "%plugin_name%" �������ļ��ѱ����ƻء��� Available_Plugins Ŀ¼��
echo.
pause
goto menu