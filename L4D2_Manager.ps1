# =================================================================
# L4D2 服务器与插件管理器 2000 (PowerShell 重制版)
# 作者: Q1en
# 功能: 安装/更新 SourceMod & MetaMod, 并管理插件。
# =================================================================

# 强制要求 PowerShell 5.1 或更高版本 (为了兼容 Expand-Archive 命令)
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
$ScriptDir = $PSScriptRoot # 获取脚本所在目录
$InstallerDir = Join-Path -Path $ScriptDir -ChildPath "SourceMod_Installers"
$PluginSourceDir = Join-Path -Path $ScriptDir -ChildPath "Available_Plugins"
$ReceiptsDir = Join-Path -Path $ScriptDir -ChildPath "Installed_Receipts"
$ScriptVersion = "2000 (PowerShell 版)"
$IsSourceModInstalled = $false

# --- 初始化检查 ---
# 检查服务器游戏目录是否存在
if (-not (Test-Path -Path $L4d2Dir)) {
    Write-Host ""
    Write-Host " 错误: 找不到求生之路2服务器的游戏目录!" -ForegroundColor Red
    Write-Host " 请编辑此脚本文件, 并正确设置 `$ServerRoot` 的值。"
    Write-Host " 期望的目录: $L4d2Dir"
    Write-Host ""
    Read-Host "按回车键退出..."
    exit
}

# 检查 SourceMod 是否已安装
if (Test-Path -Path (Join-Path -Path $L4d2Dir -ChildPath "addons\sourcemod\bin\sourcemod_mm.dll")) {
    $IsSourceModInstalled = $true
}

