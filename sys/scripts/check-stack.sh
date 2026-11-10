#!/usr/bin/env sh
# 栈自检（幂等、只读）。由 `flow localize` 在首尾各调一次，也可以手工跑。
#
#   ./sys/scripts/check-stack.sh --gate --only prereq   # ⓿ 这台机器能不能跑 localize
#   ./sys/scripts/check-stack.sh --gate                 # ⑤ 渲染结果是否自洽
#   ./sys/scripts/check-stack.sh                        # 只报告，不改变退出码
#
# 为什么要有 ⓿：localize 由别的进程派生（升级事务、CI），PATH 里可能没有 Homebrew；
# 缺 gx / gops / openssl 时后面的脚本会**静默退 1**，等到最后才报「localize failed」，
# 现场只能靠猜。
set -eu

STACK_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$STACK_ROOT"

GATE=0
ONLY=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --gate) GATE=1; shift ;;
    --only) ONLY="${2:?--only 需要 prereq|render}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

fails=0
warns=0
fail() { fails=$((fails + 1)); echo "  [FAIL] $*" >&2; }
warn() { warns=$((warns + 1)); echo "  [WARN] $*" >&2; }
ok()   { echo "  [ok]   $*"; }

# ── ⓿ 前置能力 ────────────────────────────────────────────────────────────────
check_prereq() {
  echo "prereq:"
  for tool in gx gops docker openssl; do
    if command -v "$tool" >/dev/null 2>&1; then
      ok "$tool"
    else
      fail "缺少 $tool（localize 需要它；升级事务里缺 gx 会当场回滚）"
    fi
  done
  if [ -f sys/docker-compose.yml ]; then
    ok "sys/docker-compose.yml"
  else
    fail "sys/docker-compose.yml 不存在"
  fi
  if [ -f .env ]; then
    ok ".env（gops sys localize 产物）"
  else
    warn ".env 不存在：手工跑 localize 时用 .env.example；gops 会先生成它"
  fi
}

# ── ⑤ 渲染结果 ────────────────────────────────────────────────────────────────
# A 类：产品内容，每次 localize 覆盖（见 sys/workflows/operators.gxl 的分段说明）。
A_FILES="
conf/wparse.toml
connectors/sink.d/10-file.toml
models/wpl/raw_log.wpl
models/oml/raw_log/adm.oml
topology/sinks/defaults.toml
topology/sinks/business.d/ingest.toml
topology/sinks/infra.d/default.toml
topology/sinks/infra.d/error.toml
topology/sinks/infra.d/miss.toml
topology/sinks/infra.d/residue.toml
"
# C 类：只补缺 / 他服务生成，**不进 tpl**。少一件都说明备料没跑完。
C_FILES="
connectors/source.d/90-ingest-tcp.toml
topology/sources/wpsrc.toml
"

check_render() {
  echo "render:"
  work="data-plane-run/work"

  missing=0
  for rel in $A_FILES; do
    if [ -s "$work/$rel" ]; then continue; fi
    fail "A 类缺失或为空：$work/$rel（localize 里的 gx.tpl 没跑？）"
    missing=1
  done
  if [ "$missing" = 0 ]; then
    ok "A 类 10 件已渲染到 $work/"
  fi

  missing=0
  for rel in $C_FILES; do
    if [ -s "$work/$rel" ]; then continue; fi
    fail "C 类缺失：$work/$rel（init-ingest.sh 没补上；首次部署时它由种子引导）"
    missing=1
  done
  if [ "$missing" = 0 ]; then
    ok "C 类 2 件在位（首次由种子引导，之后由 ctrl apply 接管）"
  fi

  if [ -s configs/ingest-ctrl/ingest-ctrl.toml ]; then
    ok "C 类 ingest-ctrl.toml 在位（现场态，localize 不碰）"
  else
    fail "configs/ingest-ctrl/ingest-ctrl.toml 缺失（init-ingest.sh 只补缺，不会覆盖现场改动）"
  fi

  # 残留占位：gx.tpl 渲过之后不该再有 {{ }}；`${SEC_…}` 是留给服务展开的，允许。
  leftovers="$(grep -rlF '{{' "$work" configs/ingest-ctrl 2>/dev/null || true)"
  if [ -n "$leftovers" ]; then
    fail "渲染残留 {{ }}：$leftovers"
  else
    ok "无 handlebars 残留"
  fi

  # 变量三处一致：sys/setting/vars.yml（→ merged_vars）必须与 .env.example 逐键对齐。
  # 不齐的典型后果：CI 用 .env.example 渲 compose，新变量在 CI 里是空字符串。
  if [ -f sys/merged_vars.yml ] && [ -f .env.example ]; then
    names="$(grep -E '^  - name: [A-Z_][A-Z0-9_]*' sys/merged_vars.yml | sed 's/.*name: //' | sort)"
    drift=""
    for name in $names; do
      grep -qE "^${name}=" .env.example || drift="$drift $name"
    done
    if [ -n "$drift" ]; then
      fail ".env.example 缺变量：$drift（CI 渲 compose 用这份）"
    else
      ok "变量与 .env.example 一致"
    fi
  else
    warn "缺 sys/merged_vars.yml 或 .env.example，跳过变量一致性检查"
  fi
}

case "$ONLY" in
  prereq) check_prereq ;;
  render|"") check_prereq; check_render ;;
  *) echo "--only 只支持 prereq|render" >&2; exit 2 ;;
esac

echo
if [ "$fails" -gt 0 ]; then
  echo "check-stack: $fails 项失败，$warns 项告警" >&2
  [ "$GATE" = 1 ] && exit 1
  exit 0
fi
echo "check-stack: ok（$warns 项告警）"
