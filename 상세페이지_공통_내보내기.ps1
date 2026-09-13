[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ProjectPath = "",

    [string]$HtmlPath = "",
    [string]$DestinationPath = "",
    [string]$SearchRoot = "",
    [switch]$All,
    [switch]$List,
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
if ([string]::IsNullOrWhiteSpace($SearchRoot)) {
    $SearchRoot = $ScriptRoot
}
$SearchRoot = (Resolve-Path -LiteralPath $SearchRoot).Path

function Resolve-ExportProject {
    param(
        [string]$RequestedProjectPath,
        [string]$RequestedHtmlPath
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedHtmlPath)) {
        $ResolvedHtmlPath = (Resolve-Path -LiteralPath $RequestedHtmlPath).Path
        $ResolvedProjectPath = Split-Path -Parent $ResolvedHtmlPath
    } else {
        if ([string]::IsNullOrWhiteSpace($RequestedProjectPath)) {
            $RequestedProjectPath = (Get-Location).Path
        }
        $ResolvedProjectPath = (Resolve-Path -LiteralPath $RequestedProjectPath).Path
        $ResolvedHtmlPath = Join-Path $ResolvedProjectPath "index.html"
    }

    $ProcessorPath = Join-Path $ResolvedProjectPath "export_detail.py"
    if (-not (Test-Path -LiteralPath $ResolvedHtmlPath -PathType Leaf)) {
        throw "index.html not found: $ResolvedHtmlPath"
    }
    if (-not (Test-Path -LiteralPath $ProcessorPath -PathType Leaf)) {
        throw "export_detail.py not found: $ProcessorPath"
    }

    [pscustomobject]@{
        Name = Split-Path -Leaf $ResolvedProjectPath
        ProjectPath = $ResolvedProjectPath
        HtmlPath = $ResolvedHtmlPath
        ProcessorPath = $ProcessorPath
    }
}

function Find-ExportProjects {
    param([string]$RootPath)

    $Candidates = @($RootPath)
    $Candidates += @(Get-ChildItem -LiteralPath $RootPath -Directory -Force -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName)

    foreach ($Candidate in $Candidates) {
        $IndexPath = Join-Path $Candidate "index.html"
        $ProcessorPath = Join-Path $Candidate "export_detail.py"
        if ((Test-Path -LiteralPath $IndexPath -PathType Leaf) -and
            (Test-Path -LiteralPath $ProcessorPath -PathType Leaf)) {
            Resolve-ExportProject -RequestedProjectPath $Candidate -RequestedHtmlPath ""
        }
    }
}

function Find-Edge {
    $Candidates = @(
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
    )
    $Found = $Candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($Found) { return $Found }

    $Command = Get-Command msedge -ErrorAction SilentlyContinue
    if ($Command) { return $Command.Source }
    throw "Microsoft Edge not found."
}

function Find-Python {
    param([string]$ForProjectPath)

    $Candidates = @(
        "C:\Users\dhtng\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe",
        (Join-Path $ForProjectPath ".venv\Scripts\python.exe"),
        (Join-Path $SearchRoot ".venv\Scripts\python.exe")
    )

    $Command = Get-Command python -ErrorAction SilentlyContinue
    if ($Command) { $Candidates += $Command.Source }

    foreach ($Candidate in @($Candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { continue }
        & $Candidate -c "import PIL, numpy" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $Candidate }
    }
    throw "Python with Pillow and NumPy not found."
}

