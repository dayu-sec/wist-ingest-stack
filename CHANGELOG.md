# Changelog

## [0.3.1] - 2026-11-11

### 变更（补 `_gal` + `flow localize`：配置开始跟着版本走）

- **`_gal/` + `sys/workflows/operators.gxl`**：`gops sys localize` 现在会跑 `gx run localize`
  （之前对 `kind: docker-compose` 是**静默跳过**，所以栈升级后 `data-plane-run/work/` 永远是旧的）。
  流程：⓿ 前置门禁 → ① 建渲染目标目录 → ② A 类 10 件 `gx.tpl` → ③ `init-ingest.sh`（C 类引导）
  → ④ `gops sys perms --apply` → ⑤ 门禁。
- **13 个种子分两类**：A 类 10 件（产品内容，每次覆盖 `data-plane-run/work/**`）；
  C 类 3 件（`ingest-ctrl.toml` + ctrl 生成的 `90-ingest-tcp.toml` / `wpsrc.toml`，只补缺、不进 tpl）。
- 新增 `sys/scripts/check-stack.sh`（`--gate` / `--only prereq`）：前置能力、A/C 在位、
  无 handlebars 残留、变量与 `.env.example` 一致性。
- **部署值改为环境变量优先**（需要 ctrl ≥ 0.3.1）：`INGEST_BIND_IP` / `INGEST_PORT` /
  `INGEST_ADVERTISE_HOST` / `CRED_BIND_IP` / `CRED_PORT` 由 compose 注入，
  `configs/ingest-ctrl/ingest-ctrl.toml` 里那几行降为回落默认值。
- `.gitignore` 增 `.report` / `.run*`（gx 运行产物）。

### 升级注意

- 需要 **wist-ingest-ctrl ≥ 0.3.1**（环境变量优先那一版）。
- **A 类文件每次 localize 覆盖**：以后改 `data-plane-run/work/{conf,connectors,topology,models}`
  会被下一轮 localize 冲掉——要改请改 `sys/configs/ingest/**` 再 `gops sys localize`。
- 端口 / 入口改 `values/` 或 `sys/setting/vars.yml`，不要再改 ctrl 配置文件里的 `[ingest]` / `advertise`。
- 首次部署不装 `gx` 会在 `prj upgrade` 的 regenerate 阶段当場失败并回滚（手工 localize 则是静默跳过）。

## [0.3.0] - 2026-11-11

### 新增（管理台域名入口 + 访问凭据接入 cred）

- **管理台域名**：新增 `WEB_DOMAIN`（web 服务端证书 SAN 里的那个名字），访问地址变成
  `https://<WEB_DOMAIN>:<WEB_PORT>/`。`WEB_BIND_IP` 产品默认仍是回环，要按域名/网卡访问在
  `values` 里放开。`sys/scripts/gen-mtls-dev.sh` 支持 `WEB_DOMAIN` 与 `--scope data|mgmt|all`：
  只换管理面时**不动**数据面 `ca-ingest`，已接入网关的客户端证书继续有效。
- **访问凭据（wist-cred 验证方）**：ctrl 侧新增独立的 mTLS 收数 listener
  `CRED_BIND_IP:CRED_PORT`（默认 `127.0.0.1:19092`）。材料落 `identity/ctrl/cred/`，
  走已有的 `./identity:/identity:ro` 挂载，**不需要新增挂载点**；`sys/configs/ingest-ctrl/`
  里带一段注释态的 `[ctrl.credentials]`。
- `INGEST_CTRL_IMAGE`：本机镜像覆盖（开发态）。本地构建的镜像用普通名字，
  不要伪造成 `ghcr.io/...` —— 那种 tag 一 `pull` 就是 `not found`。
- `.env.example` 补齐 `WEB_DOMAIN` / `CRED_*` / `INGEST_CTRL_IMAGE`（CI 的 compose 渲染就用这份）。

### 升级注意

- 需要 **wist-ingest-ctrl ≥ 0.3.0**（旧版不认识 `[ctrl.credentials]`，也不认 `wcr_…` 令牌）。
- `WEB_DOMAIN` 只决定证书 SAN：换域名要重签
  `WEB_DOMAIN=<域名> bash sys/scripts/gen-mtls-dev.sh --scope mgmt`，再重启 ctrl + web。
- 接 cred 剩下的活在 cred 侧：把 ingest 登记成验证方（audience = `wist-ingest`，收数地址指向
  ctrl 的 19092 端口），跑接入命令把 `cred.toml` + 证书落到 `identity/ctrl/cred/`，
  再把配置里那段取消注释——否则 ctrl 不会去监听收数端口。

## [0.2.0] - 2026-10-30

### 新增（对齐 wist-center 的控制面 link / gateway 的数据面配置页）

