# =================================================================
# L4D2 服务器与插件管理器 2100 (PowerShell 交互版)
# 作者: Q1en
# 功能: 安装/更新 SourceMod & MetaMod, 并管理插件。
# =================================================================

# 强制要求 PowerShell 5.1 或更高版本
#requires -Version 5.1

# #################### 用户配置区 (请务必修改!) ####################
#
# 请将 "$ServerRoot" 设置为您的L4D2服务器根目录 (包含 srcds.exe 的目录)
#
$ServerRoot = "D:\L4D2Server"
#
# #################################################################


# --- 脚本变量定义 ---
$L4d2Dir = Join-Path -Path $ServerRoot -ChildPath "left4dead2"
$ScriptDir = $PSScriptRoot
$InstallerDir = Join-Path -Path $ScriptDir -ChildPath "SourceMod_Installers"
$PluginSourceDir = Join-Path -Path $ScriptDir -ChildPath "Available_Plugins"
$ReceiptsDir = Join-Path -Path $ScriptDir -ChildPath "Installed_Receipts"
$ScriptVersion = "2100 (交互版)"
$IsSourceModInstalled = $false

# --- 初始化检查 ---
if (-not (Test-Path -Path $L4d2Dir)) {
    Write-Host ""
    Write-Host " 错误: 找不到求生之路2服务器的游戏目录!" -ForegroundColor Red
    Write-Host " 请编辑此脚本文件, 并正确设置 `$ServerRoot` 的值。"
    Write-Host " 期望的目录: $L4d2Dir"
    Write-Host ""
    Read-Host "按回车键退出..."
    exit
}
if (Test-Path -Path (Join-Path -Path $L4d2Dir -ChildPath "addons\sourcemod\bin\sourcemod_mm.dll")) {
    $IsSourceModInstalled = $true
}
@( $InstallerDir, $PluginSourceDir, $ReceiptsDir ) | ForEach-Object {
    if (-not (Test-Path -Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}


# --- 新增：交互式菜单核心函数 ---
function Show-InteractiveMenu {
    param(
        [Parameter(Mandatory=$true)] [System.Collections.IList]$Items,
        [Parameter(Mandatory=$true)] [string]$Title,
        [Parameter(Mandatory=$true)] [string]$ConfirmKeyChar,
        [Parameter(Mandatory=$true)] [string]$ConfirmKeyName
    )

    $currentIndex = 0
    $selectedIndexes = [System.Collections.Generic.List[int]]::new()

    while ($true) {
        Clear-Host
        Write-Host "$Title`n" -ForegroundColor Yellow

        for ($i = 0; $i -lt $Items.Count; $i++) {
            $pointer = if ($i -eq $currentIndex) { "> " } else { "  " }
            $checkbox = if ($selectedIndexes.Contains($i)) { "[✓]" } else { "[ ]" }
            
            if ($i -eq $currentIndex) {
                Write-Host "$pointer$checkbox $($Items[$i])" -ForegroundColor Black -BackgroundColor White
            } else {
                Write-Host "$pointer$checkbox $($Items[$i])"
            }
        }
        
        Write-Host ""
        Write-Host ("-"*45)
        Write-Host "  导航:       ↑ / ↓"
        Write-Host "  选择/取消:  空格键 (Spacebar)"
        Write-Host "  全选/反选:  A"
        Write-Host "  确认操作:   $ConfirmKeyName ($($ConfirmKeyChar.ToUpper()))"
        Write-Host "  返回主菜单: Q"
        Write-Host ("-"*45)

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        switch ($key.VirtualKeyCode) {
            38 { $currentIndex = ($currentIndex - 1 + $Items.Count) % $Items.Count } # Up
            40 { $currentIndex = ($currentIndex + 1) % $Items.Count } # Down
            32 { # Spacebar
                if ($selectedIndexes.Contains($currentIndex)) { [void]$selectedIndexes.Remove($currentIndex) }
                else { $selectedIndexes.Add($currentIndex) }
            }
            65 { # 'A' key for All/None
                if ($selectedIndexes.Count -lt $Items.Count) {
                    $selectedIndexes.Clear(); 0..($Items.Count - 1) | ForEach-Object { $selectedIndexes.Add($_) }
                } else {
                    $selectedIndexes.Clear()
                }
            }
            81 { return $null } # 'Q' key for Quit
        }
        
        if ($key.Character -eq $ConfirmKeyChar.ToLower()) {
            return $selectedIndexes | ForEach-Object { $Items[$_] }
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
        Write-Host " > 正在将文件移动到服务器目录..."
        robocopy $pluginPath $ServerRoot /E /MOVE /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
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
            
            # 【BUG 修复】分两步构建目标路径，避免对 Join-Path 传递多个 -ChildPath 参数
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
#region 安装 SourceMod 和 MetaMod
function Install-SourceModAndMetaMod {
    Clear-Host
    Write-Host "==================== 安装 SourceMod & MetaMod ===================="
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
    $availablePlugins = @(Get-ChildItem -Path $PluginSourceDir -Directory | Where-Object { -not (Test-Path (Join-Path $ReceiptsDir "$($_.Name).receipt")) })
    if ($availablePlugins.Count -eq 0) {
        Clear-Host
        Write-Host "没有找到可安装的新插件。"
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

function Install-AllL4D2Plugins {
    Clear-Host
    Write-Host "==================== 安装所有可用插件 ===================="
    $availablePlugins = @(Get-ChildItem -Path $PluginSourceDir -Directory | Where-Object { -not (Test-Path (Join-Path $ReceiptsDir "$($_.Name).receipt")) })
    if ($availablePlugins.Count -eq 0) {
        Write-Host "`n没有找到可安装的新插件。"
        Read-Host "按回车键返回主菜单..."
        return
    }
    $confirmation = Read-Host "`n找到 $($availablePlugins.Count) 个可安装插件。确定要全部安装吗? (Y/N)"
    if ($confirmation.ToLower() -ne 'y') {
        Write-Host "操作已取消。"
        Read-Host "按回车键返回主菜单..."
        return
    }
    foreach ($plugin in $availablePlugins) {
        Invoke-PluginInstallation -PluginObject $plugin
    }
    Write-Host "`n`n所有可用插件均已安装完毕。" -ForegroundColor Cyan
    Read-Host "按回车键返回主菜单..."
}

function Uninstall-AllL4D2Plugins {
    Clear-Host
    Write-Host "==================== 移除所有已安装插件 ===================="
    $installedPlugins = @(Get-ChildItem -Path $ReceiptsDir -Filter "*.receipt")
    if ($installedPlugins.Count -eq 0) {
        Write-Host "`n当前没有任何已安装的插件。"
        Read-Host "按回车键返回主菜单..."
        return
    }
    $confirmation = Read-Host "`n找到 $($installedPlugins.Count) 个已安装插件。确定要全部移除吗? (Y/N)"
    if ($confirmation.ToLower() -ne 'y') {
        Write-Host "操作已取消。"
        Read-Host "按回车键返回主菜单..."
        return
    }
    foreach ($receipt in $installedPlugins) {
        Invoke-PluginUninstallation -ReceiptObject $receipt
    }
    Write-Host "`n`n所有已安装的插件均已移除完毕。" -ForegroundColor Cyan
    Read-Host "按回车键返回主菜单..."
}
#endregion


# --- 主菜单与循环 ---
#region 主菜单
function Show-Menu {
    Clear-Host
    Write-Host "========================================================"
    Write-Host "       L4D2 服务器与插件管理器 $ScriptVersion"
    Write-Host "========================================================"
    Write-Host ""
    Write-Host " 服务器根目录: $ServerRoot`n"
    if ($IsSourceModInstalled) {
        Write-Host " SourceMod 状态: 已安装" -ForegroundColor Green
    } else {
        Write-Host " SourceMod 状态: 未找到!" -ForegroundColor Yellow
    }
    Write-Host "`n 请选择操作:`n"
    Write-Host "   1. 安装 / 更新 SourceMod 和 MetaMod"
    if ($IsSourceModInstalled) {
        Write-Host "   2. 安装插件"
        Write-Host "   3. 移除插件"
        Write-Host "   4. 安装所有可用插件"
        Write-Host "   5. 移除所有已安装插件"
    }
    Write-Host "`n   Q. 退出`n"
    Write-Host "========================================================"
}

# 脚本主循环
while ($true) {
    Show-Menu
    $choice = Read-Host "请输入选项编号并按回车"
    switch ($choice) {
        "1" { Install-SourceModAndMetaMod }
        "2" { if ($IsSourceModInstalled) { Install-L4D2Plugin } }
        "3" { if ($IsSourceModInstalled) { Uninstall-L4D2Plugin } }
        "4" { if ($IsSourceModInstalled) { Install-AllL4D2Plugins } }
        "5" { if ($IsSourceModInstalled) { Uninstall-AllL4D2Plugins } }
        "q" { Write-Host "正在退出..."; exit }
    }
}
#endregion