# 如果所需的功能目录不存在，则创建它们
@( $InstallerDir, $PluginSourceDir, $ReceiptsDir ) | ForEach-Object {
    if (-not (Test-Path -Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}

# --- 核心功能函数 ---

#region 安装 SourceMod 和 MetaMod
function Install-SourceModAndMetaMod {
    Clear-Host
    Write-Host "==================== 安装 SourceMod & MetaMod ===================="
    Write-Host ""
    Write-Host " 此功能将自动解压并安装最新版的 SourceMod 和 MetaMod。"
    Write-Host " 请确保您已完成以下步骤:"
    Write-Host " 1. 从官网下载了 SourceMod 和 MetaMod:Source 的 Windows 版本。"
    Write-Host "    - MetaMod: https://www.sourcemm.net/downloads.php"
    Write-Host "    - SourceMod: https://www.sourcemod.net/downloads.php"
    Write-Host " 2. 将下载的 .zip 文件放入以下目录:"
    Write-Host "    $InstallerDir"
    Write-Host ""
    Read-Host "准备就绪后，按回车键开始安装..."
    Write-Host ""

    # 安装 MetaMod
    $metamodZip = Get-ChildItem -Path $InstallerDir -Filter "mmsource-*.zip" | Sort-Object Name -Descending | Select-Object -First 1
    if ($metamodZip) {
        Write-Host " 发现 MetaMod 安装包: $($metamodZip.Name)"
        Write-Host " 正在解压到服务器目录..."
        try {
            Expand-Archive -Path $metamodZip.FullName -DestinationPath $L4d2Dir -Force -ErrorAction Stop
            Write-Host " 解压完成。" -ForegroundColor Green
            Write-Host ""

            Write-Host " 正在创建 'metamod.vdf' 以引导服务器加载..."
            $vdfContent = @"
"Plugin"
{
    "file"  "addons/metamod/bin/server"
}
"@
            # VDF 文件需要是 ANSI 编码，而不是 PowerShell 默认的 UTF-8
            [System.IO.File]::WriteAllText((Join-Path -Path $L4d2Dir -ChildPath "metamod.vdf"), $vdfContent, [System.Text.Encoding]::Default)
            Write-Host " 'metamod.vdf' 创建成功!" -ForegroundColor Green
            Write-Host ""
        } catch {
            Write-Host " 解压 MetaMod 时出错: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host " 警告: 在 '$InstallerDir' 中未找到 MetaMod 的 .zip 安装包。" -ForegroundColor Yellow
        Write-Host ""
    }

    # 安装 SourceMod
    $sourcemodZip = Get-ChildItem -Path $InstallerDir -Filter "sourcemod-*.zip" | Sort-Object Name -Descending | Select-Object -First 1
    if ($sourcemodZip) {
        Write-Host " 发现 SourceMod 安装包: $($sourcemodZip.Name)"
        Write-Host " 正在解压到服务器目录..."
        try {
            Expand-Archive -Path $sourcemodZip.FullName -DestinationPath $L4d2Dir -Force -ErrorAction Stop
            Write-Host " 解压完成。" -ForegroundColor Green
            Write-Host ""
        } catch {
            Write-Host " 解压 SourceMod 时出错: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host " 警告: 在 '$InstallerDir' 中未找到 SourceMod 的 .zip 安装包。" -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Host "======================================================="
    Write-Host " 安装流程执行完毕!" -ForegroundColor Cyan
    Write-Host " 请重启您的L4D2服务器以应用所有更改。"
    Write-Host " 重启后, 您可以重新运行此脚本来管理插件。"
    Write-Host "======================================================="
    Write-Host ""
    
    # 在当前会话中更新安装状态，以便菜单立即刷新
    if (Test-Path -Path (Join-Path -Path $L4d2Dir -ChildPath "addons\sourcemod\bin\sourcemod_mm.dll")) {
        $script:IsSourceModInstalled = $true
    }
    Read-Host "按回车键返回主菜单..."
}
#endregion

#region 安装插件
function Install-L4D2Plugin {
    Clear-Host
    Write-Host "==================== 安装插件 ===================="
    Write-Host ""
    Write-Host " 以下是 'Available_Plugins' 目录中找到的【未安装】插件:"
    Write-Host ""

    # 获取所有插件目录，并排除那些已经有安装回执的插件
    $availablePlugins = @(Get-ChildItem -Path $PluginSourceDir -Directory | Where-Object {
        -not (Test-Path -Path (Join-Path -Path $ReceiptsDir -ChildPath "$($_.Name).receipt"))
    })

    if ($availablePlugins.Count -eq 0) {
        Write-Host " 没有找到可安装的新插件。"
        Read-Host "按回车键返回主菜单..."
        return
    }

    # 创建一个映射，将数字选项映射到插件对象
    $pluginMap = @{}
    for ($i = 0; $i -lt $availablePlugins.Count; $i++) {
        $index = $i + 1
        Write-Host "   $index. $($availablePlugins[$i].Name)"
        $pluginMap[$index.ToString()] = $availablePlugins[$i]
    }

    Write-Host ""
    $choice = Read-Host "请输入要安装的插件编号 (输入其它则返回)"

    if (-not $pluginMap.ContainsKey($choice)) {
        return
    }

    $selectedPlugin = $pluginMap[$choice]
    $pluginName = $selectedPlugin.Name
    $pluginPath = $selectedPlugin.FullName
    $receiptPath = Join-Path -Path $ReceiptsDir -ChildPath "$pluginName.receipt"

    Write-Host ""
    Write-Host " 正在为 '$pluginName' 创建文件清单并准备安装..."
    # 递归获取插件目录下的所有文件，并生成相对于插件根目录的路径列表
    Get-ChildItem -Path $pluginPath -Recurse -File | ForEach-Object {
        $_.FullName.Substring($pluginPath.Length + 1)
    } | Out-File -FilePath $receiptPath -Encoding utf8
    
    Write-Host " 清单创建完毕。" -ForegroundColor Green

    Write-Host " 正在将文件移动到服务器目录..."
    # Robocopy 是处理目录树合并移动的最佳工具，功能比 Move-Item 更符合需求
    robocopy $pluginPath $ServerRoot /E /MOVE /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    
    Write-Host ""
    Write-Host " 成功! 插件 '$pluginName' 已被【移动】至服务器目录。" -ForegroundColor Green
    Write-Host ""
    Read-Host "按回车键返回主菜单..."
}
#endregion

#region 移除插件
function Uninstall-L4D2Plugin {
    Clear-Host
    Write-Host "==================== 移除插件 ===================="
    Write-Host ""
    Write-Host " 以下是【已安装】的插件:"
    Write-Host ""

    # 通过查找安装回执来确定已安装的插件
    $installedPlugins = @(Get-ChildItem -Path $ReceiptsDir -Filter "*.receipt")

    if ($installedPlugins.Count -eq 0) {
        Write-Host " 当前没有任何已安装的插件。"
        Read-Host "按回车键返回主菜单..."
        return
    }
    
    $pluginMap = @{}
    for ($i = 0; $i -lt $installedPlugins.Count; $i++) {
        $index = $i + 1
        $pluginName = $installedPlugins[$i].BaseName # BaseName 不包含扩展名
        Write-Host "   $index. $pluginName"
        $pluginMap[$index.ToString()] = $installedPlugins[$i]
    }

    Write-Host ""
    $choice = Read-Host "请输入要移除的插件编号 (输入其它则返回)"

    if (-not $pluginMap.ContainsKey($choice)) {
        return
    }

    $selectedReceipt = $pluginMap[$choice]
    $pluginName = $selectedReceipt.BaseName
    $receiptPath = $selectedReceipt.FullName

    Write-Host ""
    Write-Host " 正在从 '$pluginName' 的安装回执中读取文件列表并准备移除..."
    Write-Host ""

    # 读取回执中的每一个相对路径
    $filesToMove = Get-Content -Path $receiptPath

    foreach ($relativePath in $filesToMove) {
        $serverFile = Join-Path -Path $ServerRoot -ChildPath $relativePath
        $destinationFolder = Join-Path -Path $PluginSourceDir -ChildPath $pluginName
        $destinationFile = Join-Path -Path $destinationFolder -ChildPath $relativePath

        if (Test-Path -Path $serverFile) {
            Write-Host " - 正在移回: $relativePath"
            
            # 确保移回的目标目录存在
            $parentDir = Split-Path -Path $destinationFile -Parent
            if (-not (Test-Path -Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }
            
            Move-Item -Path $serverFile -Destination $destinationFile -Force
        } else {
            Write-Host " - 警告: 在服务器上找不到文件 $relativePath" -ForegroundColor Yellow
        }
    }

    # (可选优化) 尝试清理服务器上可能遗留的空目录
    Get-Content $receiptPath | ForEach-Object { Split-Path -Path $_ -Parent } | Sort-Object -Unique | Sort-Object -Property Length -Descending | ForEach-Object {
        if (-not [string]::IsNullOrEmpty($_)) {
            $dirOnServer = Join-Path -Path $ServerRoot -ChildPath $_
            # 检查目录是否存在且为空
            if ((Test-Path $dirOnServer) -and -not (Get-ChildItem -Path $dirOnServer)) {
                Remove-Item -Path $dirOnServer -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # 删除安装回执
    Remove-Item -Path $receiptPath -Force

    Write-Host ""
    Write-Host " 成功! 插件 '$pluginName' 的所有文件已被【移回】至 'Available_Plugins' 目录。" -ForegroundColor Green
    Write-Host ""
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
    Write-Host " 服务器根目录: $ServerRoot"
    Write-Host ""
    if ($IsSourceModInstalled) {
        Write-Host " SourceMod 状态: 已安装" -ForegroundColor Green
    } else {
        Write-Host " SourceMod 状态: 未找到!" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host " 请选择操作:"
    Write-Host ""
    Write-Host "   1. 安装 / 更新 SourceMod 和 MetaMod"
    if ($IsSourceModInstalled) {
        Write-Host "   2. 安装一个插件"
        Write-Host "   3. 移除一个插件"
    }
    Write-Host ""
    Write-Host "   Q. 退出"
    Write-Host ""
    Write-Host "========================================================"
}

function Handle-InvalidOption {
    Write-Host "`n 无效的选项, 请重新输入。" -ForegroundColor Yellow
    Read-Host "按回车键继续..."
}

# 脚本主循环
while ($true) {
    Show-Menu
    $choice = Read-Host "请输入选项编号并按回车"

    switch ($choice) {
        "1" { Install-SourceModAndMetaMod }
        "2" { if ($IsSourceModInstalled) { Install-L4D2Plugin } else { Handle-InvalidOption } }
        "3" { if ($IsSourceModInstalled) { Uninstall-L4D2Plugin } else { Handle-InvalidOption } }
        "q" { Write-Host "正在退出..."; exit }
        default { Handle-InvalidOption }
    }
}
#endregion