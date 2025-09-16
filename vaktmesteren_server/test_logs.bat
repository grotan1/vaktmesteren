@echo off
echo Testing log viewer endpoint...
timeout /t 3 /nobreak > nul
powershell -Command "try { $response = Invoke-WebRequest -Uri 'http://localhost:8082/logs' -UseBasicParsing -TimeoutSec 10; Write-Host 'SUCCESS:' $response.StatusCode '- Page loaded successfully' } catch { Write-Host 'ERROR:' $_.Exception.Message }"
pause