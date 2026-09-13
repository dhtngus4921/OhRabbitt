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
} catch {
    # Encoding setup is cosmetic; export can continue without it.
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($HtmlPath)) {
    $HtmlPath = Join-Path $ScriptRoot "index.html"
}

$HtmlPath = (Resolve-Path -LiteralPath $HtmlPath).Path
$HtmlRoot = Split-Path -Parent $HtmlPath
$ProjectProcessorPath = Join-Path $HtmlRoot "export_detail.py"
if (Test-Path -LiteralPath $ProjectProcessorPath) {
    $RuntimeRoot = $HtmlRoot
    $ProcessorPath = $ProjectProcessorPath
} else {
    $RuntimeRoot = $ScriptRoot
    $ProcessorPath = Join-Path $ScriptRoot "export_detail.py"
}

$WorkPath = Join-Path $RuntimeRoot "export_work"
$RawCapturePath = Join-Path $WorkPath "full_raw.png"
$ProfilePath = Join-Path $WorkPath ("edge_export_profile_" + [Guid]::NewGuid().ToString("N"))
$ExportPath = Join-Path $RuntimeRoot "export"

if (-not (Test-Path -LiteralPath $ProcessorPath)) {
    throw "Image processor not found: $ProcessorPath"
}

$EdgeCandidates = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
)
$EdgePath = $EdgeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $EdgePath) {
    throw "Microsoft Edge not found."
}

$BundledPython = "C:\Users\dhtng\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if (Test-Path -LiteralPath $BundledPython) {
    $PythonPath = $BundledPython
} else {
    $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $PythonCommand) {
        throw "Python with Pillow and NumPy not found."
    }
    $PythonPath = $PythonCommand.Source
}

New-Item -ItemType Directory -Path $WorkPath -Force | Out-Null
New-Item -ItemType Directory -Path $ProfilePath -Force | Out-Null
New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null

if (Test-Path -LiteralPath $RawCapturePath) {
    Remove-Item -LiteralPath $RawCapturePath -Force
}

$HtmlUrl = ([System.Uri]::new($HtmlPath)).AbsoluteUri
$VirtualTimeBudget = [Math]::Max(1000, $WaitMilliseconds)

Write-Host "[1/4] Capturing full page with Edge at ${Width}px"
$EdgeProcess = Start-Process -FilePath $EdgePath -ArgumentList @(
    "--headless=new"
    "--disable-gpu"
    "--hide-scrollbars"
    "--force-device-scale-factor=1"
    "--window-size=$Width,$CaptureHeight"
    "--virtual-time-budget=$VirtualTimeBudget"
    "--user-data-dir=$ProfilePath"
    "--screenshot=$RawCapturePath"
    $HtmlUrl
) -WindowStyle Hidden -Wait -PassThru

if ($EdgeProcess.ExitCode -ne 0) {
    throw "Edge capture failed with exit code: $($EdgeProcess.ExitCode)"
}

if (-not (Test-Path -LiteralPath $RawCapturePath)) {
    throw "Edge screenshot was not created: $RawCapturePath"
}

Write-Host "[2/4] Creating full PNG and split JPG files"
& $PythonPath $ProcessorPath
if ($LASTEXITCODE -ne 0) {
    throw "export_detail.py failed with exit code: $LASTEXITCODE"
}

Write-Host "[3/4] Validating manifest and output files"
$ManifestPath = Join-Path $ExportPath "export-manifest.json"
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    $ManifestPath = Get-ChildItem -LiteralPath $ExportPath -File -Filter "*MANIFEST*.json" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $ManifestPath -or -not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Export manifest was not created."
}

# Windows PowerShell otherwise may decode a UTF-8 JSON manifest with the
# active ANSI code page and corrupt Korean filenames.
$Manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ManifestPath | ConvertFrom-Json
$Slices = @($Manifest.slices)
if ([int]$Manifest.canvas_width -ne $Width) {
    throw "Manifest width $($Manifest.canvas_width) does not match requested width $Width."
}
if ($Slices.Count -eq 0) {
    throw "No split JPG files were listed in the manifest."
}
$SliceHeightTotal = ($Slices | Measure-Object -Property height -Sum).Sum
if ([int64]$SliceHeightTotal -ne [int64]$Manifest.full_height) {
    throw "Slice height total $SliceHeightTotal does not match full height $($Manifest.full_height)."
}

$OutputNames = @($Manifest.full_file)
$OutputNames += @($Slices | ForEach-Object { $_.file })
if (($Manifest.PSObject.Properties.Name -contains "contact_sheet") -and $Manifest.contact_sheet) {
    $OutputNames += @($Manifest.contact_sheet)
}
$OutputNames += @((Split-Path -Leaf $ManifestPath))
$OutputNames = @($OutputNames |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -Unique)

$OutputFiles = foreach ($Name in $OutputNames) {
    $Path = Join-Path $ExportPath $Name
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Expected output not found: $Path"
    }
    Get-Item -LiteralPath $Path
}

$SliceHashes = @($Slices |
    Where-Object { $_.PSObject.Properties.Name -contains "sha256" -and $_.sha256 } |
    ForEach-Object { $_.sha256 })
if ($SliceHashes.Count -eq $Slices.Count) {
    $UniqueHashCount = @($SliceHashes | Select-Object -Unique).Count
    if ($UniqueHashCount -ne $Slices.Count) {
        throw "Duplicate split-image hashes were detected."
    }
}

if (-not [string]::IsNullOrWhiteSpace($DestinationPath)) {
    $DestinationPath = [System.IO.Path]::GetFullPath($DestinationPath)
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    foreach ($File in @($OutputFiles)) {
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
