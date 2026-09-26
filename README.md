<div align="center">

# 🐧 WSL / Linux 开发环境初始化工具

**一条命令，把新开的 WSL 或 Linux 系统配置成可用的 AI 开发环境**

![Linux](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20Fedora%20%7C%20Arch%20%7C%20openSUSE%20%7C%20Alpine-FCC624?logo=linux&logoColor=black)
![WSL](https://img.shields.io/badge/WSL-2-0078D4?logo=linux&logoColor=white)
![Arch](https://img.shields.io/badge/arch-x86__64%20%7C%20aarch64-555)
![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)

Claude Code · Codex · CC Switch · 一键更新 · Docker Desktop 集成检查 · APT 清华源

</div>

---

## ✨ 功能

| | 功能 | 说明 |
|---|---|---|
| 🤖 | **Claude Code** | 使用官方原生安装器；官方安装器下载中断时，自动改用 curl 断点续传并做 SHA256 校验 |
| 🧠 | **Codex** | 使用 OpenAI 官方安装器 |
| 🔀 | **CC Switch** | 使用 [cc-switch-cli](https://github.com/SaladDay/cc-switch-cli) 官方安装器 |
| 🔄 | **一键更新** | 只更新已安装的工具，没装的不会被额外安装 |
| 🐳 | **Docker Desktop 检查** | 诊断 WSL Integration 状态，缺少 docker 组权限时可引导修复 |
| 📦 | **多发行版** | 自动识别 apt / dnf / yum / zypper / pacman / apk，缺少的依赖自动安装 |
| 🪞 | **APT 清华源** | 仅 Debian：一键换源，改动前自动备份，可随时恢复 |
| 📊 | **状态面板** | 菜单中直接显示各工具的版本和 Docker 连接状态 |

## 🚀 快速开始

在 WSL 或 Linux 终端里执行其中一条命令即可。

**GitHub**

```bash
curl -fsSL https://raw.githubusercontent.com/coeeshu/WSL-Initialization/main/wsl-setup.sh | bash
```

**国内备用（jsDelivr CDN，GitHub 访问不了时使用）**

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/coeeshu/WSL-Initialization@main/wsl-setup.sh | bash
```

> jsDelivr 有缓存，仓库更新后可能要过几个小时才会拿到新版本。

<details>
<summary>更稳妥的方式：先下载，看过内容再运行</summary>

```bash
curl -fsSLO https://raw.githubusercontent.com/coeeshu/WSL-Initialization/main/wsl-setup.sh
less wsl-setup.sh
bash wsl-setup.sh
```

</details>

> [!TIP]
> 不想进入菜单，可以直接传参数，例如一键安装全部，或者只更新已安装的工具：
> ```bash
> curl -fsSL https://raw.githubusercontent.com/coeeshu/WSL-Initialization/main/wsl-setup.sh | bash -s -- --all
> curl -fsSL https://raw.githubusercontent.com/coeeshu/WSL-Initialization/main/wsl-setup.sh | bash -s -- --update
> ```

> [!NOTE]
> Alpine 默认没有 bash 和 curl，需要先执行 `apk add bash curl`。

## 🖥️ 交互菜单

```text
  WSL / Linux 开发环境初始化
  Debian GNU/Linux 13 (trixie) · x86_64 · coee · systemd · WSL: Debian
  ──────────────────────────────────────────────────

  开发工具
   1  Claude Code      ● 2.1.282
   2  Codex            ● 0.157.0
   3  CC Switch        ○ 未安装

  Docker
   4  Docker           ● 已连接 Desktop · Engine 29.4.0 · Compose 5.1.2

  系统
   5  APT 源切换为清华源 (先备份)
   6  恢复 APT 源备份
   7  安装原生 Docker (不推荐与 Docker Desktop 同时使用)

   a  安装 / 更新全部     u  只更新已安装的     r  刷新     q  退出
  ──────────────────────────────────────────────────
  选择 (可多选，如 1 3) ›
```

- 可以一次选多项，用空格或逗号分隔，例如 `1 3`
- 执行结束后会汇总每一项的结果（✔ / ✘ / !）
- 只有会修改系统的操作（换源、安装原生 Docker）才需要二次确认

## ⚙️ 命令行参数

| 参数 | 作用 |
|---|---|
| `--all` | 安装 / 更新 Claude Code、Codex、CC Switch，并检查 Docker |
| `--update` | 只更新已安装的工具（Claude Code 使用 `claude update`） |
| `--claude` | 安装 / 更新 Claude Code |
| `--codex` | 安装 / 更新 Codex |
| `--cc-switch` | 安装 / 更新 CC Switch |
| `--docker` | 检查 Docker Desktop WSL 集成（不安装任何软件） |
| `--docker-native` | 安装原生 Docker（仅 Debian 12 / 13，不推荐与 Docker Desktop 同时使用） |
| `--mirror` | 系统 APT 源切换为清华源（仅 Debian，自动备份） |
| `--restore` | 从备份恢复 APT 源（仅 Debian） |
| `--status` | 查看安装状态 |
| `--yes`, `-y` | 跳过确认提示 |
| `--help`, `-h` | 显示帮助 |

参数可以组合使用，会按顺序执行：

```bash
bash wsl-setup.sh --claude --codex --docker
```

**环境变量**

| 变量 | 说明 |
|---|---|
| `CLAUDE_CHANNEL` | Claude Code 渠道：`stable` / `latest` / 具体版本号，默认 `latest` |
| `NO_COLOR` | 设为任意值即关闭彩色输出 |

```bash
CLAUDE_CHANNEL=stable bash wsl-setup.sh --claude
```

## 🐳 Docker：推荐使用 Docker Desktop

本脚本**不会**替你安装或配置 Docker Desktop，只负责检查集成状态、给出修复提示。

1. 在 Windows 上安装并启动 [Docker Desktop](https://www.docker.com/products/docker-desktop/)
2. 打开 **Settings → Resources → WSL Integration**，启用你的发行版，然后点击 **Apply & Restart**
3. 在 WSL 中运行 `bash wsl-setup.sh --docker` 检查

| 检查结果 | 含义与处理 |
|---|---|
| `● 已连接` | 可以正常使用 |
| `○ Docker Desktop 未运行` | 集成已开启，但 Docker Desktop 没有运行，在 Windows 上启动它即可 |
| `○ 未启用 WSL Integration` | 按上面的第 2 步操作，然后在 PowerShell 执行 `wsl --terminate <发行版>` |
| `! 无 docker.sock 权限` | 普通用户不在 docker 组；脚本会询问是否帮你加入，之后重新打开终端 |
| `! daemon 连接失败` | Docker Desktop 可能还在启动中，等几十秒后再试 |

> [!WARNING]
> 菜单第 7 项「WSL 原生 Docker」只适合**不装** Docker Desktop 的场景。检测到 Docker Desktop 集成时，脚本会拒绝安装，避免两套 Docker 争抢 `docker` 命令和 socket。

## 🌐 网络与代理

Claude Code、Codex 和 CC Switch 分别从 `claude.ai`、`chatgpt.com` 和 `github.com` 下载，需要网络能访问这些地址。推荐在 Windows 的 `%USERPROFILE%\.wslconfig` 中启用 mirrored 网络模式，让 WSL 自动沿用 Windows 的系统代理：

```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
```

保存后在 PowerShell 执行 `wsl --shutdown`，再重新打开终端。你也可以手动设置代理（端口改成你代理软件的端口）：

```bash
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
```

## 🔒 安全设计

- **先完整下载、再做语法检查、最后执行**：安装器不会以边下载边执行的方式运行；如果下载到的是 HTML 错误页，会直接拒绝执行
- **不会覆盖别人的文件**：`/usr/local/bin` 中已有的同名程序不会被替换
- **换源先备份**：备份存放在 `/var/backups/coee-wsl-setup/`，恢复时会校验文件，如果源文件在换源后又被手动改过，会拒绝覆盖
- **一键安装不动系统 APT 源**：安装依赖时只使用临时的源配置
- **保留签名校验**：APT 的签名校验始终开启
- **不会删除项目、数据或已有 CLI 配置**；不配置任何登录信息、API 密钥或 registry 镜像
- 用普通用户运行即可，需要 root 权限时会调用 `sudo`；**不要**用 `sudo bash wsl-setup.sh` 启动

## ❓ 常见问题

<details>
<summary><b>安装完成后提示 <code>command not found</code></b></summary>

当前终端还没有加载新的 PATH，执行下面的命令，或重新打开终端：

```bash
exec bash -l
```

</details>

<details>
<summary><b>Claude Code 安装报错：The connection dropped while downloading</b></summary>

这是 Claude Code 自带的下载器在经过部分代理时容易被中断，同一个代理下用 curl 下载却是正常的。**脚本会自动处理这种情况**：官方安装器失败后，脚本改用 curl 断点续传下载同一版本，按官方 `manifest.json` 做 SHA256 校验，放到官方的安装位置，再由 `claude install` 完成登记。这样装出来的结果与官方安装完全一致，`claude doctor` 显示为 `native`，自动更新保持开启。

如果兜底下载也失败了，请检查代理是否可用，或者换一个节点再重试：

```bash
bash wsl-setup.sh --claude
```

</details>

<details>
<summary><b>提示"下载到的内容不是有效的安装脚本"</b></summary>

通常是地区限制，或者代理返回了网页而不是脚本文件。检查代理是否生效：

```bash
env | grep -i _proxy
curl -sI https://claude.ai/install.sh | head -1
```

</details>

<details>
<summary><b>报错 <code>$'\r': command not found</code></b></summary>

脚本的换行符被转换成了 Windows 格式（CRLF）。重新下载，或者修复换行：

```bash
sed -i 's/\r$//' wsl-setup.sh
```

</details>

<details>
<summary><b>docker pull 报错 error getting credentials</b></summary>

`~/.docker/config.json` 中的 `credsStore` 依赖 Windows 端的凭据程序。确认 `/etc/wsl.conf` 中没有设置 `appendWindowsPath=false`；如果不需要保存凭据，也可以删除 `credsStore` 这一行。

</details>

## 🗑️ 卸载

```bash
# Claude Code
rm -f ~/.local/bin/claude && rm -rf ~/.local/share/claude
# Codex
rm -f ~/.local/bin/codex && rm -rf ~/.codex/packages
# CC Switch
rm -f ~/.local/bin/cc-switch
```

以 root 运行过的话，还需要删除 `/usr/local/bin` 中对应的符号链接。脚本写入 `~/.profile` / `~/.bashrc` 的 PATH 配置以 `# coee-wsl-setup: local-bin` 开头，可以按需删除；修改前的原文件备份为 `*.coee-backup-*`。

## 📋 系统要求

- WSL 2，或者任意常见的 Linux 发行版
- x86_64 或 aarch64
- 具有 `sudo` 权限的普通用户，或者 root

| 发行版 | 包管理器 | 安装工具 | APT 换源 | 原生 Docker |
|---|---|:-:|:-:|:-:|
| Debian 12 / 13 | apt | ✅ | ✅ | ✅ |
| 其他 Debian 版本 | apt | ✅ | ✅ | — |
| Ubuntu | apt | ✅ | — | — |
| Fedora / RHEL / Rocky / Alma | dnf / yum | ✅ | — | — |
| openSUSE | zypper | ✅ | — | — |
| Arch Linux | pacman | ✅ | — | — |
| Alpine（需先 `apk add bash curl`） | apk | ✅ | — | — |

我实际测试过的发行版：Debian 12 / 13、Ubuntu 24.04、Fedora 42、Arch Linux、Alpine 3.22、openSUSE Leap 15.6。其他同系发行版原则上也能使用。

## 🙏 鸣谢

感谢 [**LINUX DO**](https://linux.do/) 社区。

## 📄 许可证

[MIT](LICENSE) © coeeshu

---

<div align="center">
<sub>如果对你有帮助，欢迎点个 ⭐</sub>
</div>
