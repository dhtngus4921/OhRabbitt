[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Message
)

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    throw "This directory is not a Git repository."
}

git add -A
if ($LASTEXITCODE -ne 0) {
    throw "Unable to stage the changes."
}

git diff --cached --quiet
$hasChanges = $LASTEXITCODE -eq 1
if ($LASTEXITCODE -notin 0, 1) {
    throw "Unable to inspect the staged changes."
}

if ($hasChanges) {
    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "Sync work $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    }

    git commit -m $Message
    if ($LASTEXITCODE -ne 0) {
        throw "Git commit failed."
    }
}
else {
    Write-Host "No local changes to commit."
}

git push
if ($LASTEXITCODE -ne 0) {
    throw "Git push failed."
}

Write-Host "Work has been pushed successfully."
