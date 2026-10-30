# Changelog

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
