# Claude Code 一键安装脚本

[English](#claude-code-one-click-installer) | **中文**

自动安装 [Claude Code](https://www.npmjs.com/package/@anthropic-ai/claude-code) 的跨平台脚本。自动检测系统、架构和网络环境,中国 IP 自动切换镜像源加速下载。

## 功能

- **自动检测系统**:Linux / macOS / Windows
- **自动检测架构**:x64 / arm64 / armv7l(Unix)、x64 / arm64 / x86(Windows)
- **自动检测中国 IP**:三段探测(Cloudflare trace → ipinfo 国家码 → google/镜像可达性),命中后自动启用镜像源
- **自动安装 Node.js**:缺少 Node 18+ 时自动安装(Unix 用 fnm,Windows 用 winget)
- **全局安装** `@anthropic-ai/claude-code`,中国环境走 npmmirror 镜像

## 使用方法

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/xiaokuqwq/easyinstall-claude.code/main/install.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/xiaokuqwq/easyinstall-claude.code/main/install.ps1 | iex
```

安装完成后,在新终端运行:

```bash
claude
```

## 镜像源说明

检测到中国 IP 时自动使用:

| 用途 | 镜像地址 |
| --- | --- |
| npm registry | `https://registry.npmmirror.com` |
| Node.js 发行版(Unix/fnm) | `https://npmmirror.com/mirrors/node` |

非中国 IP(或判定不确定)时使用 npm / Node 官方默认源。

## 前置条件

- **Linux / macOS**:需要 `curl`(用于网络探测和安装 fnm)
- **Windows**:需要 `winget`(用于自动安装 Node;若无 winget 请先手动安装 [Node.js 18+](https://nodejs.org/en/download) 或使用 nvm-windows)

## 已知限制

- Windows 下 winget 无法将 Node 安装包下载源指向镜像,因此中国环境的 **Node 本体下载**可能较慢;npm 包下载已走镜像。需要完整镜像化可改用 nvm-windows 配合环境变量 `NVM_NODEJS_ORG_MIRROR`。
- 中国 IP 检测依赖网络探测,所有探测超时(2-3 秒)后默认按非中国处理。

## 安装失败排查

- **权限错误(EACCES)**:参考 [npm 官方文档](https://docs.npmjs.com/resolving-eacces-permissions-errors)
- **`claude` 命令找不到**:打开一个新的终端窗口后再运行,使 PATH 生效

---

# Claude Code One-Click Installer

**English** | [中文](#claude-code-一键安装脚本)

Cross-platform scripts that install [Claude Code](https://www.npmjs.com/package/@anthropic-ai/claude-code) automatically. They detect your OS, architecture, and network, and switch to mirror sources to speed up downloads when a China IP is detected.

## Features

- **OS detection**: Linux / macOS / Windows
- **Architecture detection**: x64 / arm64 / armv7l (Unix), x64 / arm64 / x86 (Windows)
- **China IP detection**: three-stage probe (Cloudflare trace → ipinfo country code → google/mirror reachability); mirror sources kick in on a match
- **Auto-install Node.js**: installs Node 18+ when missing (fnm on Unix, winget on Windows)
- **Global install** of `@anthropic-ai/claude-code`, via the npmmirror registry in China

## Usage

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/xiaokuqwq/easyinstall-claude.code/main/install.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/xiaokuqwq/easyinstall-claude.code/main/install.ps1 | iex
```

After install, open a new terminal and run:

```bash
claude
```

## Mirror sources

Used automatically when a China IP is detected:

| Purpose | Mirror |
| --- | --- |
| npm registry | `https://registry.npmmirror.com` |
| Node.js distributions (Unix/fnm) | `https://npmmirror.com/mirrors/node` |

Non-China IPs (or undetermined results) use the official npm / Node default sources.

## Prerequisites

- **Linux / macOS**: `curl` (for network probes and installing fnm)
- **Windows**: `winget` (for auto-installing Node; if winget is unavailable, install [Node.js 18+](https://nodejs.org/en/download) manually or use nvm-windows)

## Known limitations

- On Windows, winget can't point the Node installer download at a mirror, so the **Node binary download** may be slow in China; npm package downloads already use the mirror. For full mirroring, use nvm-windows with the `NVM_NODEJS_ORG_MIRROR` environment variable.
- China IP detection relies on network probes; if all probes time out (2-3s) it defaults to non-China.

## Troubleshooting

- **Permission error (EACCES)**: see the [npm docs](https://docs.npmjs.com/resolving-eacces-permissions-errors)
- **`claude` command not found**: open a new terminal window so the updated PATH takes effect
