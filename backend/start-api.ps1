$ErrorActionPreference = "Continue"
$root = "D:\EODB_HARSAC\mhari-panchayat"
$backend = Join-Path $root "backend"
$php = Join-Path $root "tools\php84\php.exe"
$logDir = Join-Path $backend "storage\logs"
$log = Join-Path $logDir "api-serve.log"
$port = 8083

function Write-Log([string]$msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
  Add-Content -Path $log -Value $line -ErrorAction SilentlyContinue
}

if (-not (Test-Path $php)) { Write-Log "PHP missing: $php"; exit 1 }
if (-not (Test-Path (Join-Path $backend "artisan"))) { Write-Log "artisan missing"; exit 1 }

$existing = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($existing) {
  Write-Log "Already listening on $port (PID $($existing[0].OwningProcess))"
  exit 0
}

Write-Log "Starting Laravel on 127.0.0.1:$port"
$p = Start-Process -FilePath $php -ArgumentList @("artisan","serve","--host=127.0.0.1","--port=$port") -WorkingDirectory $backend -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError (Join-Path $logDir "api-serve-error.log")
Start-Sleep -Seconds 2
$check = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($check) { Write-Log "OK listening PID $($p.Id)" ; exit 0 }
Write-Log "Failed to bind port $port"
exit 1
