<#
.SYNOPSIS
    Verifies the two REES46 data files and downloads the missing ones from Kaggle.

.DESCRIPTION
    Task E2-02. The raw data is never committed to Git, so this script is how
    anyone (including you, on a new machine) gets exactly the same files.

    For each file the script checks that it exists, that its size in bytes is
    right, and that its SHA-256 hash is right. A file that is missing is
    downloaded with the Kaggle command line tool. A file that exists but is
    wrong is never deleted or overwritten: the script stops and tells you.

    The script is safe to run many times. If everything is already correct,
    it only verifies and exits.

    Credentials are never stored in this script or in the repository. The
    Kaggle tool reads your own API token from your user profile.

.PARAMETER VerifyOnly
    Only check the files. Never download anything.

.PARAMETER SkipHash
    Check existence and size only. Much faster, but a damaged file with the
    right size would not be detected.

.EXAMPLE
    .\scripts\download_data.ps1 -VerifyOnly

.NOTES
    Exit codes: 0 = all files are correct, 1 = a file is wrong or could not be
    verified, 2 = manual action needed (Kaggle tool not installed).
#>
[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [switch]$SkipHash
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
# Settings
# ---------------------------------------------------------------
$repoRoot   = Split-Path -Parent $PSScriptRoot
$dataDir    = Join-Path $repoRoot 'data\raw\rees46'
$dataset    = 'mkechinov/ecommerce-behavior-data-from-multi-category-store'
$datasetUrl = "https://www.kaggle.com/datasets/$dataset"

# Expected values, recorded on 2026-10-29 (see docs/data_sources.md)
$files = @(
    [pscustomobject]@{
        Name   = '2019-Oct.csv'
        Bytes  = [int64]5668612855
        Sha256 = 'FEDD938409B5F836EC89B39C861B13DAD99FC7CD9BEB1FDDD97A2D50488B5B80'
    },
    [pscustomobject]@{
        Name   = '2019-Nov.csv'
        Bytes  = [int64]9006762395
        Sha256 = 'ADDD9A27ED99ABDECE368019EBFBA19568972C7FCBE949DB3484AAB8A3BCFFEC'
    }
)

# ---------------------------------------------------------------
# Checks one file. Returns: ok | missing | wrong size | wrong hash
# The size is checked first because it is instant, and the hash
# (which reads the whole file) only runs if the size is right.
# ---------------------------------------------------------------
function Test-DataFile {
    param([Parameter(Mandatory)] $File)

    $path = Join-Path $dataDir $File.Name
    if (-not (Test-Path -LiteralPath $path)) { return 'missing' }

    $actualBytes = (Get-Item -LiteralPath $path).Length
    if ($actualBytes -ne $File.Bytes) { return 'wrong size' }

    if ($SkipHash) { return 'ok' }

    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actualHash -ne $File.Sha256) { return 'wrong hash' }

    return 'ok'
}

# ---------------------------------------------------------------
# 1. Verify what is already on disk
# ---------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

$status = @{}
foreach ($f in $files) {
    if ($SkipHash) {
        Write-Host "Checking $($f.Name) (size only) ..."
    } else {
        Write-Host "Checking $($f.Name) (size and SHA-256, this can take a few minutes) ..."
    }
    $status[$f.Name] = Test-DataFile -File $f
    Write-Host ("  -> {0}" -f $status[$f.Name])
}

$notOk = @($files | Where-Object { $status[$_.Name] -ne 'ok' })
if ($notOk.Count -eq 0) {
    Write-Host 'All files are present and correct.'
    exit 0
}

# A file that exists but is wrong is never touched automatically.
$wrong = @($notOk | Where-Object { $status[$_.Name] -ne 'missing' })
if ($wrong.Count -gt 0) {
    foreach ($f in $wrong) {
        Write-Warning ("{0} is {1}. Delete it yourself, then run this script again." -f $f.Name, $status[$f.Name])
    }
    exit 1
}

if ($VerifyOnly) {
    Write-Warning 'Some files are missing (VerifyOnly: nothing was downloaded).'
    exit 1
}

# ---------------------------------------------------------------
# 2. Download the missing files
# ---------------------------------------------------------------
$kaggle = Get-Command kaggle -ErrorAction SilentlyContinue
if (-not $kaggle) {
    Write-Host ''
    Write-Host 'The Kaggle command line tool is not installed, so the files cannot be downloaded automatically.'
    Write-Host 'Do one of these:'
    Write-Host "  A) Download the files manually from: $datasetUrl"
    Write-Host "     and put them in: $dataDir"
    Write-Host '  B) Install the tool (pip install kaggle), create an API token in your Kaggle'
    Write-Host '     account settings, and run this script again.'
    Write-Host 'Then run this script with -VerifyOnly to check the files.'
    exit 2
}

foreach ($f in $notOk) {
    Write-Host "Downloading $($f.Name) from Kaggle ..."
    & kaggle datasets download -d $dataset -f $f.Name -p $dataDir --unzip
    if ($LASTEXITCODE -ne 0) {
        throw "The Kaggle download failed for $($f.Name) (exit code $LASTEXITCODE)."
    }

    $result = Test-DataFile -File $f
    if ($result -ne 'ok') {
        throw "$($f.Name) was downloaded but is $result."
    }
    Write-Host "  -> $($f.Name) downloaded and verified."
}

Write-Host 'All files are present and correct.'
exit 0
