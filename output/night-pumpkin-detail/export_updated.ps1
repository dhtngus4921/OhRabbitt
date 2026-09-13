[CmdletBinding()]
param([int]$Width = 860, [int]$CaptureHeight = 20000, [int]$WaitMilliseconds = 3000)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$HtmlPath = Join-Path $Root "index.html"
$WorkPath = Join-Path $Root "export_work"
$RawPath = Join-Path $WorkPath "full_raw.png"
$ProfilePath = Join-Path $WorkPath ("edge_profile_" + [Guid]::NewGuid().ToString("N"))
$EdgePath = @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe", "C:\Program Files\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$PythonPath = "C:\Users\dhtng\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

if (-not $EdgePath) { throw "Microsoft Edge not found." }
if (-not (Test-Path -LiteralPath $PythonPath)) { throw "Bundled Python not found." }
New-Item -ItemType Directory -Path $WorkPath -Force | Out-Null
New-Item -ItemType Directory -Path $ProfilePath -Force | Out-Null
if (Test-Path -LiteralPath $RawPath) { Remove-Item -LiteralPath $RawPath -Force }

$HtmlUrl = ([System.Uri]::new((Resolve-Path -LiteralPath $HtmlPath).Path)).AbsoluteUri
$VirtualTimeBudget = [Math]::Max(1000, $WaitMilliseconds)
$Process = Start-Process -FilePath $EdgePath -ArgumentList @(
    "--headless=new",
    "--disable-gpu",
    "--hide-scrollbars",
    "--force-device-scale-factor=1",
    "--window-size=$Width,$CaptureHeight",
    "--virtual-time-budget=$VirtualTimeBudget",
    "--user-data-dir=$ProfilePath",
    "--screenshot=$RawPath",
    $HtmlUrl
) -WindowStyle Hidden -Wait -PassThru
if ($Process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $RawPath)) { throw "Edge capture failed." }

& $PythonPath (Join-Path $Root "export_updated.py")
if ($LASTEXITCODE -ne 0) { throw "Image export failed." }
