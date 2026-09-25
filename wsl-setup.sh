#!/usr/bin/env bash
# Standalone Debian 12/13 WSL installer. Keep this file UTF-8 with LF endings.
set -uo pipefail

CLAUDE_URL=https://claude.ai/install.sh
CODEX_URL=https://chatgpt.com/codex/install.sh
CC_SWITCH_URL=https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh
CLAUDE_CHANNEL=${CLAUDE_CHANNEL:-}
TOOLS=(claude codex cc-switch)
declare -A TOOL_LABEL=([claude]='Claude Code' [codex]='Codex' [cc-switch]='CC Switch')
declare -A ACTION_LABEL=(
  [claude]='安装 / 更新 Claude Code' [codex]='安装 / 更新 Codex' [cc-switch]='安装 / 更新 CC Switch'
  [docker]='检查 Docker' [docker-native]='安装原生 Docker'
  [mirror]='APT 源切换为清华源' [restore]='恢复 APT 源备份'
)
declare -A VER=()
WORK=
SUITE=
OS_ID= OS_NAME= PKG= IS_WSL=0
AUTO_YES=0
ORIG_PATH=$PATH
DOCKER_STATE= DOCKER_DETAIL= DOCKER_ENGINE= DOCKER_OS= DOCKER_COMPOSE=

# ---------- 输出样式 ----------
if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
  C0=$'\e[0m' B=$'\e[1m' D=$'\e[2m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' CYN=$'\e[36m'
else
  C0= B= D= RED= GRN= YLW= BLU= CYN=
fi
say()  { printf '%s\n' "$*"; }
info() { printf '%s•%s %s\n' "$BLU" "$C0" "$*"; }
ok()   { printf '%s✔%s %s\n' "$GRN" "$C0" "$*"; }
warn() { printf '%s!%s %s\n' "$YLW" "$C0" "$*" >&2; }
fail() { printf '%s✘%s %s\n' "$RED" "$C0" "$*" >&2; }
hint() { printf '  %s%s%s\n' "$D" "$*" "$C0"; }
step() { printf '\n%s%s━━ %s%s\n' "$B" "$CYN" "$*" "$C0"; }
rule() { printf '  %s%s%s\n' "$D" '──────────────────────────────────────────────────' "$C0"; }
confirm() {
  local reply
  [[ $AUTO_YES == 1 ]] && return 0
  read -r -p "${YLW}?${C0} $1 ${D}[y/N]${C0} " reply || return 1
  [[ $reply =~ ^([yY]|[yY][eE][sS])$ ]]
}
pause() {
  [[ -t 0 && -t 1 ]] || return 0
  read -r -s -n 1 -p "${D}按任意键返回菜单…${C0}" || true
  printf '\n'
}
clear_screen() { [[ -t 1 ]] && printf '\e[H\e[2J\e[3J'; }

