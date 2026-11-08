# Publish a release to Codeberg (Forgejo / Gitea compatible API).
#
# Usage (from the project root):
#   $env:CODEBERG_TOKEN = "<token with write:repository scope>"
#   powershell -ExecutionPolicy Bypass -File tool\publish_codeberg.ps1
#   powershell -ExecutionPolicy Bypass -File tool\publish_codeberg.ps1 -Version 3.11.0
#
# What it does:
#   1. reads the version from pubspec.yaml (or -Version);
#   2. collects dist\liangciyuan-<version>-* installers;
#   3. writes dist\checksums.txt (sha256sum format);
#   4. creates the release (or reuses the existing tag);
#   5. uploads missing assets, then checksums.txt last;
#   6. verifies the assets that Codeberg reports.
#
# Exit code 0 only when every step succeeded.

[CmdletBinding()]
param(
  [string]$Version,
  [string]$Owner = 'GuLiang',
  [string]$Repo = 'liangciyuan',
  [string]$Token = $env:CODEBERG_TOKEN,
  [string[]]$Assets,
  [switch]$AllowSameSizeOverwrite
)

$ErrorActionPreference = 'Stop'
$InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Fail([string]$Message) {
  Write-Host "ERROR: $Message" -ForegroundColor Red
  exit 1
}

function Curl([string[]]$Arguments) {
  $output = & curl.exe --silent --show-error @Arguments 2>&1
  return $output
}

function Get-HttpStatus([string[]]$Arguments) {
  $code = & curl.exe --silent --output NUL --write-out '%{http_code}' @Arguments
  return [int]$code
}

if (-not $Token) { Fail 'CODEBERG_TOKEN is not set.' }

if (-not $Version) {
  $pubspec = Get-Content 'pubspec.yaml' -Raw
  $match = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
  if (-not $match.Success) { Fail 'Cannot read version from pubspec.yaml.' }
  $Version = $match.Groups[1].Value
}
if ($Version -notmatch '^[0-9]+(\.[0-9]+)+$') {
  Fail "Version must be plain numeric (got '$Version')."
}

$Api = "https://codeberg.org/api/v1/repos/$Owner/$Repo"
$Auth = @('-H', "Authorization: token $Token")

if (-not $Assets) {
  $Assets = @(
    Get-ChildItem -Path 'dist' -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "liangciyuan-$Version-*" } |
      ForEach-Object { $_.FullName }
  )
}
if (-not $Assets -or $Assets.Count -eq 0) {
  Fail "No dist\liangciyuan-$Version-* artifacts found. Build them first."
}

Write-Host "Publishing $Owner/$Repo $Version" -ForegroundColor Cyan
$files = @()
foreach ($path in $Assets) {
  if (-not (Test-Path $path)) { Fail "Missing asset: $path" }
  $item = Get-Item $path
  $hash = (Get-FileHash -Algorithm SHA256 -Path $item.FullName).Hash.ToLowerInvariant()
  $files += [pscustomobject]@{
    Name = $item.Name
    Path = $item.FullName
    Size = $item.Length
    Sha256 = $hash
  }
  Write-Host ("  {0}  {1:N1} MB  {2}" -f $item.Name, ($item.Length / 1MB), $hash.Substring(0, 12))
}

# checksums.txt goes through the same UTF-8 (no BOM) writer as the JSON payload.
$checksumPath = Join-Path $Root 'dist\checksums.txt'
$lines = $files | Sort-Object Name | ForEach-Object { "$($_.Sha256)  $($_.Name)" }
[System.IO.File]::WriteAllText(
  $checksumPath,
  (($lines -join "`n") + "`n"),
  (New-Object System.Text.UTF8Encoding($false))
)
Write-Host "  checksums.txt -> $checksumPath"

$notes = ''
$changelog = Join-Path $Root 'CHANGELOG.md'
if (Test-Path $changelog) {
  $text = Get-Content $changelog -Raw
  $pattern = "(?ms)^##\s+$([regex]::Escape($Version))(?![0-9.]).*?`r?`n(.*?)(?=^##\s|\z)"
  $match = [regex]::Match($text, $pattern)
  if ($match.Success) { $notes = $match.Groups[1].Value.Trim() }
}
if (-not $notes) { $notes = "Release $Version" }

