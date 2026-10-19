# TZ dcfg-yb2ys fix1 — vpn-route-check.ps1: совместимость с Windows PowerShell 5.1

FILE: scripts/vpn-route-check/vpn-route-check.ps1

Executor: sdk-agent code. Ровно три правки, ничего больше.

1. В функции `Measure-Proxy` строка
```
        Invoke-WebRequest -Uri "https://$h/" -Method Head -Proxy "http://127.0.0.1:$port" -TimeoutSec 8 -MaximumRedirection 0 -UseBasicParsing | Out-Null
```
   → добавить `-ErrorAction Stop` перед `| Out-Null` (в 5.1 ошибки Invoke-WebRequest не терминирующие и без этого не попадают в catch).

2. В функции `Send-Report` строка
```
        $r = Invoke-WebRequest -Uri $cfg.url -Method Post -ContentType "multipart/form-data; boundary=$b" -Body $bytes -Proxy $null -UseBasicParsing -TimeoutSec 60
```
   → убрать `-Proxy $null` и добавить `-ErrorAction Stop` (итог: `... -Body $bytes -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop`).

3. Строка
```
$LogFile = Join-Path $env:TEMP 'vpn-route-check-logs.txt'
```
   → `$LogFile = Join-Path ([System.IO.Path]::GetTempPath()) 'vpn-route-check-logs.txt'` (на Linux `$env:TEMP` пуст — самопроверка печатает ошибку).
