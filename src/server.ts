import { IncomingMessage, ServerResponse, createServer } from "node:http";
import { appendFileSync, existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

interface BridgeConfig {
  port: number;
  bindHost: string;
  token: string;
  chatHotkey: string;
  continueText: string;
  noAuth: boolean;
}

const rootDir = process.cwd();
const panelPath = join(rootDir, "panel.html");
const logPath = join(rootDir, "bridge-access.log");

const config = parseArgs(process.argv.slice(2));
const listenHost = normalizeListenHost(config.bindHost);

function parseArgs(args: string[]): BridgeConfig {
  const defaults: BridgeConfig = {
    port: 8787,
    bindHost: "+",
    token: "change-me",
    chatHotkey: "^%i",
    continueText: "continue",
    noAuth: false
  };

  const out: BridgeConfig = { ...defaults };

  for (let i = 0; i < args.length; i += 1) {
    const key = args[i];
    const next = args[i + 1];

    if (!key) {
      continue;
    }

    switch (key.toLowerCase()) {
      case "--port":
      case "-port": {
        const parsed = Number.parseInt(next ?? "", 10);
        if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 65535) {
          throw new Error("Invalid port value.");
        }
        out.port = parsed;
        i += 1;
        break;
      }
      case "--bindhost":
      case "-bindhost": {
        if (!next) {
          throw new Error("Missing value for bindHost.");
        }
        out.bindHost = next;
        i += 1;
        break;
      }
      case "--token":
      case "-token": {
        if (!next) {
          throw new Error("Missing value for token.");
        }
        out.token = next;
        i += 1;
        break;
      }
      case "--chathotkey":
      case "-chathotkey": {
        if (!next) {
          throw new Error("Missing value for chatHotkey.");
        }
        out.chatHotkey = next;
        i += 1;
        break;
      }
      case "--continuetext":
      case "-continuetext": {
        if (!next) {
          throw new Error("Missing value for continueText.");
        }
        out.continueText = next;
        i += 1;
        break;
      }
      case "--noauth":
      case "-noauth": {
        out.noAuth = true;
        break;
      }
      default: {
        throw new Error(`Unknown argument: ${key}`);
      }
    }
  }

  return out;
}

function normalizeListenHost(rawHost: string): string {
  if (rawHost === "+" || rawHost === "*" || rawHost === "0.0.0.0") {
    return "0.0.0.0";
  }

  if (!rawHost || rawHost.trim() === "") {
    return "0.0.0.0";
  }

  return rawHost;
}

function writeJson(res: ServerResponse, statusCode: number, body: unknown): void {
  const payload = JSON.stringify(body);
  const buffer = Buffer.from(payload, "utf8");
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Content-Length", String(buffer.length));
  res.end(buffer);
}

function writeText(res: ServerResponse, statusCode: number, contentType: string, body: string): void {
  const buffer = Buffer.from(body, "utf8");
  res.statusCode = statusCode;
  res.setHeader("Content-Type", contentType);
  res.setHeader("Content-Length", String(buffer.length));
  res.end(buffer);
}

function htmlEncode(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function appendAccessLog(req: IncomingMessage, pathName: string, statusCode: number, note = ""): void {
  const ip = req.socket.remoteAddress ?? "unknown";
  const safeNote = note.replace(/[\r\n]+/g, " ");
  const time = new Date().toISOString().replace("T", " ").slice(0, 19);
  const line = `${time} | ${ip} | ${req.method ?? "UNKNOWN"} | ${pathName} | ${statusCode} | ${safeNote}`;
  appendFileSync(logPath, `${line}\n`, { encoding: "utf8" });
}

function getAccessLogPageHtml(tail = 250): string {
  let lines: string[] = [];
  if (existsSync(logPath)) {
    const all = readFileSync(logPath, "utf8").split(/\r?\n/).filter((line) => line.length > 0);
    lines = all.slice(Math.max(0, all.length - tail));
  }

  if (lines.length === 0) {
    lines = ["No logs yet."];
  }

  const encoded = htmlEncode(lines.join("\r\n"));

  return `<!doctype html>
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
            <h1>Bridge Access Logs (latest ${tail} lines)</h1>
            <div>
                <a href="/">Back to panel</a>
            </div>
        </div>
        <pre>${encoded}</pre>
    </div>
</body>
</html>`;
}

async function readBody(req: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }

  if (chunks.length === 0) {
    return "";
  }

  const contentType = String(req.headers["content-type"] ?? "");
  const charsetMatch = contentType.match(/charset\s*=\s*([^;\s]+)/i);
  const charset = (charsetMatch?.[1] ?? "utf-8").toLowerCase();

  try {
    if (charset === "utf-8" || charset === "utf8") {
      return Buffer.concat(chunks).toString("utf8");
    }

    return Buffer.concat(chunks).toString("utf8");
  } catch {
    return Buffer.concat(chunks).toString("utf8");
  }
}

async function parsePayloadText(req: IncomingMessage, url: URL): Promise<string> {
  const queryText = url.searchParams.get("text");
  if (queryText && queryText.trim() !== "") {
    return queryText;
  }

  if (req.method !== "POST" && req.method !== "PUT") {
    return "";
  }

  const raw = await readBody(req);
  if (!raw || raw.trim() === "") {
    return "";
  }

  try {
    const data = JSON.parse(raw) as { text?: unknown };
    if (typeof data.text === "string") {
      return data.text;
    }
  } catch {
    return raw;
  }

  return "";
}

function checkAuth(req: IncomingMessage, url: URL): boolean {
  if (config.noAuth) {
    return true;
  }

  const queryToken = url.searchParams.get("token");
  if (queryToken && queryToken === config.token) {
    return true;
  }

  const headerToken = req.headers["x-bridge-token"];
  const firstHeader = Array.isArray(headerToken) ? headerToken[0] : headerToken;
  if (firstHeader && firstHeader === config.token) {
    return true;
  }

  return false;
}

