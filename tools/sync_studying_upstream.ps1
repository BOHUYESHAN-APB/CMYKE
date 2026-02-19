param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$DestRelative = "Studying\\_upstream_latest",
  [switch]$UpdateExisting
)

$ErrorActionPreference = "Stop"

function Test-GitClean([string]$Path) {
  if (-not (Test-Path (Join-Path $Path ".git"))) { return $false }
  $porcelain = git -C $Path status --porcelain
  return [string]::IsNullOrWhiteSpace($porcelain)
}

function Invoke-Clone([string]$Url, [string]$TargetDir, [string]$PreferredBranch = "main") {
  if (Test-Path $TargetDir) {
    throw "Target already exists: $TargetDir"
  }

  $parent = Split-Path -Parent $TargetDir
  if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }

  # Prefer HTTP/1.1 to avoid intermittent schannel/HTTP2 issues on Windows.
  $gitPrefix = @("-c", "http.version=HTTP/1.1")

  $attempts = @(
    # Try main first (explicit), with partial clone to reduce transfer.
    @("clone", "--depth", "1", "--filter=blob:none", "--single-branch", "--no-tags", "--branch", $PreferredBranch, $Url, $TargetDir),
    # Fallback: remote default branch, still partial.
    @("clone", "--depth", "1", "--filter=blob:none", "--single-branch", "--no-tags", $Url, $TargetDir),
    # Last resort: remote default branch, no filter.
    @("clone", "--depth", "1", "--single-branch", "--no-tags", $Url, $TargetDir)
  )

  foreach ($a in $attempts) {
    $out = & git @gitPrefix @a 2>&1
    if ($LASTEXITCODE -eq 0) { return }
    # Clean any partial directory before retrying a different strategy.
    if (Test-Path $TargetDir) { Remove-Item -Recurse -Force $TargetDir }
    $msg = ($out | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($msg)) {
      Write-Host $msg
    }
  }

  throw "git clone failed for $Url"
}

function Invoke-Update([string]$TargetDir) {
  if (-not (Test-Path (Join-Path $TargetDir ".git"))) {
    Write-Host "SKIP (not a git repo): $TargetDir"
    return
  }
  if (-not (Test-GitClean $TargetDir)) {
    Write-Host "SKIP (dirty worktree): $TargetDir"
    return
  }

  git -C $TargetDir fetch --prune --no-tags
  # Prefer main if exists; otherwise stay on current branch.
  $hasMain = (git -C $TargetDir branch -r) -match "origin/main"
  if ($hasMain) {
    git -C $TargetDir checkout main 2>$null
    git -C $TargetDir pull --ff-only origin main
  } else {
    git -C $TargetDir pull --ff-only
  }
}

$dest = Join-Path $RepoRoot $DestRelative
New-Item -ItemType Directory -Path $dest -Force | Out-Null

$repos = @(
  @{ name = "ai_virtual_mate_web"; url = "https://github.com/swordswind/ai_virtual_mate_web.git" },
  @{ name = "airi"; url = "https://github.com/moeru-ai/airi.git" },
  @{ name = "N.E.K.O"; url = "https://github.com/wehos/N.E.K.O.git" }
)

foreach ($r in $repos) {
  $target = Join-Path $dest $r.name
  if (Test-Path $target) {
    if ($UpdateExisting) {
      Write-Host "UPDATE $($r.name) -> $target"
      Invoke-Update $target
    } else {
      Write-Host "SKIP (exists, use -UpdateExisting): $target"
    }
    continue
  }

  Write-Host "CLONE $($r.name) <- $($r.url)"
  $ok = $false
  foreach ($attempt in 1..3) {
    try {
      Invoke-Clone -Url $r.url -TargetDir $target
      $ok = $true
      break
    } catch {
      Write-Host "Attempt $attempt failed: $($_.Exception.Message)"
      if (Test-Path $target) { Remove-Item -Recurse -Force $target }
      Start-Sleep -Seconds (3 * $attempt)
    }
  }
  if (-not $ok) {
    Write-Host "FAILED: $($r.name)"
  }
}

Write-Host "Done. Dest=$dest"
