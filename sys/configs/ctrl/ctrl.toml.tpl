# wist-ingest-ctrl 站点配置**模板**
#
# 由 `scripts/init-ingest.sh` 渲染到**栈根** `configs/ctrl/ctrl.toml`：
#   - 渲染只替换 `${INGEST_ROOT}`（栈的绝对路径）；其余变量原样保留；
#   - `configs/` 是现场态：不入库、不进交付包、升级不覆盖（见 sys-prj.yml）。
#
# 秘密不进这个文件：`${SEC_INGEST_CTRL_ADMIN_TOKEN}` 由 ctrl 启动时从
# `INGEST_CTRL_SEC_FILE`（= 栈根 `.wist/sec-value.yml`，0640）解析，
# 键名 `ingest_ctrl_admin_token` → `SEC_INGEST_CTRL_ADMIN_TOKEN`（与 center/gateway 同口径）。
# 未解析会**拒绝启动**，不会把占位符当字面 token 用。

[ctrl]
listen = "127.0.0.1:19091"

# 数据面运行根（= 容器内 /data 的宿主侧目录），必须与 compose 的挂载一致。
work_root = "${INGEST_ROOT}/data-plane-run/work"
# compose 把 identity/ingest/trust 挂到 /data/identity/ingest，所以这里指到 trust/。
identity_dir = "${INGEST_ROOT}/identity/ingest/trust"
# 要管理的容器名（docker restart / docker exec 用）。
container = "wist-ingest-stack-ingest"
container_workdir = "/data"

# 管理面鉴权（对齐 center：Bearer token + sha256 hash）。
# 真值在 `.wist/sec-value.yml`；这里的 `${SEC_*}` 由 ctrl 解析。
[ctrl.auth]
admin_token = "${SEC_INGEST_CTRL_ADMIN_TOKEN}"
# viewer_token = "${SEC_INGEST_CTRL_VIEWER_TOKEN}"   # 可选：只读 token
allow_anonymous = false

# 管理面 TLS/mTLS：与 gwlinkd↔Center 同构 —— ctrl 当服务端，web 当客户端。
[ctrl.tls]
cert_file = "${INGEST_ROOT}/identity/ctrl/tls/ctrl.pem"
key_file = "${INGEST_ROOT}/identity/ctrl/tls/ctrl.key"
client_ca_file = "${INGEST_ROOT}/identity/ctrl/tls/web-client-ca.pem"
allow_unauthenticated = false

[ingest]
bind = "0.0.0.0"
port = 6514
# 强制 len 帧；line 会在多行日志上错帧。
framing = "len"

# 以下路径是**容器内**路径（与 ctrl 无关，只写进 wparse 配置）。
server_cert = "/data/identity/ingest/server.pem"
server_key = "/data/identity/ingest/server.key"
# 必填：不填 client_ca，wparse 的 tcp source 不会要求客户端证书（静默降级为单向 TLS）。
client_ca = "/data/identity/ingest/client-ca.pem"

# 网关台账（单端口模式下只用于审计/展示）。
[[gateways]]
name = "site-a"
tenant = "tenant-a"
