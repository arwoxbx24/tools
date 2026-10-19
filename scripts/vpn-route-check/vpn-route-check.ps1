param([switch]$SelfTest, [int]$PassiveSeconds = 60)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Set-StrictMode -Version 2
$ErrorActionPreference = 'Continue'

# Контрольный список: RU — expected direct, зарубежные — expected vpn
$RuHosts = @('gosuslugi.ru', 'sberbank.ru', 'avito.ru', 'mail.ru', 'yandex.ru', 'vk.com', '2gis.com', 'habr.com',
    'ozon.ru', 'wildberries.ru', 'dzen.ru', 'rutube.ru', 'kinopoisk.ru', 'bitrix24.ru', 'xn--d1abbgf6aiiy.xn--p1ai')
$ForeignHosts = @('github.com', 'google.com', 'youtube.com', 'wikipedia.org', 'cloudflare.com')
$CheckList = @($RuHosts | ForEach-Object { [pscustomobject]@{ host = $_; expected = 'direct' } }) +
    @($ForeignHosts | ForEach-Object { [pscustomobject]@{ host = $_; expected = 'vpn' } })
$ApiCandidates = @('127.0.0.1:9097', '127.0.0.1:9090', '127.0.0.1:16756')
$ProxyCandidates = @(7897, 7890, 12334, 1080, 2080)
$LogFile = Join-Path ([System.IO.Path]::GetTempPath()) 'vpn-route-check-logs.txt'

function Get-ShortError($ex) {
    $m = [string]$ex.Message
    if ($m.Length -gt 80) { $m = $m.Substring(0, 80) }
    return $m
}

function Get-SecretCandidates {
    $list = New-Object System.Collections.Generic.List[string]
    $list.Add('')
    try {
        $dirs = @(Get-ChildItem -Path $env:APPDATA -Directory -Filter '*clash-verge*' -ErrorAction SilentlyContinue)
        foreach ($d in $dirs) {
            $files = @(Get-ChildItem -Path $d.FullName -Recurse -Filter config.yaml -ErrorAction SilentlyContinue)
            foreach ($f in $files) {
                $m = Select-String -Path $f.FullName -Pattern '^\s*secret:\s*(.+)$' | Select-Object -First 1
                if (-not $m) { continue }
                $v = $m.Matches[0].Groups[1].Value.Trim().Trim([char]34, [char]39)
                if ($v -and -not $list.Contains($v)) { $list.Add($v) }
            }
        }
    } catch { }
    try {
        foreach ($root in @($env:APPDATA, $env:LOCALAPPDATA)) {
            $dirs = @(Get-ChildItem -Path $root -Directory -Filter '*hiddify*' -ErrorAction SilentlyContinue)
            foreach ($d in $dirs) {
                $files = @(Get-ChildItem -Path $d.FullName -Recurse -Filter '*.json' -ErrorAction SilentlyContinue)
                foreach ($f in $files) {
                    $hits = @(Select-String -Path $f.FullName -Pattern '"secret"\s*:\s*"([^"]+)"' -ErrorAction SilentlyContinue)
                    foreach ($m in $hits) {
                        $v = $m.Matches[0].Groups[1].Value
                        if ($v -and -not $list.Contains($v)) { $list.Add($v) }
                    }
                }
            }
        }
    } catch { }
    return @($list)
}

function Find-Api {
    $secrets = Get-SecretCandidates
    foreach ($addr in $ApiCandidates) {
        foreach ($s in $secrets) {
            try {
                $req = [System.Net.WebRequest]::Create("http://$addr/version")
                $req.Proxy = $null
                $req.Timeout = 2000
                if ($s) { $req.Headers.Add('Authorization', "Bearer $s") }
                $resp = $req.GetResponse()
                try {
                    if ([int]$resp.StatusCode -eq 200) {
                        $body = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd()
                        return [pscustomobject]@{ base = "http://$addr"; secret = $s; version_body = $body }
                    }
                } finally { $resp.Close() }
            } catch { continue }
        }
    }
    return $null
}

function Find-ProxyPort {
    foreach ($p in $ProxyCandidates) {
        $c = New-Object System.Net.Sockets.TcpClient
        try {
            $t = $c.ConnectAsync('127.0.0.1', $p)
            if ($t.Wait(500) -and $c.Connected) { return $p }
        } catch { } finally { $c.Close() }
    }
    return $null
}

