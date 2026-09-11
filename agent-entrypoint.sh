#!/bin/bash
# 通过 nsenter 进入 PID 1 的 mount/net/pid 命名空间，用宿主机上的 woodpecker-agent
# 调用宿主机已装的编译器与 rsync/ssh（glibc 与宿主机一致）。
set -euo pipefail

HOST_AGENT="${WOODPECKER_HOST_AGENT_BIN:-/usr/local/bin/woodpecker-agent}"
CACHE_ROOT="${WOODPECKER_CACHE_DIR:-/var/cache/woodpecker}"
GOMODCACHE="${GOMODCACHE:-${CACHE_ROOT}/go/mod}"
GOCACHE="${GOCACHE:-${CACHE_ROOT}/go/build}"
NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-${CACHE_ROOT}/npm}"
PNPM_STORE_DIR="${PNPM_STORE_DIR:-${CACHE_ROOT}/pnpm}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-${CACHE_ROOT}/xdg}"
# auto：go.mod 要求更高版本时只下一次工具链（进 GOMODCACHE）。
# local：只用宿主机已装的 go，不再下载 toolchain（本机版本须满足 go.mod）。
GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"

if [[ ! -e /proc/1/ns/mnt ]]; then
  echo "当前环境无法访问 /proc/1/ns，请确认 compose 已设 pid: host 与 privileged: true" >&2
  exit 1
fi

exec nsenter --target 1 --mount --uts --ipc --net --pid -- \
  env \
    WOODPECKER_SERVER="${WOODPECKER_SERVER:-127.0.0.1:9000}" \
    WOODPECKER_AGENT_SECRET="${WOODPECKER_AGENT_SECRET:?WOODPECKER_AGENT_SECRET 未设置}" \
    WOODPECKER_BACKEND=local \
    WOODPECKER_BACKEND_LOCAL_TEMP_DIR="${WOODPECKER_BACKEND_LOCAL_TEMP_DIR:-/var/tmp/woodpecker}" \
    GOPROXY="${GOPROXY:-https://goproxy.cn,direct}" \
    GOMODCACHE="${GOMODCACHE}" \
    GOCACHE="${GOCACHE}" \
    GOTOOLCHAIN="${GOTOOLCHAIN}" \
    NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE}" \
    npm_config_cache="${NPM_CONFIG_CACHE}" \
    PNPM_STORE_DIR="${PNPM_STORE_DIR}" \
    XDG_CACHE_HOME="${XDG_CACHE_HOME}" \
    CI=true \
    PATH="${HOST_PATH:-/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin}" \
    HOST_AGENT="${HOST_AGENT}" \
  sh -c '
    for d in "$GOMODCACHE" "$GOCACHE" "$npm_config_cache" "$PNPM_STORE_DIR" "$XDG_CACHE_HOME"; do
      mkdir -p "$d" 2>/dev/null && chmod 1777 "$d" 2>/dev/null
      if [ -d "$d" ]; then
        echo "cache ok: $d"
      else
        echo "cache 目录创建失败（宿主机不可写？）: $d" >&2
      fi
    done
    exec "$HOST_AGENT"
  '
