Param(
  [string]$Host = "127.0.0.1",
  [int]$Port = 4891
)

$ErrorActionPreference = "Stop"

$env:CMYKE_BACKEND_HOST = $Host
$env:CMYKE_BACKEND_PORT = "$Port"

# Keep dev backend workspace consistent with the Flutter app workspace location:
#   Documents/cmyke/workspace/<session_id>/{inputs,outputs,logs}
if (-not $env:CMYKE_WORKSPACE_ROOT -or $env:CMYKE_WORKSPACE_ROOT.Trim() -eq "") {
  try {
    $docs = [Environment]::GetFolderPath("MyDocuments")
    if ($docs -and $docs.Trim() -ne "") {
      $env:CMYKE_WORKSPACE_ROOT = (Join-Path $docs "cmyke\\workspace")
    }
  } catch {
    # Best-effort; backend will fall back to a relative `workspace/` folder.
  }
}

Write-Host "Starting CMYKE Rust backend on http://$Host`:$Port ..."
Push-Location "$PSScriptRoot\\..\\backend-rust"
try {
  cargo run
} finally {
  Pop-Location
}
