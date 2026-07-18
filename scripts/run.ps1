# Runs a make target inside the MSYS2 UCRT64 environment from PowerShell.
# Usage:  .\scripts\run.ps1           (builds and runs the sim)
#         .\scripts\run.ps1 waves     (also opens GTKWave)
#         .\scripts\run.ps1 clean
#
# Verilator cannot build in paths that contain spaces. This script maps the
# project folder to R: (no spaces) for the duration of the build.
param(
    [string]$Target = "sim"
)

$projectDir = Split-Path -Parent $PSScriptRoot
$bash = "C:\msys64\usr\bin\bash.exe"

# Map to R: so Verilator/make never see the space in "RISC-V cpu"
if (-not (Test-Path "R:\")) {
    subst R: $projectDir | Out-Null
}

$env:MSYSTEM = "UCRT64"
$env:CHERE_INVOKING = "1"
$env:PATH = "C:\msys64\ucrt64\bin;C:\msys64\usr\bin;" + $env:PATH

& $bash -lc "cd /r && make $Target"
exit $LASTEXITCODE
