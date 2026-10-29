# Changelog

## [0.1.0] - 2026-10-29

### Added

- 初版 stack：数据面 = 上游 `warp-parse` 镜像（`tcp` source + mTLS），控制面 = 宿主 daemon `wist-ingest-ctrl`，管理台 = `wist-ingest-web`。
- 种子配置（`sys/configs/ingest/`）：`framing = "len"`、显式 `tls.ca`、文件 sink + 四个 infra sink。
- `scripts/init-ingest.sh`：以部署账号预建运行根与嵌套挂载点（避免 Docker 以 root 建）。
- `sys-prj.yml`：`identity/ingest` 进 `contract`/`backup`，`data-plane-run` 进 `protect`。
