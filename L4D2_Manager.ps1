# =================================================================
# L4D2 服务器与插件管理器 2210
# 作者: Q1en
# 功能: 部署/更新L4D2服务器, 安装/更新 SourceMod & MetaMod, 并管理插件和服务器实例。
# =================================================================

# 强制要求 PowerShell 5.1 或更高版本
#requires -Version 5.1

# #################### 用户配置区 (请务必修改!) ####################
#
# 1. 设置您的L4D2服务器根目录 (脚本将在此处创建 'l4d2_server' 文件夹)
#    例如: "D:\L4D2Server"
$ServerRootBase = "D:\L4D2Server"
#
# 2. 设置 SteamCMD.exe 的完整路径。脚本将使用它来下载和更新服务器。
#    如果文件不存在，脚本会尝试自动下载。
#    例如: "C:\steamcmd\steamcmd.exe"
$SteamCMDPath = Join-Path -Path $ServerRootBase -ChildPath "steamcmd\steamcmd.exe"
#
# 3. (可选) 预定义服务器实例配置
#    您可以在这里预设多个服务器的启动参数。
$ServerInstances = @{
    "主服_战役" = @{
        Port = 27015
        HostName = "[CN] My L4D2 Campaign Server"
        MaxPlayers = 8
        StartMap = "c1m1_hotel"
        ExtraParams = "+sv_gametypes 'coop,realism,survival'"
    }
    "副服_对抗" = @{
        Port = 27016
        HostName = "[CN] My L4D2 Versus Server"
        MaxPlayers = 8
        StartMap = "c5m1_waterfront"
        ExtraParams = "+sv_gametypes 'versus,teamversus,scavenge'"
    }
}
#
# #################################################################


# --- 脚本变量定义 ---
$ServerRoot = Join-Path -Path $ServerRootBase -ChildPath "l4d2_server" # L4D2服务器的实际路径
$L4d2Dir = Join-Path -Path $ServerRoot -ChildPath "left4dead2"
$ScriptDir = $PSScriptRoot
$InstallerDir = Join-Path -Path $ScriptDir -ChildPath "SourceMod_Installers"
$PluginSourceDir = Join-Path -Path $ScriptDir -ChildPath "Available_Plugins"
$ReceiptsDir = Join-Path -Path $ScriptDir -ChildPath "Installed_Receipts"
$RunningProcesses = @{} # 用于存储正在运行的服务器进程信息
$ScriptVersion = "2210"
$IsSourceModInstalled = $false

