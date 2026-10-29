#!/usr/bin/env bash
# 开发/联调用：生成本栈需要的三套身份（**不要用于生产**）。
#   identity/ingest/trust/  server.pem server.key client-ca.pem
#   identity/ctrl/tls/      ctrl.pem ctrl.key web-client-ca.pem
#   identity/web/tls/       web.pem web.key web-client.pem web-client.key ctrl-ca.pem
#
# 生产：由 Center（或离线 CA）签发同样的文件；本脚本只是把"文件长什么样"写死下来。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT="${STACK_ROOT}/identity"
GID="${INGEST_GID:-999}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

note() { echo "  $*"; }

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

note "generating CAs"
new_ca ca-ingest      # 数据面：校验网关客户端证书
new_ca ca-mgmt        # 管理面：ctrl 服务端 + web 客户端

note "data plane (gateways -> ingest)"
new_leaf ingest-server ca-ingest ingest-dev \
"basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1"

note "control plane (web -> ctrl)"
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
subjectAltName=DNS:localhost,IP:127.0.0.1"

mkdir -p "${OUT}/ingest/trust" "${OUT}/ctrl/tls" "${OUT}/web/tls"

install_pem "${TMP}/ingest-server.pem" "${OUT}/ingest/trust/server.pem" 0644
install_pem "${TMP}/ingest-server.key" "${OUT}/ingest/trust/server.key" 0640
install_pem "${TMP}/ca-ingest.pem"     "${OUT}/ingest/trust/client-ca.pem" 0644

install_pem "${TMP}/ctrl-server.pem" "${OUT}/ctrl/tls/ctrl.pem" 0644
install_pem "${TMP}/ctrl-server.key" "${OUT}/ctrl/tls/ctrl.key" 0640
install_pem "${TMP}/ca-mgmt.pem"     "${OUT}/ctrl/tls/web-client-ca.pem" 0644

install_pem "${TMP}/web-server.pem"  "${OUT}/web/tls/web.pem" 0644
install_pem "${TMP}/web-server.key"  "${OUT}/web/tls/web.key" 0640
install_pem "${TMP}/web-client.pem"  "${OUT}/web/tls/web-client.pem" 0644
install_pem "${TMP}/web-client.key"  "${OUT}/web/tls/web-client.key" 0640
install_pem "${TMP}/ca-mgmt.pem"     "${OUT}/web/tls/ctrl-ca.pem" 0644

note "done: ${OUT}"
echo "  ⚠ 这是开发证书（同一台机器自签），生产必须换成 Center/离线 CA 签发的身份"
