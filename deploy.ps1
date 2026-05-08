$ErrorActionPreference = "Stop"

Write-Host "[deploy] Iniciando deploy via JAR + AWS CLI..." -ForegroundColor Cyan
& "$PSScriptRoot\infra\deploy-jar.ps1"
Write-Host "[deploy] Concluido." -ForegroundColor Cyan
