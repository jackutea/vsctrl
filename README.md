# VS Code Copilot LAN Bridge

这个目录提供一个可在 VS Code 终端运行的本地服务，让手机通过局域网调用：

- `/`：手机控制面板（网页）
- `/logs`：访问日志页面（默认显示最近 250 条）
- `/chat`：向 Copilot Chat 发送一条消息
- `/continue`：发送“继续”指令

## 1. 启动服务

在 VS Code 终端 (PowerShell) 中运行：

```powershell
Set-Location e:\vsctrl
powershell -ExecutionPolicy Bypass -File .\copilot-lan-bridge.ps1 -Port 8787 -BindHost "+" -Token "your-strong-token" -ChatHotkey "^%i"
```

参数说明：

- `-Port`：监听端口，默认 `8787`
- `-BindHost`：监听主机，默认 `+`（局域网可访问）
- `-Token`：访问令牌（推荐设置复杂一些）
- `-ChatHotkey`：打开 Copilot Chat 的快捷键。默认 `Ctrl+Alt+I`，如果你改过 VS Code 快捷键，请同步修改
- `-ContinueText`：`/continue` 实际发送的文本，默认 `continue`
- `-NoAuth`：关闭鉴权（不推荐，仅用于内网临时调试）

如果提示拒绝访问（URL ACL 权限），请在管理员 PowerShell 执行一次：

```powershell
netsh http add urlacl url=http://+:8787/ user=$env:USERNAME
```

若只做本机测试（不让手机访问），可使用：

```powershell
powershell -ExecutionPolicy Bypass -File .\copilot-lan-bridge.ps1 -Port 8787 -BindHost "localhost" -Token "your-strong-token"
```

## 2. 手机调用示例

假设电脑局域网 IP 是 `192.168.1.100`。

### 打开控制面板

直接在手机浏览器打开：

```text
http://192.168.1.100:8787/
```

输入 token 后可点击：

- `Send Chat`
- `Continue`
- `Health`
- `Logs`

并支持 `Quick Prompts` 一键发送常用提示词。

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

也可以 GET：

```bash
curl "http://192.168.1.100:8787/chat?token=your-strong-token&text=你好"
```

### 继续输出

```bash
curl -X POST "http://192.168.1.100:8787/continue" \
  -H "X-Bridge-Token: your-strong-token"
```

## 3. 重要限制

此方案通过 Windows 桌面自动化把文本粘贴到 VS Code Copilot Chat 输入框并回车，因此：

- 需要保持 Windows 处于已登录桌面状态（不能锁屏）
- 发送时 VS Code 会被拉到前台
- 依赖你本机 Copilot Chat 快捷键正确可用

## 4. 常见问题

- Q:无法访问服务
    - A:检查防火墙是否放行 `8787` 端口
    - A:用管理员`netsh http add urlacl url=http://+:8787/ user=$env:USERNAME`
- Q:返回 `401 unauthorized`
    - A:确认 `token` 或 `X-Bridge-Token`
- Q:没有发到聊天框
    - A:检查 `-ChatHotkey` 是否与本机一致
- Q:中文乱码
    - A:请求头使用 `Content-Type: application/json; charset=utf-8`