function Start-LogJob($base, $secret, $file) {
    if (Test-Path $file) { Remove-Item $file -Force -ErrorAction SilentlyContinue }
    $job = Start-Job -ArgumentList $base, $secret, $file -ScriptBlock {
        param($b, $s, $f)
        try {
            $req = [System.Net.HttpWebRequest]::Create("$b/logs?level=info")
            $req.Proxy = $null
            if ($s) { $req.Headers.Add('Authorization', "Bearer $s") }
            $sr = New-Object System.IO.StreamReader($req.GetResponse().GetResponseStream())
            while ($true) {
                $line = $sr.ReadLine()
                if ($null -eq $line) { break }
                Add-Content -Path $f -Value $line -Encoding UTF8
            }
        } catch { }
    }
    Start-Sleep -Seconds 1
    return $job
}

function Measure-Proxy($h, $port) {
    $ErrorActionPreference = 'Continue'
    $res = [pscustomobject]@{ ms = $null; err = $null }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        Invoke-WebRequest -Uri "https://$h/" -Method Head -Proxy "http://127.0.0.1:$port" -TimeoutSec 8 -MaximumRedirection 0 -UseBasicParsing -ErrorAction Stop | Out-Null
        $res.ms = [int]$sw.ElapsedMilliseconds
    } catch {
        $resp = $null
        if ($_.Exception.PSObject.Properties['Response']) { $resp = $_.Exception.Response }
        if ($resp) { $res.ms = [int]$sw.ElapsedMilliseconds } else { $res.err = Get-ShortError $_.Exception }
    }
    return $res
}

function Measure-Direct($h) {
    $ErrorActionPreference = 'Continue'
    $res = [pscustomobject]@{ ms = $null; err = $null }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $req = [System.Net.WebRequest]::Create("https://$h/")
        $req.Method = 'HEAD'
        $req.Proxy = $null
        $req.Timeout = 8000
        $req.AllowAutoRedirect = $false
        $resp = $req.GetResponse()
        $resp.Close()
        $res.ms = [int]$sw.ElapsedMilliseconds
    } catch {
        $resp = $null
        if ($_.Exception.PSObject.Properties['Response']) { $resp = $_.Exception.Response }
        if ($resp) { $res.ms = [int]$sw.ElapsedMilliseconds } else { $res.err = Get-ShortError $_.Exception }
    }
    return $res
}

function Get-Payload($line) {
    try {
        $o = $line | ConvertFrom-Json -ErrorAction Stop
        if ($o.PSObject.Properties['payload']) { return [string]$o.payload }
    } catch { }
    if ($line -match '"payload":"(.*)"') { return $Matches[1] }
    return [string]$line
}

function ConvertFrom-LogLine($line) {
    $p = Get-Payload $line
    if ($p -match '-->\s+(?<host>[^:\s]+):\d+\s+match\s+(?<rule>[^\s]+(?:\([^)]*\))?)\s+using\s+(?<chain>.+)$') {
        $g = ($Matches['chain'] -split '\[')[0].Trim()
        return [pscustomobject]@{ host = $Matches['host'].ToLower(); rule = $Matches['rule']; group = $g }
    }
    if ($p -match '-->\s+(?<host>[^:\s]+):\d+\s+(?<rule>No match|DIRECT|error)') {
        $r = $Matches['rule']
        $g = ''
        if ($r -ceq 'DIRECT') { $g = 'DIRECT' }
        return [pscustomobject]@{ host = $Matches['host'].ToLower(); rule = $r; group = $g }
    }
    return $null
}

function Resolve-Routes($lines, $hostList) {
    $found = @{}
    $passive = @{}
    foreach ($line in $lines) {
        $e = ConvertFrom-LogLine $line
        if (-not $e) { continue }
        $key = $e.host
        $target = $passive
        foreach ($h in $hostList) {
            if ($e.host -eq $h.host -or $e.host.EndsWith(".$($h.host)")) { $key = $h.host; $target = $found; break }
        }
        if ($target.ContainsKey($key)) {
            $cur = $target[$key]
            $cur.count = $cur.count + 1
            if ($e.group) { $cur.rule = $e.rule; $cur.group = $e.group }
        } else {
            $target[$key] = [pscustomobject]@{ host = $key; rule = $e.rule; group = $e.group; count = 1 }
        }
    }
    return @{ found = $found; passive = $passive }
}

