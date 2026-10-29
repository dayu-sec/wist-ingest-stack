# Changelog

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