- **数据面接入授权**：管理台「网关接入」页逐网关签发一次性接入券（短 TTL、落盘只存 sha256、
  明文只交付一次），网关用 `/api/v1/link/redeem` 登记客户端证书指纹；支持撤销；
  与 center 的「连接 Gateway」是同一套逻辑，方向是数据面（gateway → ingest）。
- **wparse 配置与规则**：管理台「配置与规则」页只读浏览数据面工作根
  （`conf/` `connectors/` `topology/` `models/` + `wparse.local.toml`），口径与 gateway 一致。
- **管理台风格对齐 wist-center**：设计令牌、侧边栏 + 状态条、卡片/徽标/代码块、明暗主题、
  IBM Plex 本地字体；新增「身份与状态」页。
- 站点配置模板新增 `[ctrl.link]`（`ttl_seconds` / `advertise`）；旧版 ctrl 会忽略这一段。

### 升级注意

- 需要 **wist-ingest-ctrl ≥ 0.2.0** 与 **wist-ingest-web ≥ 0.2.0**；只升一边会出现
  「授权页 404 / 页面读不到新接口」。
- 现场已有的 `configs/ingest-ctrl/ingest-ctrl.toml` **不会**被 `init-ingest.sh` 覆盖：
  升级后手工补 `[ctrl.link] advertise = "<网关能连到的 host:port>"`，否则交付的入口是
  `0.0.0.0:6514`（管理台会提示）。

## [0.1.3] - 2026-10-29

### 变更（控制面也进容器，对齐 wist-center-stack）

- `wist-ingest-ctrl` 从“宿主 systemd”改成 compose 里的 **`ctrl` 服务**（镜像 `INGEST_CTRL_TAG`）：
  挂 `docker.sock` 管理数据面容器、挂 `configs/ingest-ctrl`（配置）/`.wist`（密钥）/
  `data-plane-run/work`（渲染目标）/`identity`（证书检查），宿主只映射 `127.0.0.1:19091`。
- `web` 的 `/api` 上游从 `host.docker.internal:19091` 改为 **`ctrl:19091`**（同 compose 网络），
  不再 `extra_hosts`；`INGEST_WEB_TAG` 升 `v0.1.2`。
- 配置改名 + 改成容器内路径：`sys/configs/ingest-ctrl/ingest-ctrl.toml`（原 `sys/configs/ctrl/ctrl.toml`）。
- 新增变量 `INGEST_CTRL_TAG`（默认 `v0.1.3`）。

## [0.1.2] - 2026-10-29

### 变更（配置与密钥的落地位置，对齐 wist-center-stack）

- **配置不再放 `/etc`**：`sys/configs/ctrl/ctrl.toml.tpl` 由 `scripts/init-ingest.sh`
  渲染到栈根 `configs/ctrl/ctrl.toml`（现场态：不入库、不进包、升级不覆盖）。
  模板里只有 `${INGEST_ROOT}` 会被替换，其余变量原样保留。
- **admin token 进密钥文件**（center / gateway 同口径）：`.wist/sec-value.yml` 的
  `ingest_ctrl_admin_token`，配置里只写 `${SEC_INGEST_CTRL_ADMIN_TOKEN}`，
  ctrl 启动时经 `INGEST_CTRL_SEC_FILE` 解析 —— **配置落盘不含秘密**。
  密钥文件从 `sec_value.yml` 改名为 `sec-value.yml`（与 center-stack 一致）。
- `sys-prj.yml`：`configs/` 进 `pkg_exclude` / `protect` / `backup`；`.wist/` 补进 `backup`
  （配置里只有占位符，丢了密钥文件就等于把 token 换了一份）。
- `.gitignore` 加 `/configs/`。

### 修复（首次实机启动）

- `ingest` 的 `command` 从 `["work"]` 改成 `["daemon"]`：`warp-parse:0.35.3-alpha` 的子命令只有
  `daemon` / `batch` / `version`，`wparse work` 直接 `unrecognized subcommand` 导致无限重启。
- 文件 sink 的 `fmt = "proto"` 改成 `"proto-text"`（上游只接受
  `json,csv,show,kv,raw,proto-text`，否则容器启动即 `配置错误`）。

## [0.1.0] - 2026-10-29

### Added

- 初版 stack：数据面 = 上游 `warp-parse` 镜像（`tcp` source + mTLS），控制面 = 宿主 daemon `wist-ingest-ctrl`，管理台 = `wist-ingest-web`。
- 种子配置（`sys/configs/ingest/`）：`framing = "len"`、显式 `tls.ca`、文件 sink + 四个 infra sink。
- `scripts/init-ingest.sh`：以部署账号预建运行根与嵌套挂载点（避免 Docker 以 root 建）。
- `sys-prj.yml`：`identity/ingest` 进 `contract`/`backup`，`data-plane-run` 进 `protect`。
