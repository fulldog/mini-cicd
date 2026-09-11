#!/bin/bash
# 通过 nsenter 进入 PID 1 的 mount/net/pid 命名空间，用宿主机上的 woodpecker-agent
# 调用宿主机已装的编译器与 rsync/ssh（glibc 与宿主机一致）。
set -euo pipefail

HOST_AGENT="${WOODPECKER_HOST_AGENT_BIN:-/usr/local/bin/woodpecker-agent}"

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
    CI=true \
    PATH="${HOST_PATH:-/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin}" \
  "${HOST_AGENT}"