# ---------- 基础 ----------
as_root() {
  if [[ $EUID == 0 ]]; then "$@"; else sudo -- "$@"; fi
}
prepare_path() {
  local entry current=$PATH
  local -a entries
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin"
  IFS=: read -r -a entries <<< "$current"
  for entry in "${entries[@]}"; do
    # Windows PATH entries (e.g. npm's claude/codex shims) must never shadow Linux tools.
    case "$entry" in /mnt/[a-z]/*|''|.) continue ;; esac
    case ":$PATH:" in *":$entry:"*) ;; *) PATH+=":$entry" ;; esac
  done
  export PATH
  hash -r
}
cleanup() {
  if [[ -n $WORK && -d $WORK && $WORK == /tmp/coee-wsl-setup.* ]]; then
    # APT lists inside $WORK are root-owned; plain rm first to avoid a sudo prompt when possible.
    rm -rf -- "$WORK" 2>/dev/null || as_root rm -rf -- "$WORK"
  fi
}
detect_system() {
  local ID= VERSION_ID= PRETTY_NAME= NAME= pm
  if [[ -f /etc/os-release ]]; then
    # This is a system-owned shell-compatible file, not user input.
    . /etc/os-release
  fi
  OS_ID=${ID:-linux}
  OS_NAME=${PRETTY_NAME:-${NAME:-Linux}}
  # Debian 12/13 get the scoped Tsinghua APT source, mirror switching and native Docker.
  case "$OS_ID:$VERSION_ID" in
    debian:12) SUITE=bookworm ;;
    debian:13) SUITE=trixie ;;
  esac
  for pm in apt-get dnf yum zypper pacman apk; do
    command -v "$pm" >/dev/null && { PKG=$pm; break; }
  done
  # Not the kernel string: containers under Docker Desktop share the WSL kernel.
  if [[ -n ${WSL_DISTRO_NAME:-} || -e /proc/sys/fs/binfmt_misc/WSLInterop || -d /run/WSL ]]; then
    IS_WSL=1
  fi
  case "$(uname -m)" in
    x86_64|aarch64) ;;
    *) fail '安装器仅支持 x86_64 / aarch64。'; return 1 ;;
  esac
  if [[ $EUID == 0 && -n ${SUDO_USER:-} && ${SUDO_USER:-root} != root ]]; then
    fail '请用普通用户运行 bash wsl-setup.sh，脚本会在需要时调用 sudo；不要用 sudo 启动整个脚本。'
    return 1
  fi
  if [[ $EUID != 0 ]] && ! command -v sudo >/dev/null; then
    fail '当前用户没有 sudo，请切换 root 后运行。'; return 1
  fi
}
make_work() {
  [[ -n $WORK ]] && return 0
  WORK=$(mktemp -d /tmp/coee-wsl-setup.XXXXXXXX) || return 1
  # APT's _apt sandbox needs traversal; installer downloads remain private.
  chmod 755 "$WORK" || return 1
  mkdir -m 700 "$WORK/downloads" || return 1
}

# ---------- APT（临时清华源，不改系统配置） ----------
write_apt_sources() {
  local scheme=${1:-https}
  printf '%s\n' \
    "deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] $scheme://mirrors.tuna.tsinghua.edu.cn/debian $SUITE main" \
    "deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] $scheme://mirrors.tuna.tsinghua.edu.cn/debian $SUITE-updates main" \
    "deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] $scheme://mirrors.tuna.tsinghua.edu.cn/debian-security $SUITE-security main" > "$WORK/sources.list"
}
apt_scoped() {
  as_root env DEBIAN_FRONTEND=noninteractive apt-get \
    -o "Dir::Etc::sourcelist=$WORK/sources.list" \
    -o Dir::Etc::sourceparts=- \
    -o "Dir::State::lists=$WORK/lists" \
    -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 \
    -o APT::Update::Error-Mode=any "$@"
}
prepare_apt() {
  [[ -f ${WORK:-/nonexistent}/apt-ready ]] && return 0
  make_work || return 1
  [[ -r /usr/share/keyrings/debian-archive-keyring.gpg ]] || {
    fail '缺少 Debian 官方签名密钥环，请先修复基础系统；不会禁用 APT 签名校验。'; return 1;
  }
  mkdir -p "$WORK/lists/partial" || return 1
  if [[ ! -s /etc/ssl/certs/ca-certificates.crt ]]; then
    warn '缺少 CA 证书：先从清华 HTTP 源通过 Debian 签名验证安装 ca-certificates，随后切回 HTTPS。'
    write_apt_sources http || return 1
    apt_scoped update || return 1
    apt_scoped install -y --no-remove --no-install-recommends ca-certificates || return 1
  fi
  write_apt_sources https || return 1
  info '刷新临时 APT 索引（清华源）…'
  apt_scoped update -qq || return 1
  touch "$WORK/apt-ready"
}
# ---------- 通用包管理 ----------
pkg_install() {
  local -a pkgs=("$@")
  info "安装依赖：${pkgs[*]}"
  case "$PKG" in
    apt-get)
      if [[ -n $SUITE ]]; then
        prepare_apt || return 1
        apt_scoped install -y --no-remove --no-install-recommends "${pkgs[@]}"
      else
        as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq || return 1
        as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
      fi ;;
    dnf|yum) as_root "$PKG" install -y "${pkgs[@]}" ;;
    zypper) as_root zypper --non-interactive install --no-recommends "${pkgs[@]}" ;;
    # -Syu, not -Sy: Arch doesn't support partial upgrades.
    pacman) as_root pacman -Syu --needed --noconfirm "${pkgs[@]}" ;;
    apk) as_root apk add --no-cache "${pkgs[@]}" ;;
    *) fail "未识别的包管理器，请手动安装：${pkgs[*]}"; return 1 ;;
  esac
}
has_ca_bundle() {
  local f
  for f in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
      /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
    [[ -s $f ]] && return 0
  done
  return 1
}
ensure_download_tools() {
  local -a need=()
  command -v curl >/dev/null || need+=(curl)
  command -v tar >/dev/null || need+=(tar)
  command -v gzip >/dev/null || need+=(gzip)
  has_ca_bundle || need+=(ca-certificates)
  ((${#need[@]})) || return 0
  pkg_install "${need[@]}"
}
ensure_python() {
  command -v python3 >/dev/null && return 0
  pkg_install python3
}
# musl systems (Alpine) need these runtime libraries for Claude Code.
ensure_claude_deps() {
  [[ $PKG == apk ]] || return 0
  local -a need=()
  apk info -e libgcc >/dev/null || need+=(libgcc)
  apk info -e libstdc++ >/dev/null || need+=(libstdc++)
  command -v rg >/dev/null || need+=(ripgrep)
  ((${#need[@]})) || return 0
  pkg_install "${need[@]}"
}
# Pure-bash "a >= b" for dotted versions; dpkg isn't available everywhere.
version_ge() {
  local IFS=. i
  local -a a b
  read -r -a a <<< "${1%%[!0-9.]*}"
  read -r -a b <<< "${2%%[!0-9.]*}"
  for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
    ((10#${a[i]:-0} > 10#${b[i]:-0})) && return 0
    ((10#${a[i]:-0} < 10#${b[i]:-0})) && return 1
  done
  return 0
}
is_debian_tuned() { [[ -n $SUITE ]]; }

# ---------- CLI 工具 ----------
tool_bin() {
  local name=$1
  if command -v "$name" 2>/dev/null; then return 0; fi
  [[ -x $HOME/.local/bin/$name ]] && printf '%s\n' "$HOME/.local/bin/$name"
}
tool_version() {
  local bin out
  bin=$(tool_bin "$1") || return 1
  [[ -n $bin ]] || return 1
  out=$(timeout 10 "$bin" --version 2>/dev/null) || return 1
  if [[ $out =~ [0-9]+\.[0-9]+(\.[0-9]+)?([-+][0-9A-Za-z.]+)? ]]; then
    printf '%s\n' "${BASH_REMATCH[0]}"
  else
    printf '%s\n' "${out%%$'\n'*}"
  fi
}
install_cli() {
  local name=$1 url=$2 interpreter=$3 installer before after
  if [[ $EUID == 0 && ( -e /usr/local/bin/$name || -L /usr/local/bin/$name ) ]] &&
      [[ $(readlink "/usr/local/bin/$name") != "$HOME/.local/bin/$name" ]]; then
    fail "/usr/local/bin/$name 已被其他安装占用；不会覆盖，请先人工检查。"; return 1
  fi
  before=$(tool_version "$name" || true)
  ensure_download_tools || return 1
  if [[ $name == claude ]]; then
    ensure_claude_deps || return 1
    # A native install updates itself (and keeps its configured channel); reinstall only as fallback.
    if [[ -z $CLAUDE_CHANNEL && -n $before && -x $HOME/.local/bin/claude ]]; then
      info '使用 claude update 更新…'
      if "$HOME/.local/bin/claude" update; then
        finish_cli "$name" "$before"; return
      fi
      warn 'claude update 失败（常见原因：代理中断了大文件下载），改用 curl 下载并校验。'
      claude_manual_install || return 1
      finish_cli "$name" "$before"; return
    fi
  fi
  make_work || return 1
  installer="$WORK/downloads/$name.sh"
  info "下载安装器 ${D}$url${C0}"
  # Download fully and syntax-check before executing; never run a partial pipe.
  curl -fLSs --proto '=https' --proto-redir '=https' --retry 3 \
    --connect-timeout 15 --max-time 180 -o "$installer" "$url" || {
    fail '下载失败。'; hint '检查网络 / 代理（WSL 内可设置 https_proxy）。'; return 1;
  }
  [[ -s $installer ]] || { fail '安装器为空。'; return 1; }
  "$interpreter" -n "$installer" 2>/dev/null || {
    fail '下载到的内容不是有效的安装脚本（常见原因：地区限制、代理返回了 HTML 页面）。'
    hint "查看内容：head $installer（临时文件会在脚本退出时删除）"
    return 1
  }
  info '运行官方安装器…'
  case "$name" in
    claude)
      # 无参数 = latest 渠道；CLAUDE_CHANNEL 可设为 stable / latest / 具体版本号。
      bash "$installer" ${CLAUDE_CHANNEL:+"$CLAUDE_CHANNEL"} || {
        warn '官方安装器失败（常见原因：代理中断了大文件下载），改用 curl 下载并校验。'
        claude_manual_install || return 1
      } ;;
    codex)
      CODEX_INSTALL_DIR="$HOME/.local/bin" CODEX_RELEASE=latest CODEX_NON_INTERACTIVE=true \
        sh "$installer" || return 1 ;;
    cc-switch)
      CC_SWITCH_INSTALL_DIR="$HOME/.local/bin" CC_SWITCH_FORCE=1 \
        bash "$installer" || return 1 ;;
  esac
  [[ -x $HOME/.local/bin/$name ]] || { fail "安装器结束，但没有找到 ~/.local/bin/$name。"; return 1; }
  finish_cli "$name" "$before"
}
# Fallback when Claude's built-in downloader fails behind a proxy: fetch the same release with
# curl, verify it against the release manifest, lay it out exactly like the native installer,
# then let `claude install` register it (it reuses an existing version instead of downloading).
claude_manual_install() {
  local base=https://downloads.claude.ai/claude-code-releases arch platform version manifest
  local checksum file dest attempt
  local re='"checksum"[[:space:]]*:[[:space:]]*"([a-f0-9]{64})"'
  case "$(uname -m)" in x86_64) arch=x64 ;; aarch64) arch=arm64 ;; esac
  platform=linux-$arch
  if [[ -f /lib/libc.musl-x86_64.so.1 || -f /lib/libc.musl-aarch64.so.1 ]] ||
      ldd /bin/ls 2>&1 | grep -q musl; then
    platform+=-musl
  fi
  if [[ $CLAUDE_CHANNEL =~ ^[0-9] ]]; then
    version=$CLAUDE_CHANNEL
  else
    version=$(curl -fsSL --retry 3 --max-time 30 "$base/${CLAUDE_CHANNEL:-latest}") || {
      fail '获取 Claude Code 版本号失败。'; return 1;
    }
  fi
  [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || { fail "版本号格式异常：${version:0:40}"; return 1; }
  manifest=$(curl -fsSL --retry 3 --max-time 30 "$base/$version/manifest.json") || {
    fail '下载 manifest.json 失败。'; return 1;
  }
  # Collapse whitespace so the regex can match the platform's block regardless of formatting.
  manifest=$(tr -d '\n\r' <<< "$manifest")
  [[ $manifest =~ \"$platform\"[[:space:]]*:[[:space:]]*\{[^}]*$re ]] || {
    fail "manifest 中没有 $platform。"; return 1;
  }
  checksum=${BASH_REMATCH[1]}
  dest=$HOME/.local/share/claude/versions/$version
  if [[ -e $HOME/.local/bin/claude || -L $HOME/.local/bin/claude ]] &&
      [[ $(readlink "$HOME/.local/bin/claude") != "$HOME/.local/share/claude/versions/"* ]]; then
    fail '~/.local/bin/claude 不是原生安装的启动链接，不会覆盖，请先人工检查。'; return 1
  fi
  make_work || return 1
  file=$WORK/downloads/claude-$version-$platform
  info "下载 Claude Code $version（$platform）…"
  for attempt in 1 2 3; do
    # -C - resumes a partial file, so retries don't restart a dropped download from zero.
    curl -fL --progress-bar --proto '=https' --retry 3 --connect-timeout 15 -C - -o "$file" \
      "$base/$version/$platform/claude" && break
    warn "下载中断，重试（$attempt/3）…"
  done
  [[ $(sha256sum "$file" 2>/dev/null) == "$checksum "* ]] || {
    fail 'SHA256 校验失败，已放弃安装。'; rm -f -- "$file"; return 1;
  }
  ok 'SHA256 校验通过'
  mkdir -p "${dest%/*}" "$HOME/.local/bin" || return 1
  install -m 755 "$file" "$dest.tmp.$$" && mv -f "$dest.tmp.$$" "$dest" || return 1
  ln -sfn "$dest" "$HOME/.local/bin/claude" || return 1
  "$dest" install "${CLAUDE_CHANNEL:-latest}" ||
    warn 'claude install 登记失败；程序已可用，稍后可手动运行 claude install。'
}
finish_cli() {
  local name=$1 before=$2 after
  ensure_path "$name" || return 1
  after=$(tool_version "$name") || { fail "$name --version 运行失败。"; return 1; }
  if [[ -z $before ]]; then ok "${TOOL_LABEL[$name]} $after 已安装"
  elif [[ $before == "$after" ]]; then ok "${TOOL_LABEL[$name]} 已是最新：$after"
  else ok "${TOOL_LABEL[$name]} $before → $after"
  fi
  if [[ $name == claude ]]; then
    [[ -n $before ]] || hint '首次使用：运行 claude 按提示登录；诊断：claude doctor'
    [[ $PKG != apk ]] || hint 'Alpine：请在 ~/.claude/settings.json 的 env 中设置 "USE_BUILTIN_RIPGREP": "0"'
  fi
}
ensure_path() {
  local name=$1 profile
  local -a profiles=("$HOME/.profile" "$HOME/.bashrc")
  [[ ! -f $HOME/.zshrc ]] || profiles+=("$HOME/.zshrc")
  for profile in "${profiles[@]}"; do
    if ! grep -Fq '# coee-wsl-setup: local-bin' "$profile" 2>/dev/null; then
      [[ ! -e $profile ]] || cp -p -- "$profile" "$profile.coee-backup-$(date +%Y%m%d-%H%M%S)-$$" || return 1
      printf '\n%s\n' '# coee-wsl-setup: local-bin' \
        'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac' >> "$profile" || return 1
    fi
  done
  hash -r
  if [[ $EUID == 0 ]]; then
    publish_cli "$name" /usr/local/bin || return 1
  fi
  case ":$ORIG_PATH:" in
    *":$HOME/.local/bin:"*|*":/usr/local/bin:"*) ;;
    *) hint '当前终端还不认识新命令：脚本结束后执行 exec bash -l 或重新打开终端。' ;;
  esac
}
publish_cli() {
  local name=$1 directory=$2
  mkdir -p "$directory" || return 1
  if [[ -e $directory/$name || -L $directory/$name ]]; then
    [[ $(readlink "$directory/$name") == "$HOME/.local/bin/$name" ]] || {
      fail "$directory/$name 已被其他程序占用，不会覆盖。"; return 1;
    }
  else
    ln -s "$HOME/.local/bin/$name" "$directory/$name" || return 1
  fi
}

# ---------- Docker ----------
# Docker Desktop's WSL integration links /usr/bin/docker into /mnt/wsl/docker-desktop.
docker_is_desktop() {
  local p
  for p in /usr/bin/docker /usr/local/bin/docker /var/run/docker.sock; do
    [[ $(readlink "$p" 2>/dev/null) == /mnt/wsl/* ]] && return 0
  done
  [[ $DOCKER_OS == *'Docker Desktop'* ]]
}
docker_probe() {
  local out
  DOCKER_STATE= DOCKER_DETAIL= DOCKER_ENGINE= DOCKER_OS= DOCKER_COMPOSE=
  if [[ -n ${DOCKER_HOST:-} || -n ${DOCKER_CONTEXT:-} ]]; then DOCKER_STATE=remote; return; fi
  if ! command -v docker >/dev/null; then
    # A dangling Desktop link means integration is on but Docker Desktop isn't running.
    if docker_is_desktop; then DOCKER_STATE=stopped; else DOCKER_STATE=no-cli; fi
    return
  fi
  if out=$(timeout -k 3 12 docker version --format '{{.Server.Version}}' 2>&1); then
    DOCKER_STATE=ok DOCKER_ENGINE=$out
    DOCKER_OS=$(timeout 10 docker info --format '{{.OperatingSystem}}' 2>/dev/null || true)
    DOCKER_COMPOSE=$(timeout 10 docker compose version --short 2>/dev/null || true)
    DOCKER_COMPOSE=${DOCKER_COMPOSE#v}
  elif [[ $out == *[Pp]ermission\ denied* ]]; then
    DOCKER_STATE=perm
  else
    DOCKER_STATE=down
    out=${out%$'\n'}
    DOCKER_DETAIL=${out##*$'\n'}
  fi
}
docker_status_text() {
  case $DOCKER_STATE in
    ok)
      printf '%s● 已连接%s %s' "$GRN" "$C0" "$D"
      docker_is_desktop && printf 'Desktop · ' || printf '原生 · '
      printf 'Engine %s · Compose %s%s' "$DOCKER_ENGINE" "${DOCKER_COMPOSE:-无}" "$C0" ;;
    stopped) printf '%s○ Docker Desktop 未运行%s' "$YLW" "$C0" ;;
    no-cli)  printf '%s○ 未启用 WSL Integration%s' "$D" "$C0" ;;
    perm)    printf '%s! 无 docker.sock 权限%s' "$YLW" "$C0" ;;
    down)    printf '%s! daemon 连接失败%s' "$YLW" "$C0" ;;
    remote)  printf '%s! 已设置 DOCKER_HOST/CONTEXT%s' "$YLW" "$C0" ;;
  esac
}
fix_docker_socket() {
  local sock=/var/run/docker.sock user group
  user=$(id -un)
  group=$(stat -Lc %G "$sock" 2>/dev/null || true)
  fail "当前用户 $user 无权访问 $sock（属组：${group:-未知}）。"
  if [[ -z $group || $group == root || $group == UNKNOWN ]]; then
    hint '属组不是 docker，不自动修改；可临时使用 sudo docker。'; return 1
  fi
  if [[ " $(id -nG "$user") " == *" $group "* ]]; then
    hint "你已在 $group 组中，只是当前会话还没生效：重新打开 WSL 终端，或执行 newgrp $group。"
    return 1
  fi
  hint "$group 组成员可无 sudo 使用 Docker（权限等同 root）。"
  confirm "把 $user 加入 $group 组？" || return 1
  if command -v usermod >/dev/null; then
    as_root usermod -aG "$group" "$user" || return 1
  else
    as_root addgroup "$user" "$group" || return 1  # busybox (Alpine)
  fi
  ok "已加入 $group 组；重新打开 WSL 终端后生效（当前终端可执行 newgrp $group）。"
}
check_docker() {
  local distro=${WSL_DISTRO_NAME:-当前发行版}
  info '检测 Docker…'
  docker_probe
  case $DOCKER_STATE in
    ok)
      ok "Docker Engine $DOCKER_ENGINE${DOCKER_OS:+ · $DOCKER_OS}"
      [[ $IS_WSL == 0 ]] || docker_is_desktop || warn '当前连接的是 WSL 原生 Docker，而不是 Docker Desktop。'
      if [[ -z $DOCKER_COMPOSE ]]; then
        warn 'docker compose 不可用：请在 Docker Desktop 中确认 Compose 已启用。'
      elif ! version_ge "$DOCKER_COMPOSE" 2.20; then
        warn "Compose $DOCKER_COMPOSE 较旧（< 2.20），部分 compose 文件特性不可用。"
      else
        ok "Docker Compose $DOCKER_COMPOSE"
      fi
      return 0 ;;
    remote)
      fail 'DOCKER_HOST / DOCKER_CONTEXT 已设置，可能连向远程 daemon；为安全起见不做检查。'
      hint '确认无误后 unset DOCKER_HOST DOCKER_CONTEXT 再试。' ;;
    stopped)
      fail 'WSL Integration 已配置，但 Docker Desktop 没有运行。'
      hint '在 Windows 启动 Docker Desktop，等待状态变为 Engine running 后再试。' ;;
    no-cli)
      if [[ $IS_WSL == 0 ]]; then
        fail '没有找到 docker 命令。'
        hint '按官方文档为你的发行版安装 Docker Engine：https://docs.docker.com/engine/install/'
        return 1
      fi
      fail 'WSL 中没有 docker 命令。'
      hint "Docker Desktop → Settings → Resources → WSL Integration → 打开 $distro → Apply & Restart"
      hint "如仍不可用：在 PowerShell 执行 wsl --terminate $distro，再重新打开终端。" ;;
    perm)
      fix_docker_socket
      return ;;
    down)
      fail "docker 命令存在，但连接 daemon 失败：${DOCKER_DETAIL:-未知错误}"
      hint "确认 Docker Desktop 正在运行，且 WSL Integration 中已打开 $distro。"
      hint 'Docker Desktop 刚启动时需要等待几十秒，稍后重试即可。' ;;
  esac
  return 1
}
docker_preflight() {
  local package
  if [[ -z $SUITE ]]; then
    fail "原生 Docker 安装仅支持 Debian 12 / 13，当前系统：$OS_NAME"
    hint '其他发行版请参考：https://docs.docker.com/engine/install/'
    return 1
  fi
  docker_probe
  if [[ $DOCKER_STATE == remote ]]; then
    fail '检测到 DOCKER_HOST/DOCKER_CONTEXT，拒绝修改可能连接远程服务的 Docker。'; return 1
  fi
  if docker_is_desktop; then
    fail '检测到 Docker Desktop WSL 集成；原生 Engine 会与之争抢 docker 命令和 socket，不会混装。'
    hint '若要改用原生 Docker，请先在 Docker Desktop 的 WSL Integration 中关闭本发行版。'
    return 1
  fi
  for package in docker-ce docker-ce-cli containerd.io moby-engine moby-cli; do
    if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) == 'install ok installed' ]]; then
      fail "已有 $package。不会卸载或替换其他渠道的 Docker，请先人工确认。"; return 1
    fi
  done
}
install_docker() {
  local version
  local -a packages=(docker.io docker-compose iptables)
  docker_preflight || return 1
  warn '推荐使用 Docker Desktop 的 WSL Integration；原生 Engine 仅适合不装 Docker Desktop 的场景。'
  confirm '仍要安装 WSL 原生 Docker？' || return 1
  prepare_apt || return 1
  # Debian 13 splits the CLI and build plugin out of the engine package.
  [[ $SUITE != trixie ]] || packages+=(docker-cli docker-buildx)
  apt_scoped install -y --no-remove --no-install-recommends "${packages[@]}" || return 1
  docker --version || return 1
  # timeout must wrap the real command: it cannot exec the as_root shell function.
  if [[ $(cat /proc/1/comm) == systemd ]]; then
    as_root timeout --kill-after=5s 60s systemctl enable --now docker || {
      fail 'systemd 启动 Docker 超时或失败。'; hint '查看日志：journalctl -u docker -n 50'; return 1;
    }
  else
    warn 'WSL 未启用 systemd，尝试通过 service 启动 Docker。'
    as_root timeout --kill-after=5s 60s service docker start || {
      fail '启动失败。'
      hint '在 /etc/wsl.conf 的 [boot] 节加入 systemd=true，再在 Windows 执行 wsl --shutdown 后重开。'
      return 1
    }
  fi
  as_root timeout 20s docker info >/dev/null || { fail 'Docker daemon 尚不可用。'; return 1; }
  if version=$(docker compose version --short 2>/dev/null) &&
      version_ge "${version#v}" 2.20; then
    ok "Docker Compose ${version#v}"
  else
    warn '该 Debian 源没有提供 Compose >= 2.20（Debian 12 通常只有 Compose v1）；推荐 Debian 13。'
  fi
  if [[ $EUID != 0 ]]; then
    hint '普通用户使用 docker 需要加入 docker 组（等同 root 权限），选择「检查 Docker」可引导设置；或使用 sudo docker。'
  fi
}

# Standard RFC822 parser for deb822 fields; preserve unrelated fields/comments.
source_helper() {
  python3 - "$@" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile
from datetime import datetime
from email.parser import Parser
from urllib.parse import urlsplit

MIRROR = "https://mirrors.tuna.tsinghua.edu.cn"

def digest(data):
    return hashlib.sha256(data).hexdigest()

def new_uri(uri):
    parsed = urlsplit(uri)
    host = parsed.hostname or ""
    official = host == "debian.org" or host.endswith(".debian.org")
    known = host in {"mirrors.tuna.tsinghua.edu.cn", "mirrors.ustc.edu.cn",
                    "mirrors.aliyun.com", "mirrors.huaweicloud.com", "mirrors.163.com"}
    if parsed.scheme not in ("http", "https") or not (official or known):
        return uri
    if parsed.query or parsed.fragment or parsed.username:
        return uri
    path = parsed.path.rstrip("/")
    if host == "security.debian.org" and path in ("", "/debian-security"):
        return MIRROR + "/debian-security"
    if path in ("/debian", "/debian-security"):
        return MIRROR + path
    return uri

def transform(text, deb822):
    if not deb822:
        result = []
        for line in text.splitlines(keepends=True):
            # Only the URI token changes, not options, suites or comments.
            line = re.sub(r"^(\s*deb(?:-src)?\s+(?:\[[^\]]*\]\s+)?)(\S+)",
                          lambda m: m[1] + new_uri(m[2]), line, count=1)
            result.append(line)
        return "".join(result)
    records = re.split(r"(\n[ \t]*\n)", text)
    for index in range(0, len(records), 2):
        block = records[index]
        parsed = Parser().parsestr("".join(line for line in block.splitlines(keepends=True)
                                           if not line.lstrip().startswith("#")))
        values = parsed.get_all("URIs", [])
        if not values:
            continue
        if len(values) != 1:
            raise ValueError("duplicate URIs field; inspect this .sources file manually")
        old = values[0].split()
        new = [new_uri(uri) for uri in old]
        if old == new:
            continue
        # Replace only the URIs field and its continuations, leaving comments intact.
        lines = block.splitlines(keepends=True)
        output, in_uris = [], False
        for line in lines:
            if re.match(r"^URIs\s*:", line, re.I):
                output.append("URIs: " + " ".join(new) + ("\n" if line.endswith("\n") else ""))
                in_uris = True
            elif in_uris and line.lstrip().startswith("#"):
                output.append(line)
            elif in_uris and line[:1] in (" ", "\t"):
                continue
            else:
                in_uris = False
                output.append(line)
        records[index] = "".join(output)
    return "".join(records)

def atomic_write(path, data, metadata):
    fd, name = tempfile.mkstemp(prefix=".coee-apt-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, stat.S_IMODE(metadata.st_mode))
        os.chown(name, metadata.st_uid, metadata.st_gid)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def source_files(root):
    paths = [root / "sources.list"]
    directory = root / "sources.list.d"
    if directory.is_symlink():
        raise ValueError("sources.list.d is a symlink; inspect manually")
    paths += sorted(directory.glob("*.list")) + sorted(directory.glob("*.sources"))
    for path in paths:
        if path.is_symlink():
            raise ValueError(f"refusing source symlink: {path}")
        if path.is_file():
            yield path

def switch(root, backups):
    plan = []
    for path in source_files(root):
        before = path.read_bytes()
        after = transform(before.decode("utf-8"), path.suffix == ".sources").encode("utf-8")
        if before != after:
            plan.append((path, before, after, path.stat()))
    if not plan:
        print("无需修改：已是清华源，或没有可识别的 Debian 官方/常用镜像源。")
        return
    backups.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup = Path(tempfile.mkdtemp(prefix=datetime.now().strftime("apt-%Y%m%d-%H%M%S-"), dir=backups))
    records = []
    for path, before, after, meta in plan:
        relative = str(path.relative_to(root))
        saved = backup / relative
        saved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, saved)
        os.chown(saved, meta.st_uid, meta.st_gid)
        records.append({"path": relative, "before": digest(before), "after": digest(after)})
    (backup / "manifest.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
    print(f"备份目录：{backup}", flush=True)
    try:
        for path, before, after, meta in plan:
            if path.is_symlink() or path.read_bytes() != before:
                raise ValueError(f"source changed during operation: {path}")
            atomic_write(path, after, meta)
            print(f"已更新：{path}")
    except Exception:
        for path, before, after, meta in plan:
            if not path.is_symlink() and path.read_bytes() == after:
                atomic_write(path, before, meta)
        raise

def restore(root, backup):
    records = json.loads((backup / "manifest.json").read_text(encoding="utf-8"))
    plan = []
    for record in records:
        rel = record["path"]
        if rel != "sources.list" and not re.fullmatch(r"sources\.list\.d/[^/]+\.(list|sources)", rel):
            raise ValueError("invalid backup path")
        path, saved = root / rel, backup / rel
        if path.is_symlink() or saved.is_symlink() or path.parent.is_symlink() or saved.parent.is_symlink():
            raise ValueError("refusing symlink on restore")
        before = saved.read_bytes()
        current = path.read_bytes()
        if digest(before) != record["before"]:
            raise ValueError(f"backup checksum mismatch: {saved}")
        if digest(current) == record["before"]:
            continue
        if digest(current) != record["after"]:
            raise ValueError(f"{path} has newer edits; refusing to overwrite them")
        plan.append((path, before, saved.stat()))
    for path, data, meta in plan:
        atomic_write(path, data, meta)
        print(f"已恢复：{path}")
    print("备份保留，可再次检查。")

def main():
    action, root, destination = sys.argv[1:]
    root, destination = Path(root), Path(destination)
    if root.is_symlink() or destination.is_symlink():
        raise ValueError("refusing symlink root")
    if action == "switch":
        switch(root, destination)
    elif action == "restore":
        restore(root, destination)
    else:
        raise ValueError("unknown action")

try:
    main()
except Exception as exc:
    print(f"APT 源操作失败：{exc}", file=sys.stderr)
    sys.exit(1)
PY
}
root_source_helper() {
  # Feed only this trusted embedded helper to root, never user-provided code.
  if [[ $EUID == 0 ]]; then
    source_helper "$@"
  else
    { declare -f source_helper; printf 'source_helper "$@"\n'; } | sudo bash -s -- "$@"
  fi
}
system_apt_update() {
  info '刷新系统 APT 索引…'
  as_root apt-get -qq -o Acquire::Retries=3 -o Acquire::http::Timeout=30 \
    -o Acquire::https::Timeout=30 -o APT::Update::Error-Mode=any update || {
    fail 'APT 更新失败；可能是网络或原有第三方源问题。备份已保留，可用「恢复 APT 源备份」还原。'; return 1;
  }
}
require_debian() {
  [[ $OS_ID == debian && $PKG == apt-get ]] && return 0
  fail "APT 换源仅支持 Debian，当前系统：$OS_NAME"; return 1
}
switch_mirror() {
  require_debian || return 1
  hint '会先备份 /etc/apt 中被修改的文件，只替换 Debian 官方 / 常见镜像的 URI。'
  confirm '把系统 APT 源切换为清华源？' || return 1
  ensure_python || return 1
  ensure_download_tools || return 1
  root_source_helper switch /etc/apt /var/backups/coee-wsl-setup || return 1
  system_apt_update
}
restore_mirror() {
  local choice i
  local -a backups
  require_debian || return 1
  ensure_python || return 1
  mapfile -t backups < <(as_root find /var/backups/coee-wsl-setup -mindepth 1 -maxdepth 1 \
    -type d -name 'apt-*' 2>/dev/null | sort -r)
  ((${#backups[@]})) || { fail '尚无此脚本创建的源备份。'; return 1; }
  for i in "${!backups[@]}"; do
    printf '   %s%2d%s  %s\n' "$B" "$((i + 1))" "$C0" "${backups[$i]##*/}"
  done
  read -r -p "${YLW}?${C0} 选择要恢复的备份 ${D}[1-${#backups[@]}，回车取消]${C0} " choice || return 1
  [[ -n $choice ]] || return 1
  if [[ ! $choice =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#backups[@]})); then
    fail '无效的编号。'; return 1
  fi
  root_source_helper restore /etc/apt "${backups[$((choice - 1))]}" || return 1
  system_apt_update
}

# ---------- 状态 ----------
refresh_status() {
  local name
  for name in "${TOOLS[@]}"; do VER[$name]=$(tool_version "$name" || true); done
  docker_probe
}
tool_status_text() {
  local v=${VER[$1]:-}
  if [[ -n $v ]]; then printf '%s● %s%s' "$GRN" "$v" "$C0"
  else printf '%s○ 未安装%s' "$D" "$C0"; fi
}
header() {
  local init user
  [[ $(cat /proc/1/comm 2>/dev/null) == systemd ]] && init=systemd || init='无 systemd'
  user=$(id -un)
  printf '\n  %s%sWSL / Linux 开发环境初始化%s\n' "$B" "$CYN" "$C0"
  printf '  %s%s · %s · %s · %s%s%s\n' "$D" "$OS_NAME" "$(uname -m)" "$user" "$init" \
    "${WSL_DISTRO_NAME:+ · WSL: $WSL_DISTRO_NAME}" "$C0"
  rule
}
show_status() {
  local name
  refresh_status
  header
  for name in "${TOOLS[@]}"; do
    printf '  %-14s %s\n' "${TOOL_LABEL[$name]}" "$(tool_status_text "$name")"
  done
  printf '  %-14s %s\n' 'Docker' "$(docker_status_text)"
  printf '\n'
}
render_menu() {
  header
  printf '\n  %s开发工具%s\n' "$B" "$C0"
  printf '   %s1%s  %-16s %s\n' "$CYN" "$C0" 'Claude Code' "$(tool_status_text claude)"
  printf '   %s2%s  %-16s %s\n' "$CYN" "$C0" 'Codex' "$(tool_status_text codex)"
  printf '   %s3%s  %-16s %s\n' "$CYN" "$C0" 'CC Switch' "$(tool_status_text cc-switch)"
  printf '\n  %sDocker%s\n' "$B" "$C0"
  printf '   %s4%s  %-16s %s\n' "$CYN" "$C0" 'Docker' "$(docker_status_text)"
  printf '\n  %s系统%s\n' "$B" "$C0"
  if [[ $OS_ID == debian ]]; then
    printf '   %s5%s  APT 源切换为清华源 %s(先备份)%s\n' "$CYN" "$C0" "$D" "$C0"
    printf '   %s6%s  恢复 APT 源备份\n' "$CYN" "$C0"
  else
    printf '   %s5  APT 源切换为清华源  (仅 Debian)%s\n' "$D" "$C0"
    printf '   %s6  恢复 APT 源备份  (仅 Debian)%s\n' "$D" "$C0"
  fi
  if [[ -n $SUITE ]]; then
    printf '   %s7%s  安装原生 Docker %s(不推荐与 Docker Desktop 同时使用)%s\n' "$CYN" "$C0" "$D" "$C0"
  else
    printf '   %s7  安装原生 Docker  (仅 Debian 12 / 13)%s\n' "$D" "$C0"
  fi
  printf '\n   %sa%s  安装 / 更新全部     %su%s  只更新已安装的     %sr%s  刷新     %sq%s  退出\n' \
    "$CYN" "$C0" "$CYN" "$C0" "$CYN" "$C0" "$CYN" "$C0"
  rule
}

# ---------- 执行 ----------
run_action() {
  local action=$1
  step "${ACTION_LABEL[$action]}"
  case "$action" in
    claude) install_cli claude "$CLAUDE_URL" bash ;;
    codex) install_cli codex "$CODEX_URL" sh ;;
    cc-switch) install_cli cc-switch "$CC_SWITCH_URL" bash ;;
    docker) check_docker ;;
    docker-native) install_docker ;;
    mirror) switch_mirror ;;
    restore) restore_mirror ;;
  esac
}
# Runs actions in order and prints a summary; Docker in "all" is advisory only.
run_batch() {
  local action advisory=0 failed=0
  local -a lines=()
  for action in "$@"; do
    case $action in
      all) advisory=1; continue ;;
      update) continue ;;
    esac
    if run_action "$action"; then
      lines+=("${GRN}✔${C0} ${ACTION_LABEL[$action]}")
    elif [[ $action == docker && $advisory == 1 ]]; then
      lines+=("${YLW}!${C0} ${ACTION_LABEL[$action]} ${D}(未就绪，按上方提示在 Docker Desktop 中处理)${C0}")
    else
      lines+=("${RED}✘${C0} ${ACTION_LABEL[$action]}")
      failed=1
    fi
  done
  if ((${#lines[@]} == 0)); then
    warn '没有需要执行的操作（「只更新」只处理已安装的工具）。'
  elif ((${#lines[@]} > 1)); then
    printf '\n%s汇总%s\n' "$B" "$C0"
    printf '  %s\n' "${lines[@]}"
  fi
  printf '\n'
  return "$failed"
}
expand_actions() {
  # Maps menu keys / CLI flags to action names; "all" / "update" are markers for run_batch.
  local key name
  for key in "$@"; do
    case "$key" in
      1|claude) echo claude ;;
      2|codex) echo codex ;;
      3|cc-switch) echo cc-switch ;;
      4|docker) echo docker ;;
      5|mirror) echo mirror ;;
      6|restore) echo restore ;;
      7|docker-native) echo docker-native ;;
      a|A|all) printf '%s\n' all claude codex cc-switch docker ;;
      u|U|update)
        echo update
        for name in "${TOOLS[@]}"; do [[ -z $(tool_bin "$name") ]] || echo "$name"; done ;;
      *) return 1 ;;
    esac
  done
}
menu_loop() {
  local input key
  local -a keys actions
  refresh_status
  while true; do
    clear_screen
    render_menu
    read -r -p "  选择 ${D}(可多选，如 1 3)${C0} ${CYN}›${C0} " input || { printf '\n'; break; }
    read -r -a keys <<< "${input//,/ }"
    ((${#keys[@]})) || continue
    case "${keys[0]}" in
      q|Q|0|exit) break ;;
      r|R) refresh_status; continue ;;
    esac
    if ! expand_actions "${keys[@]}" >/dev/null; then
      warn "无法识别：$input"; sleep 1; continue
    fi
    mapfile -t actions < <(expand_actions "${keys[@]}")
    clear_screen
    run_batch "${actions[@]}" || true
    refresh_status
    pause
  done
}
usage() {
  cat <<EOF
用法：bash wsl-setup.sh [选项…] [--yes]

  不带参数进入交互菜单。可同时给出多个选项，按顺序执行。

  --all            一键安装 / 更新 Claude Code、Codex、CC Switch，并检查 Docker
  --update         只更新已经安装的工具（Claude Code 使用 claude update）
  --claude         安装 / 更新 Claude Code（官方原生安装器，装到 ~/.local/bin）
  --codex          安装 / 更新 Codex
  --cc-switch      安装 / 更新 CC Switch
  --docker         检查 Docker / Docker Desktop WSL 集成（不安装任何东西）
  --docker-native  安装原生 Docker（仅 Debian 12/13，不推荐与 Docker Desktop 同时使用）
  --mirror         系统 APT 源切换为清华源（仅 Debian，先备份）
  --restore        恢复 APT 源备份（仅 Debian）
  --status         查看安装状态
  --yes, -y        跳过确认提示

环境变量：
  CLAUDE_CHANNEL=stable|latest|<版本号>   指定 Claude Code 渠道（默认 latest）
  NO_COLOR=1                               关闭彩色输出

支持：Debian / Ubuntu / Fedora / RHEL 系 / openSUSE / Arch / Alpine（需先 apk add bash），x86_64 / aarch64。

说明：安装器从上游下载并执行；一键安装不会修改系统 APT 源；
      不配置登录、API 密钥或 Docker registry 镜像；不会删除项目、数据或已有 CLI 配置。
EOF
}
main() {
  local arg status=0
  local -a keys=() actions
  for arg in "$@"; do
    case "$arg" in
      --help|-h) usage; return 0 ;;
      --yes|-y) AUTO_YES=1 ;;
      --status) keys+=(status) ;;
      --all|--update|--claude|--codex|--cc-switch|--docker|--docker-native|--mirror|--restore) keys+=("${arg#--}") ;;
      *) usage >&2; return 2 ;;
    esac
  done
  if [[ -n $CLAUDE_CHANNEL && ! $CLAUDE_CHANNEL =~ ^(stable|latest|[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    fail "CLAUDE_CHANNEL 无效：$CLAUDE_CHANNEL"; return 2
  fi
  prepare_path
  detect_system || return 1
  trap cleanup EXIT
  trap 'printf "\n"; exit 130' INT
  trap 'exit 143' TERM
  if ((${#keys[@]} == 0)); then menu_loop; return 0; fi
  local -a rest=()
  for arg in "${keys[@]}"; do [[ $arg == status ]] || rest+=("$arg"); done
  if ((${#rest[@]} < ${#keys[@]})); then show_status; else header; fi
  ((${#rest[@]})) || return 0
  mapfile -t actions < <(expand_actions "${rest[@]}")
  run_batch "${actions[@]}" || status=1
  return "$status"
}

# Parsed as one compound command, so `curl ... | bash` never reads past this block.
if [[ ${BASH_SOURCE[0]:-$0} == "$0" ]]; then
  # Under curl | bash, stdin is the script itself: menus and installers must read the terminal.
  if [[ ! -t 0 ]] && { : </dev/tty; } 2>/dev/null; then
    main "$@" </dev/tty
  else
    main "$@"
  fi
  exit
fi