function Invoke-DetailExport {
    param(
        [pscustomobject]$Project,
        [string]$CopyDestination
    )

    $RuntimeRoot = $Project.ProjectPath
    $WorkPath = Join-Path $RuntimeRoot "export_work"
    $RawCapturePath = Join-Path $WorkPath "full_raw.png"
    $ProfilePath = Join-Path $WorkPath ("edge_export_profile_" + [Guid]::NewGuid().ToString("N"))
    $ExportPath = Join-Path $RuntimeRoot "export"
    $EdgePath = Find-Edge
    $PythonPath = Find-Python -ForProjectPath $RuntimeRoot

    New-Item -ItemType Directory -Path $WorkPath -Force | Out-Null
    New-Item -ItemType Directory -Path $ProfilePath -Force | Out-Null
    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    if (Test-Path -LiteralPath $RawCapturePath) {
        Remove-Item -LiteralPath $RawCapturePath -Force
    }

    $HtmlUrl = ([System.Uri]::new($Project.HtmlPath)).AbsoluteUri
    $VirtualTimeBudget = [Math]::Max(1000, $WaitMilliseconds)

    Write-Host ""
    Write-Host "=== $($Project.Name) ==="
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
    if (-not (Test-Path -LiteralPath $RawCapturePath -PathType Leaf)) {
        throw "Edge screenshot was not created: $RawCapturePath"
    }

    Write-Host "[2/4] Creating full PNG and split JPG files"
    & $PythonPath $Project.ProcessorPath
    if ($LASTEXITCODE -ne 0) {
        throw "export_detail.py failed with exit code: $LASTEXITCODE"
    }

    Write-Host "[3/4] Validating manifest and output files"
    $ManifestPath = Join-Path $ExportPath "export-manifest.json"
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        $ManifestPath = Get-ChildItem -LiteralPath $ExportPath -File -Filter "*MANIFEST*.json" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $ManifestPath -or -not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Export manifest was not created."
    }

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
        $OutputFilePath = Join-Path $ExportPath $Name
        if (-not (Test-Path -LiteralPath $OutputFilePath -PathType Leaf)) {
            throw "Expected output not found: $OutputFilePath"
        }
        Get-Item -LiteralPath $OutputFilePath
    }

    $SliceHashes = @($Slices |
        Where-Object { $_.PSObject.Properties.Name -contains "sha256" -and $_.sha256 } |
        ForEach-Object { $_.sha256 })
    if ($SliceHashes.Count -eq $Slices.Count) {
        if (@($SliceHashes | Select-Object -Unique).Count -ne $Slices.Count) {
            throw "Duplicate split-image hashes were detected."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($CopyDestination)) {
        $FinalPath = [System.IO.Path]::GetFullPath($CopyDestination)
        New-Item -ItemType Directory -Path $FinalPath -Force | Out-Null
        foreach ($File in @($OutputFiles)) {
            Copy-Item -LiteralPath $File.FullName -Destination (Join-Path $FinalPath $File.Name) -Force
        }
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

    [pscustomobject]@{
        Project = $Project.Name
        Output = $FinalPath
        Files = $OutputFiles.Count
        Status = "Complete"
    }
}

if ($All -or $List) {
    $Projects = @(Find-ExportProjects -RootPath $SearchRoot)
} else {
    $Projects = @(Resolve-ExportProject -RequestedProjectPath $ProjectPath -RequestedHtmlPath $HtmlPath)
}

if ($Projects.Count -eq 0) {
    throw "No exportable projects found under: $SearchRoot"
}

if ($List) {
    $Projects | Select-Object Name, ProjectPath, HtmlPath | Format-Table -AutoSize
    exit 0
}

$Results = @()
$Failures = @()
foreach ($Project in $Projects) {
    try {
        $ProjectDestination = $DestinationPath
        if ($All -and -not [string]::IsNullOrWhiteSpace($DestinationPath)) {
            $ProjectDestination = Join-Path $DestinationPath $Project.Name
        }
        $Results += Invoke-DetailExport -Project $Project -CopyDestination $ProjectDestination
    } catch {
        $Failures += [pscustomobject]@{
            Project = $Project.Name
            Error = $_.Exception.Message
        }
        Write-Error -ErrorAction Continue "[$($Project.Name)] $($_.Exception.Message)"
        if (-not $All) { throw }
    }
}

Write-Host ""
Write-Host "=== Export summary ==="
if ($Results.Count -gt 0) {
    $Results | Format-Table Project, Status, Files, Output -AutoSize
}
if ($Failures.Count -gt 0) {
    $Failures | Format-Table Project, Error -AutoSize
    throw "$($Failures.Count) project export(s) failed."
}

<#
.SYNOPSIS
Exports one or all detail-page projects under C:\Codex.

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Codex\상세페이지_공통_내보내기.ps1" "C:\Codex\화병_상세페이지"

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Codex\상세페이지_공통_내보내기.ps1" -All

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Codex\상세페이지_공통_내보내기.ps1" -List
#>
