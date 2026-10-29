#!/usr/bin/env bash
# 数据面运行根备料（幂等；在 `gops run start` 之前、以部署账号执行）。
#
# 为什么需要它：父挂载 ./data-plane-run/work:/data 生效后，子挂载点
# （/data/identity/ingest）只能落在宿主这份工作目录里；缺失时由 Docker 守护进程
# 以 **root** 创建，之后部署账号既 chown 不动也 chmod 不动，
# `gops sys perms --apply` 只会得到整片 Operation not permitted。
# 本脚本提前以部署账号建好，Docker 看到已存在就不会再创建。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

WORK="${STACK_ROOT}/data-plane-run/work"
SEED="${STACK_ROOT}/sys/configs/ingest"
IDENTITY="${STACK_ROOT}/identity"
GID="${INGEST_GID:-999}"

note() { echo "  $*"; }

# 1) 运行根 + 子挂载点
mkdir -p "${WORK}"/{conf,connectors,topology,models,data,identity}
mkdir -p "${WORK}/identity/ingest"
mkdir -p "${WORK}/.ctrl"
note "work root: ${WORK}"

# 2) 种子：只补缺，不覆盖现场改动
copy_missing() {
  local src="$1" dst="$2"
  [ -d "${src}" ] || return 0
  (cd "${src}" && find . -type d -print0 | while IFS= read -r -d '' d; do
    mkdir -p "${dst}/${d}"
  done
  find . -type f -print0 | while IFS= read -r -d '' f; do
    if [ ! -e "${dst}/${f}" ]; then
      cp "${src}/${f}" "${dst}/${f}"
    fi
  done)
}
copy_missing "${SEED}/conf" "${WORK}/conf"
copy_missing "${SEED}/connectors" "${WORK}/connectors"
copy_missing "${SEED}/topology" "${WORK}/topology"
copy_missing "${SEED}/models" "${WORK}/models"
note "seed copied (existing files kept)"

# 3) 站点身份：三棵目录（数据面 / ctrl 管理面 / web）
#    ingest/trust  -- 数据面服务端证书 + 网关客户端 CA
#    ctrl/tls      -- ctrl 服务端证书 + web 客户端 CA（mTLS）
#    web/tls       -- web 服务端证书 + 访问 ctrl 的客户端证书 + ctrl 信任锚
mkdir -p "${IDENTITY}/ingest/trust" "${IDENTITY}/ctrl/tls" "${IDENTITY}/web/tls"
note "identity dir: ${IDENTITY}"

# 4) 属组对齐（只 chgrp，不提权；属主保持部署账号）
chgrp -R "${GID}" "${WORK}" "${IDENTITY}" 2>/dev/null || {
  echo "  ⚠ chgrp ${GID} 失败：确认当前账号在 gid=${GID} 组里（见 README 的一次性前置）" >&2
}
chmod 2750 "${IDENTITY}" "${IDENTITY}/ingest" "${IDENTITY}/web" 2>/dev/null || true
chmod 0750 "${IDENTITY}/ctrl" 2>/dev/null || true
chmod 2750 "${IDENTITY}/ingest/trust" "${IDENTITY}/web/tls" "${IDENTITY}/ctrl/tls" 2>/dev/null || true
chmod -R u+rwX,g+rwX,o-rwx "${WORK}" 2>/dev/null || true

echo "init-ingest: done"
