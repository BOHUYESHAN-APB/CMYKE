Param(
  [string]$OutDir = "",
  [switch]$SkipFlutterBuild,
  [switch]$SkipBackendBuild,
  [string]$OpenCodePath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
  $here = Split-Path -Parent $PSCommandPath
  return (Resolve-Path (Join-Path $here "..")).Path
}

$repo = Resolve-RepoRoot
Push-Location $repo
try {
  if ($OutDir.Trim() -eq "") {
    $OutDir = Join-Path $repo "dist\\windows\\CMYKE"
  }

  if (-not $SkipBackendBuild) {
    Write-Host "[1/4] Building Rust gateway (release)..."
    cargo build --manifest-path "backend-rust\\Cargo.toml" --release | Out-Host
  } else {
    Write-Host "[1/4] Skipping Rust build."
  }

  if (-not $SkipFlutterBuild) {
    Write-Host "[2/4] Building Flutter Windows (release)..."
    flutter build windows --release | Out-Host
  } else {
    Write-Host "[2/4] Skipping Flutter build."
  }

  $flutterRelease = Join-Path $repo "build\\windows\\x64\\runner\\Release"
  if (-not (Test-Path $flutterRelease)) {
    throw "Flutter release directory not found: $flutterRelease"
  }

  Write-Host "[3/4] Staging package to $OutDir ..."
  if (Test-Path $OutDir) {
    Remove-Item -Recurse -Force $OutDir
  }
  New-Item -ItemType Directory -Force $OutDir | Out-Null
  Copy-Item -Recurse -Force (Join-Path $flutterRelease "*") $OutDir

  $backendExe = Join-Path $repo "backend-rust\\target\\release\\cmyke-backend.exe"
  if (-not (Test-Path $backendExe)) {
    throw "Rust release backend not found: $backendExe"
  }
  Copy-Item -Force $backendExe (Join-Path $OutDir "cmyke-backend.exe")

  $resolvedOpenCode = $OpenCodePath.Trim()
  if ($resolvedOpenCode -eq "") {
    $resolvedOpenCode = ($env:CMYKE_OPENCODE_BIN ?? "").Trim()
  }
  if ($resolvedOpenCode -ne "") {
    if (-not (Test-Path $resolvedOpenCode)) {
      throw "OpenCode binary not found: $resolvedOpenCode"
    }
    Copy-Item -Force $resolvedOpenCode (Join-Path $OutDir "opencode.exe")
  } else {
    Write-Host "[3/4] OpenCode not provided. Set -OpenCodePath or CMYKE_OPENCODE_BIN to bundle it."
  }

  Write-Host "[4/4] Done."
  Write-Host "Package output: $OutDir"
} finally {
  Pop-Location
}

