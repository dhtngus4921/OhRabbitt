[CmdletBinding()]
param(
    [string]$HtmlPath = "",
    [string]$DestinationPath = "",
    [int]$Width = 860,
    [int]$CaptureHeight = 20000,
    [int]$WaitMilliseconds = 3500
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($HtmlPath)) {
    $HtmlPath = Join-Path $Root "index.html"
}
$HtmlPath = (Resolve-Path -LiteralPath $HtmlPath).Path
$ProcessorPath = Join-Path $Root "export_detail.py"
$WorkPath = Join-Path $Root "export_work"
$RawPath = Join-Path $WorkPath "full_raw.png"
$ProfilePath = Join-Path $WorkPath ("edge_profile_" + [Guid]::NewGuid().ToString("N"))
$ExportPath = Join-Path $Root "export"

$EdgePath = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$PythonPath = "C:\Users\dhtng\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

if (-not $EdgePath) { throw "Microsoft Edge not found." }
if (-not (Test-Path -LiteralPath $PythonPath)) { throw "Bundled Python not found." }
if (-not (Test-Path -LiteralPath $ProcessorPath)) { throw "Image processor not found: $ProcessorPath" }

New-Item -ItemType Directory -Path $WorkPath -Force | Out-Null
New-Item -ItemType Directory -Path $ProfilePath -Force | Out-Null
New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
if (Test-Path -LiteralPath $RawPath) { Remove-Item -LiteralPath $RawPath -Force }

$HtmlUrl = ([System.Uri]::new($HtmlPath)).AbsoluteUri
$VirtualTimeBudget = [Math]::Max(1000, $WaitMilliseconds)

Write-Host "[1/4] Capturing full page at ${Width}px"
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
if ($Process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $RawPath)) {
    throw "Edge capture failed."
}

Write-Host "[2/4] Creating full PNG and Coupang slices"
& $PythonPath $ProcessorPath
if ($LASTEXITCODE -ne 0) { throw "Image export failed." }

$ManifestPath = Join-Path $ExportPath "export-manifest.json"
if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Export manifest not found." }
$Manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ManifestPath | ConvertFrom-Json
$Slices = @($Manifest.slices)
if ([int]$Manifest.canvas_width -ne $Width) {
    throw "Manifest width $($Manifest.canvas_width) does not match requested width $Width."
}
if ($Slices.Count -eq 0) { throw "No split JPG files were listed in the manifest." }
$SliceHeightTotal = ($Slices | Measure-Object -Property height -Sum).Sum
if ([int64]$SliceHeightTotal -ne [int64]$Manifest.full_height) {
    throw "Slice height total $SliceHeightTotal does not match full height $($Manifest.full_height)."
}
$SliceHashes = @($Slices | ForEach-Object { $_.sha256 })
if (@($SliceHashes | Select-Object -Unique).Count -ne $Slices.Count) {
    throw "Duplicate split-image hashes were detected."
}

$OutputNames = @($Manifest.full_file) + @($Slices | ForEach-Object { $_.file }) + @($Manifest.contact_sheet) + @("export-manifest.json")
$OutputNames = @($OutputNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$OutputFiles = foreach ($Name in $OutputNames) {
    $Path = Join-Path $ExportPath $Name
    if (-not (Test-Path -LiteralPath $Path)) { throw "Expected output not found: $Path" }
    Get-Item -LiteralPath $Path
}

Write-Host "[3/4] Copying verified files"
if (-not [string]::IsNullOrWhiteSpace($DestinationPath)) {
    $DestinationPath = [System.IO.Path]::GetFullPath($DestinationPath)
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    foreach ($File in $OutputFiles) {
        Copy-Item -LiteralPath $File.FullName -Destination (Join-Path $DestinationPath $File.Name) -Force
    }
    $FinalPath = $DestinationPath
} else {
    $FinalPath = $ExportPath
}

Write-Host "[4/4] Complete"
Write-Host "Output: $FinalPath"
Get-ChildItem -LiteralPath $FinalPath -File |
    Where-Object { $_.Name -in $OutputNames } |
    Sort-Object Name |
    Select-Object Name, Length, LastWriteTime |
    Format-Table -AutoSize
