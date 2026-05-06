param(
    [int]$Port = 8787,
    [string]$BindHost = "+",
    [string]$Token = "change-me",
    [string]$ChatHotkey = "^%i",
    [string]$ContinueText = "continue",
    [switch]$NoAuth
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms

$signature = @"
using System;
using System.Runtime.InteropServices;

public static class Win32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
"@

Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue | Out-Null

$panelPath = Join-Path $PSScriptRoot "panel.html"
$logPath = Join-Path $PSScriptRoot "bridge-access.log"

function Write-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][int]$StatusCode,
        [Parameter(Mandatory = $true)]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 6
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = "application/json; charset=utf-8"
    $Context.Response.ContentLength64 = $buffer.Length
    $Context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Context.Response.OutputStream.Close()
}

function Write-TextResponse {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][int]$StatusCode,
        [Parameter(Mandatory = $true)][string]$ContentType,
        [Parameter(Mandatory = $true)][string]$Body
    )

    $buffer = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = $ContentType
    $Context.Response.ContentLength64 = $buffer.Length
    $Context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Context.Response.OutputStream.Close()
}

function Append-AccessLog {
        param(
                [Parameter(Mandatory = $true)]$Request,
                [Parameter(Mandatory = $true)][string]$Path,
                [Parameter(Mandatory = $true)][int]$StatusCode,
                [string]$Note = ""
        )

        $ip = "unknown"
        if ($Request.RemoteEndPoint -and $Request.RemoteEndPoint.Address) {
                $ip = $Request.RemoteEndPoint.Address.ToString()
        }

        $safeNote = $Note -replace "[\r\n]+", " "
        $line = "{0} | {1} | {2} | {3} | {4} | {5}" -f (
                (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"),
                $ip,
                $Request.HttpMethod,
                $Path,
                $StatusCode,
                $safeNote
        )

        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Get-AccessLogPageHtml {
        param([int]$Tail = 250)

        $lines = @()
        if (Test-Path -LiteralPath $logPath) {
                $lines = Get-Content -LiteralPath $logPath -Tail $Tail -Encoding UTF8
        }

        if (-not $lines -or $lines.Count -eq 0) {
                $lines = @("No logs yet.")
        }

        $joined = [string]::Join("`r`n", $lines)
        $encoded = [System.Net.WebUtility]::HtmlEncode($joined)

        return @"
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Bridge Access Logs</title>
    <style>
        body {
            margin: 0;
            font-family: "Trebuchet MS", "Lucida Sans Unicode", sans-serif;
            background: linear-gradient(150deg, #071423, #0f3556 45%, #1f5d8a);
            color: #def0ff;
        }
        .wrap {
            width: min(980px, 100% - 24px);
            margin: 20px auto;
            border: 1px solid rgba(168, 208, 255, 0.35);
            border-radius: 14px;
            background: rgba(7, 21, 34, 0.78);
            box-shadow: 0 12px 30px rgba(0, 0, 0, 0.35);
            overflow: hidden;
        }
        .bar {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 10px;
            padding: 12px 14px;
            border-bottom: 1px solid rgba(168, 208, 255, 0.25);
        }
        h1 {
            margin: 0;
            font-size: 1rem;
            letter-spacing: 0.2px;
        }
        a {
            color: #9edbff;
            text-decoration: none;
            font-weight: 600;
        }
        a:hover {
            text-decoration: underline;
        }
        pre {
            margin: 0;
            padding: 12px 14px 16px;
            max-height: calc(100vh - 95px);
            overflow: auto;
            white-space: pre-wrap;
            word-break: break-word;
            line-height: 1.35;
            font-size: 0.86rem;
            color: #cce7ff;
            background: rgba(0, 0, 0, 0.22);
        }
    </style>
</head>
<body>
    <div class="wrap">
        <div class="bar">
            <h1>Bridge Access Logs (latest $Tail lines)</h1>
            <div>
                <a href="/">Back to panel</a>
            </div>
        </div>
        <pre>$encoded</pre>
    </div>
</body>
</html>
"@
}

function Get-RequestBodyText {
    param([Parameter(Mandatory = $true)]$Request)

    if (-not $Request.HasEntityBody) {
        return ""
    }

    # Most mobile clients send JSON in UTF-8 without charset. Default to UTF-8 in that case.
    $encoding = [System.Text.Encoding]::UTF8
    $contentType = [string]$Request.Headers["Content-Type"]
    if (-not [string]::IsNullOrWhiteSpace($contentType)) {
        $parts = $contentType.Split(';')
        foreach ($part in $parts) {
            $segment = $part.Trim()
            if ($segment.StartsWith("charset=", [System.StringComparison]::OrdinalIgnoreCase)) {
                $charset = $segment.Substring(8).Trim().Trim('"').Trim("'")
                if (-not [string]::IsNullOrWhiteSpace($charset)) {
                    try {
                        $encoding = [System.Text.Encoding]::GetEncoding($charset)
                    }
                    catch {
                        $encoding = [System.Text.Encoding]::UTF8
                    }
                }
                break
            }
        }
    }

    $reader = New-Object System.IO.StreamReader($Request.InputStream, $encoding, $true)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Close()
    }
}

function Parse-RequestPayload {
    param([Parameter(Mandatory = $true)]$Request)

    $text = $Request.QueryString["text"]
    if ([string]::IsNullOrWhiteSpace($text) -and ($Request.HttpMethod -eq "POST" -or $Request.HttpMethod -eq "PUT")) {
        $raw = Get-RequestBodyText -Request $Request
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            try {
                $obj = $raw | ConvertFrom-Json -ErrorAction Stop
                if ($obj -and $obj.PSObject.Properties.Name -contains "text") {
                    $text = [string]$obj.text
                }
            }
            catch {
                # If body is not JSON, treat it as plain text.
                $text = $raw
            }
        }
    }

    return $text
}

function Ensure-VSCodeForeground {
    $vscode = Get-Process -Name "Code" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Sort-Object StartTime -Descending |
        Select-Object -First 1

    if (-not $vscode) {
        throw "Interactive VS Code window not found. Keep VS Code open on the desktop session."
    }

    [void][Win32]::ShowWindowAsync($vscode.MainWindowHandle, 9)
    Start-Sleep -Milliseconds 100
    [void][Win32]::SetForegroundWindow($vscode.MainWindowHandle)
    Start-Sleep -Milliseconds 150
}

function Send-TextToCopilotChat {
    param([Parameter(Mandatory = $true)][string]$Text)

    Ensure-VSCodeForeground

    $wshell = New-Object -ComObject WScript.Shell
    # Open Copilot Chat panel.
    $wshell.SendKeys($ChatHotkey)
    Start-Sleep -Milliseconds 250

    [System.Windows.Forms.Clipboard]::SetText($Text)
    Start-Sleep -Milliseconds 60
    $wshell.SendKeys("^v")
    Start-Sleep -Milliseconds 60
    $wshell.SendKeys("{ENTER}")
}

function Check-Auth {
    param([Parameter(Mandatory = $true)]$Request)

    if ($NoAuth) {
        return $true
    }

    $incoming = $Request.QueryString["token"]
    if (-not [string]::IsNullOrEmpty($incoming) -and $incoming -eq $Token) {
        return $true
    }

    $headerToken = $Request.Headers["X-Bridge-Token"]
    if (-not [string]::IsNullOrEmpty($headerToken) -and $headerToken -eq $Token) {
        return $true
    }

    return $false
}

$listener = New-Object System.Net.HttpListener
$prefix = "http://$BindHost`:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
}
catch {
    Write-Error "Failed to start listener: $($_.Exception.Message). For LAN bind, run admin shell or add URL ACL with netsh."
    exit 1
}

