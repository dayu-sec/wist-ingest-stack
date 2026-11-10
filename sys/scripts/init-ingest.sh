#!/usr/bin/env bash
# 运行根 / 现场态备料（幂等；`flow localize` 的第 ③ 步 —— 在渲染之后、perms 之前）。
#
# 分工（与 `sys/workflows/operators.gxl` 顶部的 A/C 分类一致）：
#   A 类（10 件产品内容）由 `gx.tpl` **每次覆盖**，本脚本不再碰 ——
#     老做法（对所有种子 `copy_missing`）的症状是「栈升了、运行态还是旧配置」。
#   C 类由本脚本**只补缺**，绝不覆盖现场：
#     - `configs/ingest-ctrl/ingest-ctrl.toml` —— ctrl 自己的站点配置 + 网关台账，运维手改；
#     - `data-plane-run/work/connectors/source.d/90-ingest-tcp.toml`
#       `data-plane-run/work/topology/sources/wpsrc.toml`
#       —— 由 ctrl apply 按站点配置生成；这里只做「首次 up 之前」的引导内容，
#          不能覆盖站点已 apply 的结果（收数地址 / 证书路径会当场失效）。
#
# 为什么要先建目录：父挂载 ./data-plane-run/work:/data 生效后，子挂载点
# （/data/identity/ingest）只能落在宿主这份工作目录里；缺失时由 Docker 守护进程
# 以 **root** 创建，之后部署账号既 chown 不动也 chmod 不动，
# `gops sys perms --apply` 只会得到整片 Operation not permitted。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

WORK="${STACK_ROOT}/data-plane-run/work"
SEED="${STACK_ROOT}/sys/configs/ingest"
CTRL_SEED="${STACK_ROOT}/sys/configs/ingest-ctrl"
CTRL_DIR="${STACK_ROOT}/configs/ingest-ctrl"
IDENTITY="${STACK_ROOT}/identity"
GID="${INGEST_GID:-999}"

note() { echo "  $*"; }

# 1) 运行根 + 子挂载点（渲染目标目录已由 flow 的 ① 建过，这里兜底首次手工调用）
mkdir -p "${WORK}"/{conf,connectors,topology,models,data,identity}
mkdir -p "${WORK}/connectors/sink.d" "${WORK}/connectors/source.d"
mkdir -p "${WORK}/topology/sinks/business.d" "${WORK}/topology/sinks/infra.d" "${WORK}/topology/sources"
mkdir -p "${WORK}/models/oml/raw_log" "${WORK}/models/wpl"
mkdir -p "${WORK}/identity/ingest"
mkdir -p "${WORK}/.ctrl"
note "work root: ${WORK}"

# 2) C 类引导（只补缺）：ctrl 生成的那两件。A 类在 flow 里由 gx.tpl 覆盖，这里不碰。
fill_missing() { # <相对路径>
  local rel="$1"
  [ -f "${WORK}/${rel}" ] && return 0
  [ -f "${SEED}/${rel}" ] || {
    echo "  ⚠ 种子缺失：${SEED}/${rel}（C 类引导文件）" >&2
    return 0
  }
  mkdir -p "$(dirname "${WORK}/${rel}")"
  cp "${SEED}/${rel}" "${WORK}/${rel}"
  note "C 类引导：${rel}"
}
fill_missing "connectors/source.d/90-ingest-tcp.toml"
fill_missing "topology/sources/wpsrc.toml"

# 3) ctrl 站点配置：种子 -> 栈根 configs/ingest-ctrl/ingest-ctrl.toml（现场态）
#    只补缺，不覆盖现场改动（与上面的纪律一致）；`${SEC_*}` 留给 ctrl 运行时解析。
if [ -d "${CTRL_SEED}" ]; then
  mkdir -p "${CTRL_DIR}"
  cp -n "${CTRL_SEED}/ingest-ctrl.toml" "${CTRL_DIR}/ingest-ctrl.toml" 2>/dev/null || true
  chmod 0640 "${CTRL_DIR}/ingest-ctrl.toml" 2>/dev/null || true
  note "ctrl config: ${CTRL_DIR}/ingest-ctrl.toml"
fi

# 4) 站点身份：三棵目录（数据面 / ctrl 管理面 / web）
#    ingest/trust  -- 数据面服务端证书 + 网关客户端 CA
#    ctrl/tls      -- ctrl 服务端证书 + web 客户端 CA（mTLS）
#    web/tls       -- web 服务端证书 + 访问 ctrl 的客户端证书 + ctrl 信任锚
mkdir -p "${IDENTITY}/ingest/trust" "${IDENTITY}/ctrl/tls" "${IDENTITY}/web/tls"
note "identity dir: ${IDENTITY}"

# 5) 属组对齐（只 chgrp，不提权；属主保持部署账号）
chgrp -R "${GID}" "${WORK}" "${IDENTITY}" 2>/dev/null || {
  echo "  ⚠ chgrp ${GID} 失败：确认当前账号在 gid=${GID} 组里（见 README 的一次性前置）" >&2
}
chmod 2750 "${IDENTITY}" "${IDENTITY}/ingest" "${IDENTITY}/web" 2>/dev/null || true
chmod 0750 "${IDENTITY}/ctrl" 2>/dev/null || true
chmod 2750 "${IDENTITY}/ingest/trust" "${IDENTITY}/web/tls" "${IDENTITY}/ctrl/tls" 2>/dev/null || true
chmod -R u+rwX,g+rwX,o-rwx "${WORK}" 2>/dev/null || true
# 渲染产物按文件给读权限：ingest 容器是 999:999，属组已对齐。
find "${WORK}" -type f -name '*.toml' -exec chmod 0640 {} + 2>/dev/null || true

echo "init-ingest: done"
