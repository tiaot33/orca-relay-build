#!/usr/bin/env bash
set -euo pipefail

# 用法:
#   sudo bash install-or-update.sh
# 可选环境变量:
#   GITHUB_PROXY="https://ghfast.top/"   # 国内网络下载 Release 加速前缀（注意末尾带 /）
#   REPO="tiaot33/orca-relay-build"
#   INSTALL_ROOT="/opt/orca-relay"
#   HEALTH_URL="http://127.0.0.1:8080/health"

REPO="${REPO:-tiaot33/orca-relay-build}"
GITHUB_PROXY="${GITHUB_PROXY:-}"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/orca-relay}"
SERVICE_NAME="${SERVICE_NAME:-orca-relay}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8080/health}"

if [ -n "${GITHUB_PROXY}" ] && [[ "${GITHUB_PROXY}" != */ ]]; then
  GITHUB_PROXY="${GITHUB_PROXY}/"
fi

API_URL="https://api.github.com/repos/${REPO}/releases/latest"
LATEST_TAG="$(curl -fsSL "${API_URL}" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>process.stdout.write(JSON.parse(d).tag_name||""))')"

if [ -z "${LATEST_TAG}" ]; then
  echo "[orca-relay] 无法获取最新 Release 版本号" >&2
  exit 1
fi

CURRENT_TAG=""
if [ -f "${INSTALL_ROOT}/current/BUILD_INFO.json" ]; then
  CURRENT_TAG="$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).releaseTag' "${INSTALL_ROOT}/current/BUILD_INFO.json" 2>/dev/null || true)"
fi

if [ "${CURRENT_TAG}" = "${LATEST_TAG}" ]; then
  echo "[orca-relay] 当前已是最新版本 (${LATEST_TAG})，无需更新。"
  exit 0
fi

echo "[orca-relay] 发现新版本: ${CURRENT_TAG:-未安装} -> ${LATEST_TAG}"

BASE_DL="${GITHUB_PROXY}https://github.com/${REPO}/releases/download/${LATEST_TAG}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

curl -fL --retry 3 -o "${TMP_DIR}/orca-relay-bundle.tar.gz" "${BASE_DL}/orca-relay-bundle.tar.gz"
curl -fL --retry 3 -o "${TMP_DIR}/orca-relay-bundle.tar.gz.sha256" "${BASE_DL}/orca-relay-bundle.tar.gz.sha256"

(
  cd "${TMP_DIR}"
  sha256sum -c orca-relay-bundle.tar.gz.sha256
)

TARGET_DIR="${INSTALL_ROOT}/releases/${LATEST_TAG}"
rm -rf "${TARGET_DIR}"
mkdir -p "${TARGET_DIR}"
tar -xzf "${TMP_DIR}/orca-relay-bundle.tar.gz" -C "${TARGET_DIR}"

if id -u orca-relay >/dev/null 2>&1; then
  chown -R orca-relay:orca-relay "${INSTALL_ROOT}/releases/${LATEST_TAG}"
fi

PREV_LINK="$(readlink -f "${INSTALL_ROOT}/current" 2>/dev/null || true)"
ln -sfn "${TARGET_DIR}" "${INSTALL_ROOT}/current"

if systemctl is-enabled "${SERVICE_NAME}" >/dev/null 2>&1; then
  echo "[orca-relay] 重启 systemd 服务 ${SERVICE_NAME}..."
  systemctl restart "${SERVICE_NAME}"

  HEALTH_OK=0
  for _ in $(seq 1 20); do
    if curl -fsS "${HEALTH_URL}" >/dev/null 2>&1; then
      HEALTH_OK=1
      break
    fi
    sleep 0.5
  done

  if [ "${HEALTH_OK}" -ne 1 ]; then
    echo "[orca-relay] 健康检查失败，自动回滚到上一版本！" >&2
    if [ -n "${PREV_LINK}" ] && [ -d "${PREV_LINK}" ]; then
      ln -sfn "${PREV_LINK}" "${INSTALL_ROOT}/current"
      systemctl restart "${SERVICE_NAME}" || true
    fi
    exit 1
  fi
fi

# 仅保留最近 3 个版本，释放磁盘空间
if [ -d "${INSTALL_ROOT}/releases" ]; then
  ls -1dt "${INSTALL_ROOT}/releases/"* 2>/dev/null | tail -n +4 | xargs -r rm -rf
fi

echo "[orca-relay] 已成功更新并切换至 ${LATEST_TAG}"