Write-Host "Copilot LAN Bridge started at $prefix"
Write-Host "Auth mode: " -NoNewline
if ($NoAuth) {
    Write-Host "none (not recommended)"
}
else {
    Write-Host "token"
}
Write-Host "Routes: GET /, GET /logs, GET/POST /chat, GET/POST /continue, GET /health"
Write-Host "Press Ctrl+C to stop"

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
        $req = $ctx.Request
        $path = $req.Url.AbsolutePath.TrimEnd("/")
        if ([string]::IsNullOrEmpty($path)) {
            $path = "/"
        }

        if ($path -eq "/favicon.ico") {
            $ctx.Response.StatusCode = 204
            $ctx.Response.OutputStream.Close()
            Append-AccessLog -Request $req -Path $path -StatusCode 204 -Note "favicon"
            continue
        }

        if ($path -eq "/") {
            if (-not (Test-Path -LiteralPath $panelPath)) {
                Write-TextResponse -Context $ctx -StatusCode 500 -ContentType "text/plain; charset=utf-8" -Body "panel.html not found"
                Append-AccessLog -Request $req -Path $path -StatusCode 500 -Note "panel missing"
                continue
            }

            $html = Get-Content -LiteralPath $panelPath -Raw -Encoding UTF8
            Write-TextResponse -Context $ctx -StatusCode 200 -ContentType "text/html; charset=utf-8" -Body $html
            Append-AccessLog -Request $req -Path $path -StatusCode 200 -Note "panel"
            continue
        }

        if ($path -eq "/health") {
            Write-JsonResponse -Context $ctx -StatusCode 200 -Body @{
                ok = $true
                time = (Get-Date).ToString("s")
            }
            Append-AccessLog -Request $req -Path $path -StatusCode 200 -Note "health"
            continue
        }

        if (-not (Check-Auth -Request $req)) {
            Write-JsonResponse -Context $ctx -StatusCode 401 -Body @{
                ok = $false
                error = "unauthorized"
                hint = "Pass token in query or X-Bridge-Token header"
            }
            Append-AccessLog -Request $req -Path $path -StatusCode 401 -Note "unauthorized"
            continue
        }

        if ($path -eq "/logs") {
            $logHtml = Get-AccessLogPageHtml -Tail 250
            Write-TextResponse -Context $ctx -StatusCode 200 -ContentType "text/html; charset=utf-8" -Body $logHtml
            Append-AccessLog -Request $req -Path $path -StatusCode 200 -Note "logs page"
            continue
        }

        if ($path -eq "/chat") {
            $text = Parse-RequestPayload -Request $req
            if ([string]::IsNullOrWhiteSpace($text)) {
                Write-JsonResponse -Context $ctx -StatusCode 400 -Body @{
                    ok = $false
                    error = "text is required"
                }
                Append-AccessLog -Request $req -Path $path -StatusCode 400 -Note "chat missing text"
                continue
            }

            Send-TextToCopilotChat -Text $text
            Write-JsonResponse -Context $ctx -StatusCode 200 -Body @{
                ok = $true
                action = "chat"
                text = $text
            }
            Append-AccessLog -Request $req -Path $path -StatusCode 200 -Note "chat sent"
            continue
        }

        if ($path -eq "/continue") {
            if ($req.HttpMethod -ne "POST" -and $req.HttpMethod -ne "GET") {
                Write-JsonResponse -Context $ctx -StatusCode 405 -Body @{
                    ok = $false
                    error = "method not allowed"
                }
                Append-AccessLog -Request $req -Path $path -StatusCode 405 -Note "continue method"
                continue
            }

            Send-TextToCopilotChat -Text $ContinueText
            Write-JsonResponse -Context $ctx -StatusCode 200 -Body @{
                ok = $true
                action = "continue"
                text = $ContinueText
            }
            Append-AccessLog -Request $req -Path $path -StatusCode 200 -Note "continue sent"
            continue
        }

        Write-JsonResponse -Context $ctx -StatusCode 404 -Body @{
            ok = $false
            error = "not found"
        }
        Append-AccessLog -Request $req -Path $path -StatusCode 404 -Note "not found"
    }
    catch {
        Write-JsonResponse -Context $ctx -StatusCode 500 -Body @{
            ok = $false
            error = $_.Exception.Message
        }
        Append-AccessLog -Request $ctx.Request -Path $path -StatusCode 500 -Note $_.Exception.Message
    }
}

$listener.Stop()
$listener.Close()