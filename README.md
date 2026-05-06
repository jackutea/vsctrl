# VS Code Copilot LAN Bridge

支持两种实现：

- `Node.js + TypeScript`（推荐，默认入口）
- `PowerShell`（保留兼容实现）

统一提供这些路由：

- `/`：手机控制面板（网页）
- `/logs`：访问日志页面（默认显示最近 250 条）
- `/chat`：向 Copilot Chat 发送一条消息
- `/continue`：发送“继续”指令
- `/health`：健康检查

## 1. 用 CMD 启动（默认 Node.js TypeScript）

在命令行里进入目录后执行：

```cmd
cd /d e:\vsctrl
run.cmd
```

`run.cmd` 会自动：

- 检查 Node.js
- 首次执行 `npm install`
- 编译 TypeScript
- 启动服务（默认 `8787` + `--noAuth`）

可追加参数（支持 `--xxx` 或 `-Xxx` 两种风格）：

```cmd
run.cmd --port 8787 --bindHost + --token your-strong-token --chatHotkey "^%i"
```

参数说明：

- `--port` / `-Port`：监听端口，默认 `8787`
- `--bindHost` / `-BindHost`：监听主机，默认 `+`（局域网可访问）
- `--token` / `-Token`：访问令牌
- `--chatHotkey` / `-ChatHotkey`：打开 Copilot Chat 的快捷键，默认 `Ctrl+Alt+I`（`^%i`）
- `--continueText` / `-ContinueText`：`/continue` 实际发送文本，默认 `continue`
- `--noAuth` / `-NoAuth`：关闭鉴权（不推荐）

## 2. 用 Node 手动启动（可选）

```cmd
cd /d e:\vsctrl
npm install
npm run build
node dist\server.js --port 8787 --bindHost + --token your-strong-token
```

## 3. PowerShell 兼容实现（可选）

如果你仍想使用原来的 PowerShell 实现：

```powershell
Set-Location e:\vsctrl
powershell -ExecutionPolicy Bypass -File .\copilot-lan-bridge.ps1 -Port 8787 -BindHost "+" -Token "your-strong-token" -ChatHotkey "^%i"
```

## 4. 手机调用示例

假设电脑局域网 IP 是 `192.168.1.100`。

### 打开控制面板

```text
http://192.168.1.100:8787/
```

### 健康检查

```bash
curl "http://192.168.1.100:8787/health"
```

### 发送聊天消息

```bash
curl -X POST "http://192.168.1.100:8787/chat" \
  -H "Content-Type: application/json" \
  -H "X-Bridge-Token: your-strong-token" \
  -d '{"text":"请帮我总结当前文件"}'
```

### 继续输出

```bash
curl -X POST "http://192.168.1.100:8787/continue" \
  -H "X-Bridge-Token: your-strong-token"
```

## 5. 重要限制

无论是 Node 版还是 PowerShell 版，本质都依赖 Windows 桌面自动化把文本发到 VS Code：

- 需要保持 Windows 已登录桌面（不能锁屏）
- 发送时 VS Code 会被切到前台
- 依赖你本机 Copilot Chat 快捷键可用

## 6. 常见问题

- Q: 无法访问服务
- A: 检查防火墙是否放行 `8787` 端口
- Q: 返回 `401 unauthorized`
- A: 确认 `token` 或 `X-Bridge-Token`
- Q: 没有发到聊天框
- A: 检查 `chatHotkey` 是否与本机一致
- Q: 中文乱码
- A: 请求头使用 `Content-Type: application/json; charset=utf-8`