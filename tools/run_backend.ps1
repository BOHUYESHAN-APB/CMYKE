Param(
  [string]$Host = "127.0.0.1",
  [int]$Port = 4891
)

$ErrorActionPreference = "Stop"

$env:CMYKE_BACKEND_HOST = $Host
$env:CMYKE_BACKEND_PORT = "$Port"

Write-Host "Starting CMYKE Rust backend on http://$Host`:$Port ..."
Push-Location "$PSScriptRoot\\..\\backend-rust"
try {
  cargo run
} finally {
  Pop-Location
}