# --- 初始化检查 ---
if (-not (Test-Path -Path $ServerRootBase)) {
    New-Item -Path $ServerRootBase -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path -Path $L4d2Dir)) {
    Write-Host ""
    Write-Host " 提示: 未找到求生之路2服务器目录。" -ForegroundColor Cyan
    Write-Host " 您可以稍后使用菜单中的 [部署服务器] 功能进行安装。"
    Write-Host " 当前目标目录: $ServerRoot"
    Write-Host ""
    Read-Host "按回车键继续..."
}
if (Test-Path -Path (Join-Path -Path $L4d2Dir -ChildPath "addons\sourcemod\bin\sourcemod_mm.dll")) {
    $IsSourceModInstalled = $true
}
@( $InstallerDir, $PluginSourceDir, $ReceiptsDir ) | ForEach-Object {
    if (-not (Test-Path -Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}


# --- 交互式菜单核心函数 ---
function Show-InteractiveMenu {
    param(
        [Parameter(Mandatory=$true)] [System.Collections.IList]$Items,
        [Parameter(Mandatory=$true)] [string]$Title,
        [Parameter(Mandatory=$true)] [string]$ConfirmKeyChar,
        [Parameter(Mandatory=$true)] [string]$ConfirmKeyName,
        [switch]$SingleSelection
    )

    $currentIndex = 0
    $selectedIndexes = [System.Collections.Generic.List[int]]::new()

    while ($true) {
        Clear-Host
        Write-Host "$Title`n" -ForegroundColor Yellow
        
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $pointer = if ($i -eq $currentIndex) { "> " } else { "  " }
            $displayItem = $Items[$i]

            if (-not $SingleSelection) {
                 $checkbox = if ($selectedIndexes.Contains($i)) { "[✓]" } else { "[ ]" }
                 $displayItem = "$checkbox $($Items[$i])"
            }

            if ($i -eq $currentIndex) {
                Write-Host "$pointer$displayItem" -ForegroundColor Black -BackgroundColor White
            } else {
                Write-Host "$pointer$displayItem"
            }
        }
        
        Write-Host ""
        Write-Host ("-"*55)
        Write-Host "  导航:       ↑ / ↓"
        if (-not $SingleSelection) {
            Write-Host "  选择/取消:  空格键 (Spacebar)"
            Write-Host "  全选/反选:  A"
        }
        Write-Host "  确认操作:   $ConfirmKeyName ($($ConfirmKeyChar.ToUpper())) 或 Enter"
        Write-Host "  返回:       Q"
        Write-Host ("-"*55)

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        switch ($key.VirtualKeyCode) {
            38 { $currentIndex = ($currentIndex - 1 + $Items.Count) % $Items.Count } # Up
            40 { $currentIndex = ($currentIndex + 1) % $Items.Count } # Down
            32 { # Spacebar
                if (-not $SingleSelection) {
                    if ($selectedIndexes.Contains($currentIndex)) { [void]$selectedIndexes.Remove($currentIndex) }
                    else { $selectedIndexes.Add($currentIndex) }
                }
            }
            65 { # 'A' key for All/None
                 if (-not $SingleSelection) {
                    if ($selectedIndexes.Count -lt $Items.Count) {
                        $selectedIndexes.Clear(); 0..($Items.Count - 1) | ForEach-Object { $selectedIndexes.Add($_) }
                    } else {
                        $selectedIndexes.Clear()
                    }
                }
            }
            81 { return $null } # 'Q' key for Quit
            13 { # Enter Key
                if ($SingleSelection) { return $Items[$currentIndex] }
                else { return $selectedIndexes | ForEach-Object { $Items[$_] } }
            }
        }
        
        if ($key.Character -eq $ConfirmKeyChar.ToLower()) {
             if ($SingleSelection) { return $Items[$currentIndex] }
             else { return $selectedIndexes | ForEach-Object { $Items[$_] } }
        }
    }
}


# --- 辅助函数 (插件操作的核心逻辑) ---
#region 辅助函数
function Invoke-PluginInstallation {
    param([Parameter(Mandatory=$true)] [System.IO.DirectoryInfo]$PluginObject)
    $pluginName = $PluginObject.Name
    $pluginPath = $PluginObject.FullName
    $receiptPath = Join-Path -Path $ReceiptsDir -ChildPath "$pluginName.receipt"
    Write-Host "`n--- 开始安装 '$pluginName' ---" -ForegroundColor White
    try {
        Write-Host " > 正在创建文件清单..."
        Get-ChildItem -Path $pluginPath -Recurse -File | ForEach-Object {
            $_.FullName.Substring($pluginPath.Length + 1)
        } | Out-File -FilePath $receiptPath -Encoding utf8
        Write-Host " > 正在将文件复制到服务器目录..."
        robocopy $pluginPath $ServerRoot /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
        Remove-Item -Path $pluginPath -Recurse -Force # 使用复制+删除代替移动，避免跨驱动器问题
        Write-Host "   成功! 插件 '$pluginName' 已安装。" -ForegroundColor Green
    } catch {
        Write-Host "   错误! 安装插件 '$pluginName' 时发生意外: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-PluginUninstallation {
    param([Parameter(Mandatory=$true)] [System.IO.FileInfo]$ReceiptObject)
    $pluginName = $ReceiptObject.BaseName
    $receiptPath = $ReceiptObject.FullName
    Write-Host "`n--- 开始移除 '$pluginName' ---" -ForegroundColor White
    try {
        $filesToMove = Get-Content -Path $receiptPath
        foreach ($relativePath in $filesToMove) {
            $serverFile = Join-Path -Path $ServerRoot -ChildPath $relativePath
            
            $pluginReclaimFolder = Join-Path -Path $PluginSourceDir -ChildPath $pluginName
            $destinationFile = Join-Path -Path $pluginReclaimFolder -ChildPath $relativePath
            
            if (Test-Path -Path $serverFile) {
                $parentDir = Split-Path -Path $destinationFile -Parent
                if (-not (Test-Path -Path $parentDir)) {
                    New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
                }
                Move-Item -Path $serverFile -Destination $destinationFile -Force
            }
        }
        # 清理空目录
        Get-Content $receiptPath | ForEach-Object { Split-Path -Path $_ -Parent } | Sort-Object -Unique | Sort-Object -Property Length -Descending | ForEach-Object {
            if (-not [string]::IsNullOrEmpty($_)) {
                $dirOnServer = Join-Path -Path $ServerRoot -ChildPath $_
                if ((Test-Path $dirOnServer) -and -not (Get-ChildItem -Path $dirOnServer)) {
                    Remove-Item -Path $dirOnServer -Force -ErrorAction SilentlyContinue
                }
            }
        }
        Remove-Item -Path $receiptPath -Force
        Write-Host " > 成功! 插件 '$pluginName' 的所有文件已被移回。" -ForegroundColor Green
    } catch {
        Write-Host " > 错误! 移除插件 '$pluginName' 时发生意外: $($_.Exception.Message)" -ForegroundColor Red
    }
}
#endregion


# --- 核心功能函数 ---
#region 服务器部署
function Deploy-L4D2Server {
    Clear-Host
    Write-Host "==================== 部署L4D2专用服务器 ===================="
    Write-Host "`n此功能将使用 SteamCMD 下载或更新 Left 4 Dead 2 Dedicated Server。"
    Write-Host "服务器将被安装到: $ServerRoot"
    Write-Host "将使用 SteamCMD: $SteamCMDPath"
    Write-Host ""
    
    # 检查并下载SteamCMD
    if (-not (Test-Path $SteamCMDPath)) {
        Write-Host "未找到 SteamCMD，将尝试自动下载..." -ForegroundColor Yellow
        $steamCmdDir = Split-Path -Path $SteamCMDPath -Parent
        if (-not (Test-Path $steamCmdDir)) {
            New-Item -Path $steamCmdDir -ItemType Directory -Force | Out-Null
        }
        $zipPath = Join-Path $steamCmdDir "steamcmd.zip"
        try {
            Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile $zipPath
            Expand-Archive -Path $zipPath -DestinationPath $steamCmdDir -Force
            Remove-Item -Path $zipPath
            Write-Host "SteamCMD 下载并解压成功!" -ForegroundColor Green
        } catch {
            Write-Host "下载 SteamCMD 失败: $($_.Exception.Message)" -ForegroundColor Red
            Read-Host "请手动下载 SteamCMD 并将其放置在 '$SteamCMDPath'。按回车键返回。"
            return
        }
    }

    Write-Host "`n准备就绪，即将开始执行 SteamCMD..."
    Read-Host "按回车键开始部署..."

    # 执行SteamCMD命令
    $steamCmdArgs = "+force_install_dir `"$ServerRoot`" +login anonymous +app_update 222860 validate +quit"
    try {
        $process = Start-Process -FilePath $SteamCMDPath -ArgumentList $steamCmdArgs -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Host "`nL4D2 服务器文件部署/更新成功!" -ForegroundColor Green
        } else {
            Write-Host "`nSteamCMD 执行过程中可能出现问题 (退出代码: $($process.ExitCode))。" -ForegroundColor Yellow
            Write-Host "请检查上面的日志输出。"
        }
    } catch {
         Write-Host "`n执行 SteamCMD 失败: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "=========================================================="
    Read-Host "`n按回车键返回主菜单..."
}
#endregion

#region 服务器实例管理
function Manage-ServerInstances {
    while ($true) {
        Clear-Host
        Write-Host "==================== 服务器实例管理 ===================="
        Write-Host "`n当前正在运行的实例:"
        if ($RunningProcesses.Count -eq 0) {
            Write-Host "  (无)"
        } else {
            $RunningProcesses.GetEnumerator() | ForEach-Object {
                Write-Host "  - $($_.Name) (端口: $($_.Value.Port), PID: $($_.Value.PID))" -ForegroundColor Green
            }
        }
        Write-Host "`n请选择操作:"
        Write-Host "  1. 启动一个新的服务器实例"
        Write-Host "  2. 关闭一个正在运行的实例"
        Write-Host "  3. 生成服务器定时任务命令行"
        Write-Host "`n  Q. 返回主菜单"
        Write-Host "========================================================"
        
        $choice = Read-Host "请输入选项编号并按回车"
        switch ($choice) {
            "1" { Start-L4D2ServerInstance }
            "2" { Stop-L4D2ServerInstance }
            "3" { Generate-ScheduledTaskCommands }
            "q" { return }
        }
    }
}

function Start-L4D2ServerInstance {
    $srcdsPath = Join-Path -Path $ServerRoot -ChildPath "srcds.exe"
    if (-not (Test-Path $srcdsPath)) {
        Write-Host "`n错误: 找不到 srcds.exe。请先部署服务器。" -ForegroundColor Red
        Read-Host "按回车键返回..."
        return
    }

    $instanceOptions = $ServerInstances.Keys | ForEach-Object { "$_ (端口: $($ServerInstances[$_].Port))" }
    $instanceOptions += "手动配置新实例"
    
    $selected = Show-InteractiveMenu -Items $instanceOptions -Title "请选择要启动的服务器实例配置" -ConfirmKeyChar 's' -ConfirmKeyName "启动" -SingleSelection

    if (-not $selected) { return }

    $config = $null
    if ($selected -eq "手动配置新实例") {
        Write-Host "`n--- 手动配置新实例 ---" -ForegroundColor Yellow
        $config = @{
            Port = Read-Host "请输入端口号 (例如 27015)"
            HostName = Read-Host "请输入服务器名称"
            MaxPlayers = Read-Host "请输入最大玩家数 (例如 8)"
            StartMap = Read-Host "请输入初始地图 (例如 c1m1_hotel)"
            ExtraParams = Read-Host "请输入其他启动参数 (可留空)"
        }
    } else {
        $instanceName = ($selected -split ' ')[0]
        $config = $ServerInstances[$instanceName]
        $config.Name = $instanceName # 将名称加入配置中
    }
    
    # 检查端口是否已被此脚本启动的进程占用
    $portInUse = $RunningProcesses.Values | Where-Object { $_.Port -eq $config.Port }
    if ($portInUse) {
        Write-Host "`n错误: 端口 $($config.Port) 已被实例 '$($portInUse.Name)' 占用 (PID: $($portInUse.PID))。" -ForegroundColor Red
        Read-Host "按回车键返回..."
        return
    }

    # 构建启动参数
    $launchArgs = "-console -game left4dead2 -insecure +sv_lan 0 +ip 0.0.0.0 -port $($config.Port) +maxplayers $($config.MaxPlayers) +map $($config.StartMap) +hostname `"$($config.HostName)`" $($config.ExtraParams)"
    
    Write-Host "`n即将使用以下参数启动服务器:" -ForegroundColor Cyan
    Write-Host " $srcdsPath $launchArgs"
    
    try {
        $process = Start-Process -FilePath $srcdsPath -ArgumentList $launchArgs -PassThru
        $instanceName = if ($config.Name) { $config.Name } else { "手动实例_port$($config.Port)" }
        $RunningProcesses[$instanceName] = @{ PID = $process.Id; Port = $config.Port; Name = $instanceName }
        Write-Host "`n服务器实例 '$instanceName' 已成功启动! (PID: $($process.Id))" -ForegroundColor Green
    } catch {
        Write-Host "`n启动服务器失败: $($_.Exception.Message)" -ForegroundColor Red
    }
    Read-Host "按回车键返回..."
}

function Stop-L4D2ServerInstance {
    if ($RunningProcesses.Count -eq 0) {
        Write-Host "`n当前没有由本脚本启动的正在运行的实例。" -ForegroundColor Yellow
        Read-Host "按回车键返回..."
        return
    }

    $runningNames = $RunningProcesses.Keys | ForEach-Object { "$_ (PID: $($RunningProcesses[$_].PID))" }
    $selected = Show-InteractiveMenu -Items $runningNames -Title "请选择要关闭的服务器实例" -ConfirmKeyChar 'k' -ConfirmKeyName "关闭" -SingleSelection

    if (-not $selected) { return }

    $instanceNameToStop = ($selected -split ' ')[0]
    $processInfo = $RunningProcesses[$instanceNameToStop]

    Write-Host "`n正在尝试关闭实例 '$instanceNameToStop' (PID: $($processInfo.PID))..."
    try {
        Stop-Process -Id $processInfo.PID -Force -ErrorAction Stop
        Write-Host "进程已成功关闭。" -ForegroundColor Green
        $RunningProcesses.Remove($instanceNameToStop)
    } catch {
        Write-Host "关闭进程失败: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "该进程可能已被手动关闭。"
        $RunningProcesses.Remove($instanceNameToStop) # 无论如何都从列表中移除
    }
    Read-Host "按回车键返回..."
}

function Generate-ScheduledTaskCommands {
    Clear-Host
    Write-Host "==================== 生成定时任务命令行 ===================="
    Write-Host "此功能会为您预设的服务器实例生成用于 Windows 任务计划程序的命令行。"
    Write-Host "您可以复制这些命令来创建定时开机和关机任务。"
    Write-Host "------------------------------------------------------------`n"

    if ($ServerInstances.Count -eq 0) {
        Write-Host "您尚未在脚本中预定义任何服务器实例 (`$ServerInstances`)。" -ForegroundColor Yellow
        Read-Host "按回车键返回..."
        return
    }
    
    $srcdsPath = Join-Path -Path $ServerRoot -ChildPath "srcds.exe"

    foreach ($name in $ServerInstances.Keys) {
        $config = $ServerInstances[$name]
        $launchArgs = "-console -game left4dead2 -insecure +sv_lan 0 +ip 0.0.0.0 -port $($config.Port) +maxplayers $($config.MaxPlayers) +map $($config.StartMap) +hostname `"$($config.HostName)`" $($config.ExtraParams)"
        
        Write-Host "实例: '$name'" -ForegroundColor Yellow
        
        # 启动命令
        Write-Host "  [定时启动] 命令:" -ForegroundColor Green
        Write-Host "    程序/脚本: " -NoNewline; Write-Host "`"$srcdsPath`"" -ForegroundColor Cyan
        Write-Host "    添加参数: " -NoNewline; Write-Host $launchArgs -ForegroundColor Cyan
        
        # 关闭命令
        $taskkillCmd = "taskkill /F /IM srcds.exe /FI `"hostname eq $($config.HostName)`"" # 注意：此方法依赖于hostname，不够精确
        $taskkillCmdPrecise = "wmic process where `"commandline like '%-port $($config.Port)%`" call terminate" # 更精确的方法
        Write-Host "  [定时关闭] 命令 (推荐，较精确):" -ForegroundColor Green
        Write-Host "    程序/脚本: " -NoNewline; Write-Host "wmic" -ForegroundColor Cyan
        Write-Host "    添加参数: " -NoNewline; Write-Host "process where `"commandline like '%-port $($config.Port)%'`" call terminate" -ForegroundColor Cyan
        Write-Host ""
    }

    Write-Host "========================================================"
    Write-Host "提示: 'wmic' 命令更为精确，因为它通过端口号来识别进程。"
    Write-Host "请在创建任务计划程序时，将“程序/脚本”和“添加参数”分别填入对应栏位。"
    Read-Host "`n按回车键返回..."
}
#endregion

#region 安装 SourceMod 和 MetaMod
function Install-SourceModAndMetaMod {
    Clear-Host
    Write-Host "==================== 安装 SourceMod & MetaMod ===================="
    if (-not(Test-Path -Path (Join-Path -Path $ServerRoot -ChildPath "srcds.exe"))) {
        Write-Host "`n错误: 服务器尚未部署 (找不到srcds.exe)。" -ForegroundColor Red
        Write-Host "请先从主菜单选择 [部署服务器] 选项。"
        Read-Host "按回车键返回..."
        return
    }
    Write-Host "`n此功能将自动解压并安装最新版的 SourceMod 和 MetaMod。"
    Write-Host "请确保您已完成以下步骤:"
    Write-Host "1. 从官网下载了 SourceMod 和 MetaMod:Source 的 Windows 版本。"
    Write-Host "   - MetaMod: https://www.sourcemm.net/downloads.php"
    Write-Host "   - SourceMod: https://www.sourcemod.net/downloads.php"
    Write-Host "2. 将下载的 .zip 文件放入以下目录:"
    Write-Host "   $InstallerDir"
    Read-Host "`n准备就绪后，按回车键开始安装..."
    Write-Host ""

    # 安装 MetaMod
    $metamodZip = Get-ChildItem -Path $InstallerDir -Filter "mmsource-*.zip" | Sort-Object Name -Descending | Select-Object -First 1
    if ($metamodZip) {
        Write-Host "发现 MetaMod 安装包: $($metamodZip.Name)"
        Write-Host "正在解压到服务器目录..."
        try {
            Expand-Archive -Path $metamodZip.FullName -DestinationPath $L4d2Dir -Force -ErrorAction Stop
            Write-Host "解压完成。" -ForegroundColor Green
            Write-Host "正在创建 'metamod.vdf' 以引导服务器加载..."
            $vdfContent = @"
"Plugin"
{
    "file"  "addons/metamod/bin/server"
}
"@
            [System.IO.File]::WriteAllText((Join-Path $L4d2Dir "metamod.vdf"), $vdfContent, [System.Text.Encoding]::Default)
            Write-Host "'metamod.vdf' 创建成功!`n" -ForegroundColor Green
        } catch {
            Write-Host "解压 MetaMod 时出错: $($_.Exception.Message)`n" -ForegroundColor Red
        }
    } else {
        Write-Host "警告: 在 '$InstallerDir' 中未找到 MetaMod 的 .zip 安装包。`n" -ForegroundColor Yellow
    }

    # 安装 SourceMod
    $sourcemodZip = Get-ChildItem -Path $InstallerDir -Filter "sourcemod-*.zip" | Sort-Object Name -Descending | Select-Object -First 1
    if ($sourcemodZip) {
        Write-Host "发现 SourceMod 安装包: $($sourcemodZip.Name)"
        Write-Host "正在解压到服务器目录..."
        try {
            Expand-Archive -Path $sourcemodZip.FullName -DestinationPath $L4d2Dir -Force -ErrorAction Stop
            Write-Host "解压完成。`n" -ForegroundColor Green
        } catch {
            Write-Host "解压 SourceMod 时出错: $($_.Exception.Message)`n" -ForegroundColor Red
        }
    } else {
        Write-Host "警告: 在 '$InstallerDir' 中未找到 SourceMod 的 .zip 安装包。`n" -ForegroundColor Yellow
    }

    Write-Host "======================================================="
    Write-Host " 安装流程执行完毕!" -ForegroundColor Cyan
    Write-Host " 请重启您的L4D2服务器以应用所有更改。"
    Write-Host " 重启后, 您可以重新运行此脚本来管理插件。"
    Write-Host "======================================================="
    Write-Host ""
    if (Test-Path (Join-Path $L4d2Dir "addons\sourcemod\bin\sourcemod_mm.dll")) {
        $script:IsSourceModInstalled = $true
    }
    Read-Host "按回车键返回主菜单..."
}
#endregion

#region 插件管理功能
function Install-L4D2Plugin {
    if (-not $IsSourceModInstalled) {
        Write-Host "`n错误: SourceMod尚未安装，无法管理插件。" -ForegroundColor Red
        Read-Host "请先安装SourceMod。按回车键返回..."
        return
    }
    $availablePlugins = @(Get-ChildItem -Path $PluginSourceDir -Directory | Where-Object { -not (Test-Path (Join-Path $ReceiptsDir "$($_.Name).receipt")) })
    if ($availablePlugins.Count -eq 0) {
        Clear-Host
        Write-Host "没有找到可安装的新插件。"
        Write-Host "请将插件文件夹放入 '$PluginSourceDir' 目录中。"
        Read-Host "按回车键返回主菜单..."
        return
    }
    
    $pluginNames = $availablePlugins | ForEach-Object { $_.Name }
    $selectedNames = Show-InteractiveMenu -Items $pluginNames -Title "请选择要安装的插件" -ConfirmKeyChar 'i' -ConfirmKeyName "安装"

    Clear-Host
    if ($null -eq $selectedNames -or $selectedNames.Count -eq 0) {
        Write-Host "未选择任何插件或操作已取消。"
        Read-Host "按回车键返回主菜单..."
        return
    }

    $pluginsToInstall = $availablePlugins | Where-Object { $selectedNames -contains $_.Name }
    foreach ($plugin in $pluginsToInstall) {
        Invoke-PluginInstallation -PluginObject $plugin
    }

    Write-Host "`n`n所有选定的插件均已处理完毕。" -ForegroundColor Cyan
    Read-Host "按回车键返回主菜单..."
}

function Uninstall-L4D2Plugin {
     if (-not $IsSourceModInstalled) {
        Write-Host "`n错误: SourceMod尚未安装，无法管理插件。" -ForegroundColor Red
        Read-Host "请先安装SourceMod。按回车键返回..."
        return
    }
    $installedPlugins = @(Get-ChildItem -Path $ReceiptsDir -Filter "*.receipt")
    if ($installedPlugins.Count -eq 0) {
        Clear-Host
        Write-Host "当前没有任何已安装的插件。"
        Read-Host "按回车键返回主菜单..."
        return
    }

    $pluginNames = $installedPlugins | ForEach-Object { $_.BaseName }
    $selectedNames = Show-InteractiveMenu -Items $pluginNames -Title "请选择要移除的插件" -ConfirmKeyChar 'r' -ConfirmKeyName "移除"

    Clear-Host
    if ($null -eq $selectedNames -or $selectedNames.Count -eq 0) {
        Write-Host "未选择任何插件或操作已取消。"
        Read-Host "按回车键返回主菜单..."
        return
    }
    
    $receiptsToProcess = $installedPlugins | Where-Object { $selectedNames -contains $_.BaseName }
    foreach ($receipt in $receiptsToProcess) {
        Invoke-PluginUninstallation -ReceiptObject $receipt
    }

    Write-Host "`n`n所有选定的插件均已处理完毕。" -ForegroundColor Cyan
    Read-Host "按回车键返回主菜单..."
}
#endregion


# --- 主菜单与循环 ---
#region 主菜单
function Show-Menu {
    Clear-Host
    $ServerStatus = if (Test-Path -Path (Join-Path $ServerRoot "srcds.exe")) { 
        Write-Host " 服务器状态: 已部署" -ForegroundColor Green
    } else {
        Write-Host " 服务器状态: 未部署" -ForegroundColor Yellow
    }
    if (Test-Path (Join-Path $L4d2Dir "addons\sourcemod\bin\sourcemod_mm.dll")) {
        $script:IsSourceModInstalled = $true
    } else {
        $script:IsSourceModInstalled = $false
    }
    
    Write-Host "========================================================"
    Write-Host "    L4D2 服务器与插件管理器 $ScriptVersion"
    Write-Host "========================================================"
    Write-Host ""
    Write-Host " 服务器根目录: $ServerRootBase"
    $ServerStatus
    if ($IsSourceModInstalled) {
        Write-Host " SourceMod 状态: 已安装" -ForegroundColor Green
    } else {
        Write-Host " SourceMod 状态: 未找到!" -ForegroundColor Yellow
    }
    if ($RunningProcesses.Count -gt 0) {
        Write-Host " 运行中实例数: $($RunningProcesses.Count)" -ForegroundColor Cyan
    }
    Write-Host "`n ================ 服务器管理 ================"
    Write-Host "   1. 部署/更新 L4D2 服务器文件"
    Write-Host "   2. 管理服务器实例 (启动/关闭/定时)"
    Write-Host "`n ================ 插件管理 ================"
    Write-Host "   3. 安装 / 更新 SourceMod 和 MetaMod"
    Write-Host "   4. 安装插件"
    Write-Host "   5. 移除插件"
    Write-Host "`n   Q. 退出`n"
    Write-Host "========================================================"
}

# 脚本主循环
while ($true) {
    Show-Menu
    $choice = Read-Host "请输入选项编号并按回车"
    switch ($choice) {
        "1" { Deploy-L4D2Server }
        "2" { Manage-ServerInstances }
        "3" { Install-SourceModAndMetaMod }
        "4" { Install-L4D2Plugin }
        "5" { Uninstall-L4D2Plugin }
        "q" { 
            if ($RunningProcesses.Count -gt 0) {
                Write-Host "`n警告: 有 $($RunningProcesses.Count) 个服务器实例仍在运行。" -ForegroundColor Yellow
                $confirm = Read-Host "退出脚本不会关闭这些服务器。确认退出吗? (y/n)"
                if ($confirm -ne 'y') { continue }
            }
            Write-Host "正在退出..."; exit 
        }
    }
}
#endregion