function Get-Route($group) {
    if (-not $group) { return 'unknown' }
    if ($group -match 'DIRECT|Россия') { return 'direct' }
    if ($group -match 'REJECT') { return 'reject' }
    return 'vpn'
}

function New-HostRows($hostList, $probes, $found) {
    $rows = @()
    foreach ($h in $hostList) {
        $rule = $null; $group = $null
        if ($found.ContainsKey($h.host)) { $rule = $found[$h.host].rule; $group = $found[$h.host].group }
        $route = Get-Route $group
        $ok = $null
        if ($route -ne 'unknown') { $ok = ($route -eq $h.expected) }
        $pr = $probes[$h.host]
        $rows += [pscustomobject]@{
            host = $h.host; expected = $h.expected; route = $route; ok = $ok; rule = $rule; group = $group
            proxy_ms = $pr.proxy_ms; proxy_err = $pr.proxy_err; direct_ms = $pr.direct_ms; direct_err = $pr.direct_err
        }
    }
    return $rows
}

function Send-Report($json, $dir) {
    $cfgPath = Join-Path $dir 'upload.json'
    if (-not (Test-Path $cfgPath)) { Write-Host 'Отправка пропущена: нет upload.json'; return }
    try {
        $cfg = Get-Content -Raw -Encoding UTF8 -Path $cfgPath | ConvertFrom-Json
        $b = [guid]::NewGuid().ToString('N')
        $nl = "`r`n"
        $sb = New-Object System.Text.StringBuilder
        foreach ($p in $cfg.fields.PSObject.Properties) {
            [void]$sb.Append("--$b${nl}Content-Disposition: form-data; name=`"$($p.Name)`"$nl$nl$($p.Value)$nl")
        }
        [void]$sb.Append("--$b${nl}Content-Disposition: form-data; name=`"file`"; filename=`"report.json`"${nl}Content-Type: application/json$nl$nl$json$nl--$b--$nl")
        $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($sb.ToString())
        $r = Invoke-WebRequest -Uri $cfg.url -Method Post -ContentType "multipart/form-data; boundary=$b" -Body $bytes -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        if ([int]$r.StatusCode -ge 200 -and [int]$r.StatusCode -lt 300) { Write-Host 'Отчёт отправлен на сервер' }
        else { Write-Host "Сервер ответил кодом $($r.StatusCode): $(([string]$r.Content).Substring(0, [Math]::Min(300, ([string]$r.Content).Length)))" }
    } catch {
        $code = ''; $text = Get-ShortError $_.Exception
        if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
            try {
                $code = [int]$_.Exception.Response.StatusCode
                $text = (New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd()
                if ($text.Length -gt 300) { $text = $text.Substring(0, 300) }
            } catch { }
        }
        Write-Host "Отправка не удалась. Код: $code. Ответ: $text"
    }
}

function Invoke-SelfTest {
    $samples = @(
        '[TCP] 127.0.0.1:50001 --> habr.com:443 match GeoIP(ru) using DIRECT',
        '[TCP] 127.0.0.1:50002 --> github.com:443 match Match using VPN[VLESS-ws]',
        '[TCP] 127.0.0.1:50003 --> 2gis.com:443 match DomainSuffix(2gis.com) using 🇷🇺 Россия напрямую',
        '[TCP] 127.0.0.1:50004 --> youtube.com:443 match DstPort(443) using REJECT'
    )
    $res = Resolve-Routes $samples $CheckList
    $got = @()
    foreach ($n in @('habr.com', 'github.com', '2gis.com', 'youtube.com')) {
        if ($res.found.ContainsKey($n)) { $got += Get-Route $res.found[$n].group } else { $got += 'unknown' }
    }
    if (($got -join ',') -eq 'direct,vpn,direct,reject') { Write-Host 'SELFTEST OK' }
    else { Write-Host "SELFTEST FAIL: $($got -join ',')"; exit 1 }
}

function Invoke-Main {
    Write-Host 'Проверка маршрутов VPN. Окно не закрывайте, это займёт 1–2 минуты.'
    $api = Find-Api
    if ($api) { Write-Host "API ядра найден: $($api.base)" } else { Write-Host 'API ядра не найден: определим только время ответа.' }
    $proxyPort = Find-ProxyPort
    if ($proxyPort) { Write-Host "Прокси-порт: $proxyPort" } else { Write-Host 'Прокси-порт не найден: замер через прокси пропущен.' }
    $job = $null
    if ($api) { $job = Start-LogJob $api.base $api.secret $LogFile }

    $probes = @{}
    $i = 0
    foreach ($h in $CheckList) {
        $i++
        Write-Host "[$i/$($CheckList.Count)] Проверяю $($h.host)…"
        $pr = [pscustomobject]@{ proxy_ms = $null; proxy_err = $null; direct_ms = $null; direct_err = $null }
        $probes[$h.host] = $pr
        if ($proxyPort) {
            $r = Measure-Proxy $h.host $proxyPort
            $pr.proxy_ms = $r.ms; $pr.proxy_err = $r.err
        }
        $d = Measure-Direct $h.host
        $pr.direct_ms = $d.ms; $pr.direct_err = $d.err
        Start-Sleep -Milliseconds 200
    }

    if ($job) {
        Write-Host "Теперь $PassiveSeconds секунд просто ходите по своим обычным сайтам в браузере…"
        $left = $PassiveSeconds
        while ($left -gt 0) {
            $step = [Math]::Min(10, $left)
            Write-Host "Осталось $left с…"
            Start-Sleep -Seconds $step
            $left -= $step
        }
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host 'Журнал ядра недоступен: пассивная фаза пропущена.'
    }
    $lines = @()
    if (Test-Path $LogFile) { $lines = @(Get-Content -Path $LogFile -Encoding UTF8 -ErrorAction SilentlyContinue) }

    $res = Resolve-Routes $lines $CheckList
    $rows = @(New-HostRows $CheckList $probes $res.found)
    $passiveRows = @($res.passive.Values | Sort-Object count -Descending | ForEach-Object {
        [pscustomobject]@{ host = $_.host; rule = $_.rule; group = $_.group; count = $_.count } })

    $apiInfo = $null
    if ($api) { $apiInfo = [ordered]@{ base = $api.base; version_body = $api.version_body } }
    $report = [ordered]@{
        ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        computer = $env:COMPUTERNAME
        os = [Environment]::OSVersion.VersionString
        api = $apiInfo
        proxy_port = $proxyPort
        hosts = $rows
        passive = $passiveRows
        log_lines = $lines.Count
    }
    $json = $report | ConvertTo-Json -Depth 6
    $name = 'vpn-route-check-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    $path = Join-Path ([Environment]::GetFolderPath('Desktop')) $name
    try {
        [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "Отчёт сохранён: $path"
    } catch { Write-Host "Не удалось сохранить отчёт: $(Get-ShortError $_.Exception)" }

    $rows | Format-Table host, expected, route, ok, group, rule, proxy_ms, direct_ms -AutoSize | Out-Host
    $ru = @($rows | Where-Object { $_.expected -eq 'direct' })
    $fo = @($rows | Where-Object { $_.expected -eq 'vpn' })
    $ruOk = @($ru | Where-Object { $_.ok -eq $true }).Count
    $foOk = @($fo | Where-Object { $_.ok -eq $true }).Count
    foreach ($s in @(@('РФ напрямую', $ruOk, $ru.Count), @('Зарубеж через VPN', $foOk, $fo.Count))) {
        $color = 'Red'
        if ($s[1] -eq $s[2]) { $color = 'Green' }
        Write-Host ("{0}: {1} из {2}" -f $s[0], $s[1], $s[2]) -ForegroundColor $color
    }
    $bad = @($rows | Where-Object { $_.route -eq 'unknown' -or $_.ok -eq $false })
    if ($bad.Count -gt 0) {
        Write-Host 'Требуют внимания:'
        foreach ($b in $bad) { Write-Host "  $($b.host): ожидалось $($b.expected), получено $($b.route)" }
    }
    Send-Report $json $PSScriptRoot
}

if ($SelfTest) { Invoke-SelfTest } else { Invoke-Main }