function runDesktopAutomation(chatHotkey: string, text: string): void {
  const hotkeyB64 = Buffer.from(chatHotkey, "utf8").toString("base64");
  const textB64 = Buffer.from(text, "utf8").toString("base64");

  const psScript = [
    "$ErrorActionPreference = 'Stop'",
    "Add-Type -AssemblyName System.Windows.Forms",
    "$signature = @\"",
    "using System;",
    "using System.Runtime.InteropServices;",
    "public static class Win32 {",
    "  [DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr hWnd);",
    "  [DllImport(\"user32.dll\")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);",
    "}",
    "\"@",
    "Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue | Out-Null",
    `$chatHotkey = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${hotkeyB64}'))`,
    `$text = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${textB64}'))`,
    "$vscode = Get-Process -Name 'Code' -ErrorAction SilentlyContinue |",
    "  Where-Object { $_.MainWindowHandle -ne 0 } |",
    "  Sort-Object StartTime -Descending |",
    "  Select-Object -First 1",
    "if (-not $vscode) { throw 'Interactive VS Code window not found. Keep VS Code open on the desktop session.' }",
    "[void][Win32]::ShowWindowAsync($vscode.MainWindowHandle, 9)",
    "Start-Sleep -Milliseconds 100",
    "[void][Win32]::SetForegroundWindow($vscode.MainWindowHandle)",
    "Start-Sleep -Milliseconds 150",
    "$wshell = New-Object -ComObject WScript.Shell",
    "$wshell.SendKeys($chatHotkey)",
    "Start-Sleep -Milliseconds 250",
    "[System.Windows.Forms.Clipboard]::SetText($text)",
    "Start-Sleep -Milliseconds 60",
    "$wshell.SendKeys('^v')",
    "Start-Sleep -Milliseconds 60",
    "$wshell.SendKeys('{ENTER}')"
  ].join("\n");

  const result = spawnSync(
    "powershell",
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", psScript],
    { encoding: "utf8" }
  );

  if (result.status !== 0) {
    const stderr = (result.stderr ?? "").trim();
    const stdout = (result.stdout ?? "").trim();
    throw new Error(stderr || stdout || "Desktop automation failed.");
  }
}

function sendTextToCopilotChat(text: string): void {
  runDesktopAutomation(config.chatHotkey, text);
}

const server = createServer(async (req, res) => {
  const method = req.method ?? "GET";
  const url = new URL(req.url ?? "/", `http://${req.headers.host ?? `localhost:${config.port}`}`);
  const pathName = url.pathname.replace(/\/+$/, "") || "/";

  try {
    if (pathName === "/favicon.ico") {
      res.statusCode = 204;
      res.end();
      appendAccessLog(req, pathName, 204, "favicon");
      return;
    }

    if (pathName === "/") {
      if (!existsSync(panelPath)) {
        writeText(res, 500, "text/plain; charset=utf-8", "panel.html not found");
        appendAccessLog(req, pathName, 500, "panel missing");
        return;
      }

      const html = readFileSync(panelPath, "utf8");
      writeText(res, 200, "text/html; charset=utf-8", html);
      appendAccessLog(req, pathName, 200, "panel");
      return;
    }

    if (pathName === "/health") {
      writeJson(res, 200, {
        ok: true,
        time: new Date().toISOString().slice(0, 19)
      });
      appendAccessLog(req, pathName, 200, "health");
      return;
    }

    if (!checkAuth(req, url)) {
      writeJson(res, 401, {
        ok: false,
        error: "unauthorized",
        hint: "Pass token in query or X-Bridge-Token header"
      });
      appendAccessLog(req, pathName, 401, "unauthorized");
      return;
    }

    if (pathName === "/logs") {
      const html = getAccessLogPageHtml(250);
      writeText(res, 200, "text/html; charset=utf-8", html);
      appendAccessLog(req, pathName, 200, "logs page");
      return;
    }

    if (pathName === "/chat") {
      const text = await parsePayloadText(req, url);
      if (!text || text.trim() === "") {
        writeJson(res, 400, {
          ok: false,
          error: "text is required"
        });
        appendAccessLog(req, pathName, 400, "chat missing text");
        return;
      }

      sendTextToCopilotChat(text);
      writeJson(res, 200, {
        ok: true,
        action: "chat",
        text
      });
      appendAccessLog(req, pathName, 200, "chat sent");
      return;
    }

    if (pathName === "/continue") {
      if (method !== "GET" && method !== "POST") {
        writeJson(res, 405, {
          ok: false,
          error: "method not allowed"
        });
        appendAccessLog(req, pathName, 405, "continue method");
        return;
      }

      sendTextToCopilotChat(config.continueText);
      writeJson(res, 200, {
        ok: true,
        action: "continue",
        text: config.continueText
      });
      appendAccessLog(req, pathName, 200, "continue sent");
      return;
    }

    writeJson(res, 404, {
      ok: false,
      error: "not found"
    });
    appendAccessLog(req, pathName, 404, "not found");
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    writeJson(res, 500, {
      ok: false,
      error: message
    });
    appendAccessLog(req, pathName, 500, message);
  }
});

server.listen(config.port, listenHost, () => {
  const bindText = config.bindHost;
  const prefix = `http://${bindText}:${config.port}/`;
  console.log(`Copilot LAN Bridge (Node.js) started at ${prefix}`);
  console.log(`Auth mode: ${config.noAuth ? "none (not recommended)" : "token"}`);
  console.log("Routes: GET /, GET /logs, GET/POST /chat, GET/POST /continue, GET /health");
  console.log("Press Ctrl+C to stop");
});
