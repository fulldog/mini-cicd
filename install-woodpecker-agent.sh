#!/usr/bin/env bash
# 把官方 woodpecker-agent 装到宿主机，供 compose 里 nsenter 调用。
# 用法：sudo bash install-woodpecker-agent.sh
# 可选：WOODPECKER_AGENT_VERSION=v3.18.0 DEST=/usr/local/bin/woodpecker-agent
if [ -z "${BASH_VERSION:-}" ]; then
  echo "本脚本需要 bash" >&2
  exit 1
fi
set -euo pipefail

DEST="${DEST:-/usr/local/bin/woodpecker-agent}"
TMPDIR_WP="${WOODPECKER_BACKEND_LOCAL_TEMP_DIR:-/var/tmp/woodpecker}"
CACHE_ROOT="${WOODPECKER_CACHE_DIR:-/var/cache/woodpecker}"
VERSION="${WOODPECKER_AGENT_VERSION:-v3.18.0}"

arch="$(uname -m)"
case "${arch}" in
  x86_64 | amd64) goarch="amd64" ;;
  aarch64 | arm64) goarch="arm64" ;;
  *)
    echo "不支持的架构: ${arch}" >&2
    exit 1
    ;;
esac

url="https://github.com/woodpecker-ci/woodpecker/releases/download/${VERSION}/woodpecker-agent_linux_${goarch}.tar.gz"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

echo "下载 ${url}"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o "${workdir}/agent.tgz" "${url}"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "${workdir}/agent.tgz" "${url}"
else
  echo "需要 curl 或 wget" >&2
  exit 1
fi

tar -tzf "${workdir}/agent.tgz" >/dev/null
tar -xzf "${workdir}/agent.tgz" -C "${workdir}"
bin=""
if [[ -f "${workdir}/woodpecker-agent" ]]; then
  bin="${workdir}/woodpecker-agent"
else
  bin="$(find "${workdir}" -type f -name 'woodpecker-agent' | head -n 1 || true)"
fi
if [[ -z "${bin}" || ! -f "${bin}" ]]; then
  echo "压缩包里找不到 woodpecker-agent" >&2
  exit 1
fi

install -m 0755 "${bin}" "${DEST}"
mkdir -p "${TMPDIR_WP}" \
  "${CACHE_ROOT}/go/mod" \
  "${CACHE_ROOT}/go/build" \
  "${CACHE_ROOT}/npm" \
  "${CACHE_ROOT}/pnpm" \
  "${CACHE_ROOT}/xdg"
chmod 1777 "${TMPDIR_WP}" "${CACHE_ROOT}" \
  "${CACHE_ROOT}/go" "${CACHE_ROOT}/go/mod" "${CACHE_ROOT}/go/build" \
  "${CACHE_ROOT}/npm" "${CACHE_ROOT}/pnpm" "${CACHE_ROOT}/xdg" 2>/dev/null || true
echo "已安装 ${DEST}（${VERSION} linux/${goarch}）"
echo "工作目录 ${TMPDIR_WP}"
echo "缓存目录 ${CACHE_ROOT}"
"${DEST}" --help >/dev/null 2>&1 || "${DEST}" --version || true
