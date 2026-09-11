#!/usr/bin/env bash
# 通用：把本地产物 rsync 到远端，可选执行远程命令与 HTTP 健康检查。
# 环境变量：
#   DEPLOY_HOST、DEPLOY_USER     必填
#   DEPLOY_PATH                 远端根目录，默认 /opt/app
#   PUBLISH_SRC                 要同步的本地路径，空格分隔；相对当前工作目录
#   PUBLISH_DEST                相对 DEPLOY_PATH 的远端子路径，与 PUBLISH_SRC 一一对应；
#                               未设则按源路径的 basename 放到 DEPLOY_PATH 下
#   SSH_PRIVATE_KEY             可选，PEM 私钥全文
#   REMOTE_AFTER                可选，SSH 上执行的命令（如 sudo -n systemctl restart myapp）
#   DEPLOY_HEALTH_URL           可选，curl 成功即视为发布成功
if [ -z "${BASH_VERSION:-}" ]; then
  echo "本脚本需要 bash" >&2
  exit 1
fi
set -euo pipefail

DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_USER="${DEPLOY_USER:-}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/app}"
PUBLISH_SRC="${PUBLISH_SRC:-}"
PUBLISH_DEST="${PUBLISH_DEST:-}"
REMOTE_AFTER="${REMOTE_AFTER:-}"
DEPLOY_HEALTH_URL="${DEPLOY_HEALTH_URL:-}"

if [[ -z "${DEPLOY_HOST}" || -z "${DEPLOY_USER}" ]]; then
  echo "请设置 DEPLOY_HOST 与 DEPLOY_USER" >&2
  exit 1
fi
if [[ -z "${PUBLISH_SRC}" ]]; then
  echo "请设置 PUBLISH_SRC（要 rsync 的本地文件或目录，空格分隔）" >&2
  exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
  echo "需要 rsync" >&2
  exit 1
fi
if ! command -v ssh >/dev/null 2>&1; then
  echo "需要 ssh" >&2
  exit 1
fi

key_file=""
cleanup() {
  if [[ -n "${key_file}" && -f "${key_file}" ]]; then
    rm -f "${key_file}"
  fi
}
trap cleanup EXIT

ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
if [[ -n "${SSH_PRIVATE_KEY:-}" ]]; then
  key_file="$(mktemp)"
  chmod 600 "${key_file}"
  printf '%s\n' "${SSH_PRIVATE_KEY}" >"${key_file}"
  ssh_opts+=(-o IdentitiesOnly=yes -i "${key_file}")
fi

ssh_cmd=(ssh "${ssh_opts[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}")
rsync_rsh="ssh ${ssh_opts[*]}"

# shellcheck disable=SC2206
src_items=(${PUBLISH_SRC})
dest_items=()
if [[ -n "${PUBLISH_DEST}" ]]; then
  # shellcheck disable=SC2206
  dest_items=(${PUBLISH_DEST})
  if [[ "${#src_items[@]}" -ne "${#dest_items[@]}" ]]; then
    echo "PUBLISH_DEST 项数须与 PUBLISH_SRC 相同" >&2
    exit 1
  fi
fi

"${ssh_cmd[@]}" "mkdir -p $(printf '%q' "${DEPLOY_PATH}")"

i=0
for src in "${src_items[@]}"; do
  if [[ ! -e "${src}" ]]; then
    echo "本地不存在: ${src}" >&2
    exit 1
  fi
  if [[ "${#dest_items[@]}" -gt 0 ]]; then
    rel="${dest_items[$i]}"
  else
    rel="$(basename "${src}")"
  fi
  remote="${DEPLOY_PATH}/${rel}"
  echo "rsync ${src} → ${DEPLOY_USER}@${DEPLOY_HOST}:${remote}"
  if [[ -d "${src}" ]]; then
    "${ssh_cmd[@]}" "mkdir -p $(printf '%q' "${remote}")"
    rsync -az --delete --checksum -e "${rsync_rsh}" "${src%/}/" "${DEPLOY_USER}@${DEPLOY_HOST}:${remote}/"
  else
    "${ssh_cmd[@]}" "mkdir -p $(printf '%q' "$(dirname "${remote}")")"
    rsync -az --checksum -e "${rsync_rsh}" "${src}" "${DEPLOY_USER}@${DEPLOY_HOST}:${remote}"
  fi
  i=$((i + 1))
done

if [[ -n "${REMOTE_AFTER}" ]]; then
  echo "远程执行: ${REMOTE_AFTER}"
  "${ssh_cmd[@]}" "${REMOTE_AFTER}"
fi

if [[ -z "${DEPLOY_HEALTH_URL}" ]]; then
  exit 0
fi

ok=0
for _ in 1 2 3 4 5 6; do
  if curl -fsS --max-time 10 "${DEPLOY_HEALTH_URL}" >/dev/null; then
    echo "健康检查成功 ${DEPLOY_HEALTH_URL}"
    ok=1
    break
  fi
  sleep 2
done
if [[ "${ok}" -ne 1 ]]; then
  echo "健康检查失败 ${DEPLOY_HEALTH_URL}" >&2
  exit 1
fi
