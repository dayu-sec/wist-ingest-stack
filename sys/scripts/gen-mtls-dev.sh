#!/usr/bin/env bash
# 开发/联调用：生成本栈需要的三套身份（**不要用于生产**）。
#   identity/ingest/trust/  server.pem server.key client-ca.pem
#   identity/ctrl/tls/      ctrl.pem ctrl.key web-client-ca.pem
#   identity/web/tls/       web.pem web.key web-client.pem web-client.key ctrl-ca.pem
#
# 生产：由 Center（或离线 CA）签发同样的文件；本脚本只是把"文件长什么样"写死下来。
#
# 用法：
#   bash sys/scripts/gen-mtls-dev.sh                    # 全部重生成（默认）
#   WEB_DOMAIN=ingest-web.dev.wist.lab \
#     bash sys/scripts/gen-mtls-dev.sh --scope mgmt     # 只换管理面（ctrl + web）
#
# 为什么要 `--scope`：
#   - `data`（ca-ingest）一换，**所有已接入网关的客户端证书全部失效**，每台都要重新签发接入券；
#   - `mgmt`（ca-mgmt）只牵动 ctrl ↔ web 这一对，两者一起重启即可，完全不碰网关。
#   所以「换 web 域名 / 换管理面证书」只跑 `--scope mgmt`；首次部署或整体轮换才用默认 all。
#
# 换完重启消费方（内容变了但进程要重读）：
#   docker restart wist-ingest-stack-ctrl wist-ingest-stack-web
# 数据面也被换过时才需要：docker restart wist-ingest-stack-ingest
#
# WEB_DOMAIN：web 服务端证书（浏览器侧）的额外 SAN。不设时只有 localhost / 127.0.0.1，
#   用域名访问会报「证书名字不符」。取值与 `sys/setting/vars.yml` 的 WEB_DOMAIN 一致。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT="${STACK_ROOT}/identity"
GID="${INGEST_GID:-999}"
WEB_DOMAIN="${WEB_DOMAIN:-}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

note() { echo "  $*"; }

SCOPE=all
while [ "$#" -gt 0 ]; do
  case "$1" in
    --scope) SCOPE="${2:?--scope 需要 data|mgmt|all}"; shift 2 ;;
    --scope=*) SCOPE="${1#*=}"; shift ;;
    -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "未知参数：$1（可用：--scope data|mgmt|all）" >&2; exit 2 ;;
  esac
done
case "${SCOPE}" in
  data|mgmt|all) ;;
  *) echo "非法的 --scope：${SCOPE}（只能是 data|mgmt|all）" >&2; exit 2 ;;
esac

# web 服务端证书的 SAN：localhost / 127.0.0.1 永远保留（回环联调），域名按需追加。
WEB_SAN="DNS:localhost,IP:127.0.0.1"
case "${WEB_DOMAIN}" in
  ""|localhost) ;;
  *[[:space:]]*) echo "WEB_DOMAIN 不能含空白：'${WEB_DOMAIN}'" >&2; exit 2 ;;
  *) WEB_SAN="${WEB_SAN},DNS:${WEB_DOMAIN}" ;;
esac

new_ca() {
  local name="$1"
  openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -sha256 \
    -subj "/CN=${name}" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout "${TMP}/${name}.key" -out "${TMP}/${name}.pem" >/dev/null 2>&1
}

new_leaf() {
  local name="$1" ca="$2" cn="$3" ext="$4"
  openssl req -newkey rsa:2048 -nodes -subj "/CN=${cn}" \
    -keyout "${TMP}/${name}.key" -out "${TMP}/${name}.csr" >/dev/null 2>&1
  printf '%s\n' "${ext}" > "${TMP}/${name}.ext"
  openssl x509 -req -in "${TMP}/${name}.csr" -CA "${TMP}/${ca}.pem" -CAkey "${TMP}/${ca}.key" \
    -CAcreateserial -days 365 -sha256 -extfile "${TMP}/${name}.ext" \
    -out "${TMP}/${name}.pem" >/dev/null 2>&1
}

install_pem() { # src dst mode
  install -m "$3" "$1" "$2"
  chgrp "${GID}" "$2" 2>/dev/null || true
}

mkdir -p "${OUT}/ingest/trust" "${OUT}/ctrl/tls" "${OUT}/web/tls"

if [ "${SCOPE}" = data ] || [ "${SCOPE}" = all ]; then
  note "data plane (gateways -> ingest)  [ca-ingest]"
  new_ca ca-ingest      # 数据面：校验网关客户端证书
  new_leaf ingest-server ca-ingest ingest-dev \
  "basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1"

  install_pem "${TMP}/ingest-server.pem" "${OUT}/ingest/trust/server.pem" 0644
  install_pem "${TMP}/ingest-server.key" "${OUT}/ingest/trust/server.key" 0640
  install_pem "${TMP}/ca-ingest.pem"     "${OUT}/ingest/trust/client-ca.pem" 0644
  note "  ⚠ 网关侧已签发的客户端证书全部失效，需重新签发接入券"
fi

if [ "${SCOPE}" = mgmt ] || [ "${SCOPE}" = all ]; then
  note "control plane (web -> ctrl) + 浏览器入口  [ca-mgmt, web SAN: ${WEB_SAN}]"
  new_ca ca-mgmt        # 管理面：ctrl 服务端 + web 客户端
  new_leaf ctrl-server ca-mgmt ingest-ctrl \
  "basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:ingest-ctrl,IP:127.0.0.1"

  new_leaf web-client ca-mgmt web \
  "basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=clientAuth
subjectAltName=URI:wist://gateway/web"

  new_leaf web-server ca-mgmt localhost \
  "basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=${WEB_SAN}"

  install_pem "${TMP}/ctrl-server.pem" "${OUT}/ctrl/tls/ctrl.pem" 0644
  install_pem "${TMP}/ctrl-server.key" "${OUT}/ctrl/tls/ctrl.key" 0640
  install_pem "${TMP}/ca-mgmt.pem"     "${OUT}/ctrl/tls/web-client-ca.pem" 0644

  install_pem "${TMP}/web-server.pem"  "${OUT}/web/tls/web.pem" 0644
  install_pem "${TMP}/web-server.key"  "${OUT}/web/tls/web.key" 0640
  install_pem "${TMP}/web-client.pem"  "${OUT}/web/tls/web-client.pem" 0644
  install_pem "${TMP}/web-client.key"  "${OUT}/web/tls/web-client.key" 0640
  install_pem "${TMP}/ca-mgmt.pem"     "${OUT}/web/tls/ctrl-ca.pem" 0644
fi

note "done: ${OUT} (scope=${SCOPE})"
echo "  ⚠ 这是开发证书（同一台机器自签），生产必须换成 Center/离线 CA 签发的身份"
echo "  ↻ 重启消费方：docker restart wist-ingest-stack-ctrl wist-ingest-stack-web"
if [ "${SCOPE}" = data ] || [ "${SCOPE}" = all ]; then
  echo "  ↻ 数据面也被换了：docker restart wist-ingest-stack-ingest"
fi
