@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Balachou Installer
pushd "%~dp0"
set "_ps1=%TEMP%\Balachou_Install_%RANDOM%%RANDOM%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$src = Get-Content -LiteralPath '%~f0' -Raw -Encoding UTF8; $parts = $src -split '(?m)^# POWERSHELL_PAYLOAD\r?$', 2; if ($parts.Count -lt 2) { exit 1 }; Set-Content -LiteralPath '%_ps1%' -Value $parts[1] -Encoding UTF8"
if errorlevel 1 (
  echo Failed to extract installer payload.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%_ps1%"
set "_code=%ERRORLEVEL%"
del "%_ps1%" >nul 2>nul
popd
exit /b %_code%
# POWERSHELL_PAYLOAD
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8

function Line($message, $color = 'Gray') { Write-Host $message -ForegroundColor $color }
function Ok($message) { Line "  [OK]   $message" Green }
function Warn($message) { Line "  [WARN] $message" Yellow }
function Skip($message) { Line "  [SKIP] $message" DarkYellow }
function Fail($message) { Line "  [FAIL] $message" Red }

function ReadJson($path) {
    try {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function CopyFile($source, $destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function CopyZhTree($sourceLocalization, $targetLocalization) {
    Get-ChildItem -LiteralPath $sourceLocalization -Recurse -File -Filter 'zh_CN.lua' | ForEach-Object {
        $relative = $_.FullName.Substring($sourceLocalization.Length).TrimStart('\')
        CopyFile $_.FullName (Join-Path $targetLocalization $relative)
    }
}

Clear-Host
Line '╔══════════════════════════════════════╗' Cyan
Line '║          Balachou Installer          ║' Cyan
Line '╚══════════════════════════════════════╝' Cyan
Line ''

$root = (Get-Location).Path
$mods = Join-Path $root 'Mods'
if (!(Test-Path -LiteralPath $mods -PathType Container)) {
    Fail 'Mods folder not found. Put this .cmd beside the Mods folder.'
    Read-Host 'Press Enter to exit'
    exit 1
}

$data = Join-Path $root 'Balachou_data'
$zip = Join-Path $data 'main.zip'
$repo = Join-Path $data 'Balachou-main'
if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force }
New-Item -ItemType Directory -Force -Path $data | Out-Null
Ok 'Balachou_data prepared'

$url = 'https://gh-proxy.org/https://github.com/ChromaPIE/Balachou/archive/refs/heads/main.zip'
Line '  [..]   Downloading Balachou main.zip...' DarkCyan
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Ok 'Download complete'

Expand-Archive -LiteralPath $zip -DestinationPath $data -Force
if (!(Test-Path -LiteralPath $repo)) {
    Fail 'Downloaded archive layout is unexpected.'
    Read-Host 'Press Enter to exit'
    exit 1
}
Ok 'Archive extracted'

$vanillaSource = Join-Path $repo 'localization\zh_CN.lua'
$vanillaTarget = Join-Path $root 'localization\zh_CN.lua'
if (Test-Path -LiteralPath $vanillaSource) {
    CopyFile $vanillaSource $vanillaTarget
    Ok 'Vanilla localization installed'
} else {
    Warn 'Vanilla localization not found in archive'
}

$chromicSource = Join-Path $repo 'Mods\ChromicPatch'
$chromicTarget = Join-Path $mods 'ChromicPatch'
if (Test-Path -LiteralPath $chromicSource) {
    if (Test-Path -LiteralPath $chromicTarget) { Remove-Item -LiteralPath $chromicTarget -Recurse -Force }
    Copy-Item -LiteralPath $chromicSource -Destination $chromicTarget -Recurse -Force
    Ok 'ChromicPatch replaced'
} else {
    Warn 'ChromicPatch not found in archive'
}

$installed = 0
$skipped = 0
$failed = 0
$installedNames = @()
$idIndex = @{}
$nameIndex = @{}

Get-ChildItem -LiteralPath $mods -Directory | Where-Object { $_.Name -ne 'ChromicPatch' } | ForEach-Object {
    $folder = $_.FullName
    Get-ChildItem -LiteralPath $folder -File -Filter '*.json' | ForEach-Object {
        $json = ReadJson $_.FullName
        if ($null -eq $json) { return }

        if ($json.PSObject.Properties.Name -contains 'id' -and $json.id) {
            $key = [string]$json.id
            if (!$idIndex.ContainsKey($key.ToLowerInvariant())) { $idIndex[$key.ToLowerInvariant()] = $folder }
        }
        if ($json.PSObject.Properties.Name -contains 'name' -and $json.name) {
            $key = [string]$json.name
            if (!$nameIndex.ContainsKey($key.ToLowerInvariant())) { $nameIndex[$key.ToLowerInvariant()] = $folder }
        }
    }
}

$metadataFiles = Get-ChildItem -LiteralPath (Join-Path $repo 'Mods') -Recurse -File -Filter 'lang.cmeta'
foreach ($metadataFile in $metadataFiles) {
    $metadata = ReadJson $metadataFile.FullName
    if ($null -eq $metadata -or -not $metadata.modid) {
        $skipped++
        Skip ('Invalid metadata: ' + $metadataFile.FullName)
        continue
    }

    $sourceLocalization = Split-Path -Parent $metadataFile.FullName
    $repoMod = Split-Path -Leaf (Split-Path -Parent $sourceLocalization)
    if ($repoMod -eq 'ChromicPatch') { continue }

    $lookup = [string]$metadata.modid
    if ($repoMod -ieq 'smods') {
        $target = $nameIndex[$lookup.ToLowerInvariant()]
    } else {
        $target = $idIndex[$lookup.ToLowerInvariant()]
    }
    if (!$target) {
        $skipped++
        Skip ($repoMod + ': target mod not found for modid ' + $lookup)
        continue
    }

    try {
        $targetLocalization = Join-Path $target 'localization'
        if ($repoMod -ieq 'Wormhole') {
            CopyZhTree $sourceLocalization $targetLocalization
        } else {
            $sourceFile = Join-Path $sourceLocalization 'zh_CN.lua'
            if (Test-Path -LiteralPath $sourceFile) {
                CopyFile $sourceFile (Join-Path $targetLocalization 'zh_CN.lua')
            } else {
                CopyZhTree $sourceLocalization $targetLocalization
            }
        }
        $installed++
        $installedNames += (Split-Path -Leaf $target)
        Ok ($repoMod + ' -> ' + (Split-Path -Leaf $target))
    } catch {
        $failed++
        Fail ($repoMod + ': ' + $_.Exception.Message)
    }
}

Line ''
Line 'Summary' Cyan
Line ('  Installed: ' + $installed) Green
Line ('  Skipped:   ' + $skipped) Yellow
Line ('  Failed:    ' + $failed) Red
if ($installedNames.Count -gt 0) { Line ('  Mods: ' + (($installedNames | Sort-Object -Unique) -join ', ')) Gray }
Line ''
Read-Host 'Press Enter to exit'
