[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    throw "This directory is not a Git repository."
}

$changes = git status --porcelain
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read the Git working tree status."
}

if ($changes) {
    throw "Local changes already exist. Commit or stash them before pulling."
}

git pull --ff-only
if ($LASTEXITCODE -ne 0) {
    throw "Git pull failed. Resolve the error before starting work."
}

Write-Host "Repository is up to date. You can start working."
