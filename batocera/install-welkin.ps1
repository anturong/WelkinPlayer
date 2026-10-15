<#
.SYNOPSIS
    把 Welkin 修复版 AppImage 一键装到 Batocera（上传 + 安装 + 可选自检）。

.DESCRIPTION
    配合同目录的 install-welkin.sh 使用：本脚本负责 scp 上传与远程调用，
    安装逻辑都在 install-welkin.sh 里（也可以单独拷到 Batocera 上运行）。
    非交互登录使用 OpenSSH for Windows 的 SSH_ASKPASS 机制（临时文件，退出即删）。

.EXAMPLE
    # 最常用：把同目录的 batocera 修复版 AppImage 装上去，自检 + 重启 ES
    powershell -ExecutionPolicy Bypass -File .\install-welkin.ps1 -Verify -Restart

.EXAMPLE
    # 指定 IP / 密码
    powershell -ExecutionPolicy Bypass -File .\install-welkin.ps1 `
        -ComputerName 192.168.17.128 -Password linux -Verify

.EXAMPLE
    # 卸载（连 AppImage 一起删）
    powershell -ExecutionPolicy Bypass -File .\install-welkin.ps1 -Uninstall -Purge -Restart

.EXAMPLE
    # 只测连通
    powershell -ExecutionPolicy Bypass -File .\install-welkin.ps1 -Check

.NOTES
    Batocera 出厂 SSH 账号 root / linux。
    注意：本文件含中文，必须以 UTF-8 with BOM 保存，否则 PowerShell 5.1 会按 GBK 解析而报语法错。
#>
[CmdletBinding()]
param(
    [string]$AppImage,
    [string]$ComputerName = '192.168.17.128',
    [string]$UserName     = 'root',
    [string]$Password     = 'linux',
    [int]   $Port         = 22,
    [switch]$Verify,
    [switch]$Restart,
    [switch]$NoGamelist,
    [switch]$Uninstall,
    [switch]$Purge,
    [switch]$SkipUpload,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

function Say  ($m) { Write-Host $m }
function Ok   ($m) { Write-Host $m -ForegroundColor Green }
function Warn ($m) { Write-Host $m -ForegroundColor Yellow }
function Fail ($m) { Write-Host $m -ForegroundColor Red; exit 1 }

foreach ($exe in 'ssh','scp') {
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
        Fail "找不到 $exe.exe —— 请在 Windows 可选功能里安装 'OpenSSH 客户端'"
    }
}

$installer = Join-Path $PSScriptRoot 'install-welkin.sh'
if (-not (Test-Path -LiteralPath $installer)) { Fail "同目录下缺少 install-welkin.sh" }

if (-not $Uninstall) {
    if (-not $AppImage) {
        $cand = Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'Welkin*.AppImage' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending
        if ($cand.Count -gt 0) {
            $AppImage = ($cand | Where-Object { $_.Name -like '*-batocera*' } | Select-Object -First 1).FullName
            if (-not $AppImage) { $AppImage = ($cand | Where-Object { $_.Name -like '*-fixed*' } | Select-Object -First 1).FullName }
            if (-not $AppImage) { $AppImage = $cand[0].FullName }
            Say "自动选中: $AppImage"
        } else {
            Fail "没找到 Welkin*.AppImage，请用 -AppImage 指定"
        }
    }
    if (-not (Test-Path -LiteralPath $AppImage)) { Fail "找不到 AppImage: $AppImage" }
    $appName = Split-Path -Leaf $AppImage
    Say ("AppImage : {0}" -f $AppImage)
    Say ("           {0:N1} MB  sha256 {1}" -f ((Get-Item -LiteralPath $AppImage).Length / 1MB),
                                               (Get-FileHash -LiteralPath $AppImage -Algorithm SHA256).Hash.Substring(0,16))
    if ($appName -notlike '*-batocera*') {
        Warn "注意：这不是 batocera 修复版。若文件名带 -fixed，则插件已修好但本地音源会命中上游 bug 而没声音；若是原版，一按播放就会让 WebKit 渲染进程崩掉（详见 README）。"
    }
}

# ---------------------------------------------------------------- SSH 环境
$tmpDir  = Join-Path $env:TEMP ("welkin-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$askpass = Join-Path $tmpDir 'askpass.cmd'
$known   = Join-Path $tmpDir 'known_hosts'
Set-Content -LiteralPath $askpass -Value "@echo off`r`necho $Password`r`n" -Encoding Ascii -NoNewline

$env:SSH_ASKPASS         = $askpass
$env:SSH_ASKPASS_REQUIRE = 'force'
$env:DISPLAY             = 'localhost:0'

$sshOpts = @('-o','StrictHostKeyChecking=no','-o',"UserKnownHostsFile=$known",
             '-o','PreferredAuthentications=password','-o','PubkeyAuthentication=no',
             '-o','ConnectTimeout=10','-o','LogLevel=ERROR','-p',"$Port")
$scpOpts = @('-o','StrictHostKeyChecking=no','-o',"UserKnownHostsFile=$known",
             '-o','PreferredAuthentications=password','-o','PubkeyAuthentication=no',
             '-o','ConnectTimeout=10','-o','LogLevel=ERROR','-P',"$Port")
$target = "$UserName@$ComputerName"

try {
    Say ""
    Say "== 连接 $target =="
    $info = & ssh @sshOpts $target 'cat /usr/share/batocera/batocera.version 2>/dev/null; uname -r; id -u'
    if ($LASTEXITCODE -ne 0) { Fail "SSH 登录失败：检查 IP / 密码（Batocera 出厂 root/linux）" }
    $info | ForEach-Object { Say "   $_" }
    if ((@($info)[-1]).ToString().Trim() -ne '0') { Fail "远端不是 root" }
    if ($Check) { Ok "`n连通性正常。"; exit 0 }

    Say ""
    Say "== 上传安装脚本 =="
    & scp @scpOpts $installer "${target}:/tmp/install-welkin.sh" | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "install-welkin.sh 上传失败" }
    & ssh @sshOpts $target 'sed -i "s/\r$//" /tmp/install-welkin.sh; chmod 755 /tmp/install-welkin.sh' | Out-Null
    Ok "   /tmp/install-welkin.sh 就绪"

    if (-not $Uninstall -and -not $SkipUpload) {
        Say ""
        Say "== 上传 AppImage（约 117 MB）=="
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & scp @scpOpts $AppImage "${target}:/userdata/system/" | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "AppImage 上传失败（/userdata 空间不足？）" }
        $sw.Stop()
        Ok ("   完成，用时 {0:N1}s" -f $sw.Elapsed.TotalSeconds)
    }

    $flags = @()
    if ($Verify)     { $flags += '--verify' }
    if ($Restart)    { $flags += '--restart' }
    if ($NoGamelist) { $flags += '--no-gamelist' }
    if ($Uninstall)  { $flags += '--uninstall' }
    if ($Purge)      { $flags += '--purge' }

    $arg = ''
    if (-not $Uninstall -and $appName) { $arg = "'/userdata/system/$appName'" }

    Say ""
    Say "== 远端执行 =="
    & ssh @sshOpts $target "bash /tmp/install-welkin.sh $($flags -join ' ') $arg"
    $code = $LASTEXITCODE
    Say ""
    if ($code -eq 0) { Ok "完成（远端 exit 0）" } else { Warn "远端 exit $code，请看上面的输出" }

    if (-not $Uninstall) {
        Say ""
        Say "提示：ES 里进 Ports 菜单即可看到 Welkin；日志在 /userdata/system/logs/welkin-app.log"
    }
}
finally {
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