# --- release -------------------------------------------------------------
$release = $null
$tagUrl = "$Api/releases/tags/$Version"
$tagStatus = Get-HttpStatus @($Auth + $tagUrl)
if ($tagStatus -eq 200) {
  $release = (Curl @($Auth + $tagUrl)) | ConvertFrom-Json
  Write-Host "Reusing existing release id=$($release.id)" -ForegroundColor Yellow
} elseif ($tagStatus -eq 404) {
  $payload = [pscustomobject]@{
    tag_name = $Version
    name = "凉次元 $Version"
    body = $notes
    draft = $false
    prerelease = $false
  } | ConvertTo-Json -Depth 5
  $payloadPath = Join-Path $env:TEMP "codeberg-release-$Version.json"
  [System.IO.File]::WriteAllText($payloadPath, $payload, (New-Object System.Text.UTF8Encoding($false)))
  $created = Curl @($Auth + @(
    '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '--data-binary', "@$payloadPath",
    "$Api/releases"
  ))
  try {
    $release = $created | ConvertFrom-Json
  } catch {
    Fail "Create release failed: $created"
  }
  if (-not $release.id) { Fail "Create release failed: $created" }
  Write-Host "Created release id=$($release.id)" -ForegroundColor Green
} else {
  Fail "Cannot query release (HTTP $tagStatus). Check the token and repo path."
}

# --- assets --------------------------------------------------------------
function Upload-Asset([string]$Name, [string]$Path) {
  $status = & curl.exe --silent --output "$env:TEMP\codeberg-upload.log" --write-out '%{http_code}' `
    -H "Authorization: token $Token" `
    -F "attachment=@$Path" `
    "$Api/releases/$($release.id)/assets?name=$Name"
  if ([int]$status -ne 201) {
    $detail = Get-Content "$env:TEMP\codeberg-upload.log" -Raw -ErrorAction SilentlyContinue
    Fail "Upload $Name failed (HTTP $status): $detail"
  }
  Write-Host "  uploaded $Name" -ForegroundColor Green
}

$existing = @{}
$latest = (Curl @($Auth + "$Api/releases/tags/$Version")) | ConvertFrom-Json
foreach ($asset in @($latest.assets)) {
  if ($asset) { $existing["$($asset.name)"] = $asset }
}

foreach ($file in $files) {
  $current = $existing[$file.Name]
  if ($current) {
    if ([int64]$current.size -eq [int64]$file.Size) {
      Write-Host "  skip $($file.Name) (already uploaded, same size)" -ForegroundColor DarkGray
      continue
    }
    if (-not $AllowSameSizeOverwrite) {
      Fail "Asset $($file.Name) exists with a different size. Delete it in the web UI first."
    }
    & curl.exe --silent $Auth -X DELETE "$Api/releases/$($release.id)/assets/$($current.id)" | Out-Null
  }
  Upload-Asset $file.Name $file.Path
}

# checksums.txt must be the last upload so a half-published release is never
# advertised as complete.
$current = $existing['checksums.txt']
if ($current) {
  & curl.exe --silent $Auth -X DELETE "$Api/releases/$($release.id)/assets/$($current.id)" | Out-Null
}
Upload-Asset 'checksums.txt' $checksumPath

# --- verify --------------------------------------------------------------
Write-Host 'Verifying published assets...' -ForegroundColor Cyan
$verified = (Curl @($Auth + "$Api/releases/tags/$Version")) | ConvertFrom-Json
$published = @{}
foreach ($asset in @($verified.assets)) {
  if ($asset) { $published["$($asset.name)"] = [int64]$asset.size }
}
$ok = $true
foreach ($file in $files) {
  $remoteSize = $published[$file.Name]
  if ($null -eq $remoteSize) {
    Write-Host "  MISSING $($file.Name)" -ForegroundColor Red
    $ok = $false
  } elseif ($remoteSize -ne [int64]$file.Size) {
    Write-Host "  SIZE MISMATCH $($file.Name): local $($file.Size), remote $remoteSize" -ForegroundColor Red
    $ok = $false
  } else {
    Write-Host "  ok $($file.Name)" -ForegroundColor Green
  }
}
if (-not $published.ContainsKey('checksums.txt')) {
  Write-Host '  MISSING checksums.txt' -ForegroundColor Red
  $ok = $false
}
if (-not $ok) { Fail 'Verification failed.' }

Write-Host ''
Write-Host "Release page: https://codeberg.org/$Owner/$Repo/releases/tag/$Version" -ForegroundColor Cyan
Write-Host 'Next: dart run tool\verify_update_channel.dart --download' -ForegroundColor Cyan