# wist-ingest-stack

网关数据面的接收侧栈：**数据面 = 上游 warp-parse**（`tcp` source + mTLS），控制面与管理台独立发版。

| 组件 | 来源 | 跑在哪 |
|---|---|---|
| `ingest` | `ghcr.io/wp-labs/warp-parse:${WPARSE_TAG}`（上游镜像，本仓**不构建**） | compose |
| `web` | `wist-ingest-web` 镜像 | compose |
| `ctrl` | `wist-ingest-ctrl` 二进制 | **宿主 systemd**（要重启 ingest 容器，不能把 docker socket 塞进业务容器） |

## 目录

```text
sys/
  sys_model.yml          kind: docker-compose
  docker-compose.yml     ingest + ctrl + web
  setting/vars.yml       产品默认变量
  configs/ingest-ctrl/ingest-ctrl.toml  ctrl 站点配置（容器内路径 + ${SEC_*} 占位）
  scripts/init-ingest.sh 备料：运行根 + 种子 + 复制 ctrl 配置
values/value.yml         现场覆盖
identity/ingest/         站点身份（server cert/key + client CA）—— 站点态，不进包
configs/ingest-ctrl/     ctrl 渲染后的站点配置（现场态，不入库、不进包）
data-plane-run/work/     容器 /data 的宿主侧工作根 —— 站点态
.wist/sec-value.yml      密钥（`ingest_ctrl_admin_token` → `${SEC_INGEST_CTRL_ADMIN_TOKEN}`，0640）
```

## 首次部署（Linux）

```bash
# 0) 一次性宿主前置：部署账号需在容器 gid 组里（默认 999）
#    sudo usermod -aG 999 <账号>   # 之后重新登录

# 1) 变量落地
cp .env.example .env            # 或 gops sys localize
gops sys update                 # 生成 sys/merged_vars.yml（需提交）
gops sys localize

# 2) 预建运行根（必须在 up 之前，且以部署账号执行）
bash sys/scripts/init-ingest.sh

# 3) 放站点身份（三棵目录）
#    开发：
#      bash sys/scripts/gen-mtls-dev.sh
#    生产：由 Center / 离线 CA 签发同名文件
#      identity/ingest/trust/  server.pem server.key client-ca.pem      数据面（网关 → ingest）
#      identity/ctrl/tls/      ctrl.pem ctrl.key web-client-ca.pem      管理面（ctrl 服务端）
#      identity/web/tls/       web.pem web.key web-client.pem web-client.key ctrl-ca.pem
#    私钥一律 0640、属组 999。
gops sys perms --check
gops sys perms --apply

# 4) 起三个容器：数据面 + 控制面（ctrl）+ 管理台
#    ctrl 与 wist-center 同构：也是一个容器（挂 docker.sock 管理 ingest），宿主只暴露 127.0.0.1:19091。
gops run start

# 5) 登录管理台
#    admin token 在密钥文件里（配置里只有 ${SEC_INGEST_CTRL_ADMIN_TOKEN} 占位）：
gops sec get ingest_ctrl_admin_token      # 复制输出的值
#    浏览器打开 https://127.0.0.1:18080 （自签证书告警点继续），粘进去即可。
#    // 想看只读账号：往 .wist/sec-value.yml 加 ingest_ctrl_viewer_token，
#    // 并取消 configs/ingest-ctrl/ingest-ctrl.toml 里 viewer_token 那行注释，重启 ctrl 容器。

# 6) 改站点配置时（网关台账 / 端口等）：改 configs/ingest-ctrl/ingest-ctrl.toml 后重启 ctrl；
#    ctrl 的 apply 会渲染数据面配置 → wproj check → 重启 ingest（失败自动回滚）。
#    docker restart wist-ingest-stack-ctrl
#    # 或在页面点「应用配置并重启」
```

## 安全要点（都写进配置里了，改之前先读）

1. **`tls.ca` 必填**：`tcp` source 不填 `ca` 时**不会要求客户端证书**，mTLS 会静默降级成单向 TLS。ctrl 的 lint 把这条做成硬错误（`E001`）。
2. **`framing = "len"`**：`line` 帧会把 payload 里的裸换行当记录边界，多行日志必然错帧。
3. **私钥只走文件挂载**，`0640` + 属组 999；不要用 `${SEC_xxx}`（会出现在 `docker inspect`）。
4. **ctrl 不持有 CA 私钥**：它只渲染配置、校验、重启。
5. **管理面双向认证**（与 gwlinkd↔Center 同构）：ctrl 当服务端（`identity/ctrl/tls`），web 容器当客户端（`identity/web/tls/web-client.*`），nginx 用 `proxy_ssl_*` 出示证书并校验 ctrl。
6. **`identity/` 进 `contract`**：换一份等于所有网关换信任锚。该归档含私钥，落点必须离机/加密。
7. **管理面鉴权对齐 center**：Bearer token + sha256 hash；`admin` 可下发/重启，`viewer` 只读。未配 token 且未显式 `allow_anonymous` → ctrl 拒绝启动。
8. 轮换：`ca` 支持多张 PEM，走「先加新根 → 换叶 → 下旧根」；换完必须触发重连（`apply` 默认重启）。

## 已知边界

- 上游 `tcp` source 不把 peer cert 的 CN/序列号写进 `Tags`，所以**单端口模式下无法按证书做租户归属**；多租户隔离需要上游补丁或每租户独立 listener。
- `sys/configs/ingest/models/` 里的 `raw_log.wpl` 是 `skip_parse = true` 时的原文旁路占位；接入真实 WPL/OML 后替换。
- `wproj check` 版本差异：老版本会去 `models/sources/` 找 `wpsrc.toml` 并报错（wist-gateway-stack 同样报），以部署镜像里的 `wproj` 为准。

## 发布

- `version.txt` 是唯一版本权威；改动组件 tag 后 `gops sys update`，一并提交 `sys/merged_vars.yml`。
- `WPARSE_TAG` 是**非 `wist*` 镜像**，进 TCR 前必须 `./dev/push-images.sh --dry-run` 再实推。
