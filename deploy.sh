#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE=${XBAR_VIBE_ENV_FILE:-"$ROOT_DIR/.env"}
export XBAR_VIBE_ENV_FILE=$ENV_FILE

compose() {
  docker compose --project-directory "$ROOT_DIR" --env-file "$ENV_FILE" -f "$ROOT_DIR/docker-compose.yml" "$@"
}

replace_value() {
  key=$1
  value=$2
  temporary="$ENV_FILE.tmp.$$"
  awk -v key="$key" -v value="$value" 'BEGIN { FS = "=" } $1 == key { print key "=" value; next } { print }' "$ENV_FILE" >"$temporary"
  mv "$temporary" "$ENV_FILE"
}

read_value() {
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1
}

template_value() {
  sed -n "s/^$1=//p" "$ROOT_DIR/.env.example" | tail -n 1
}

sync_release() {
  image=$(template_value XBAR_VIBE_IMAGE)
  version=$(template_value XBAR_VIBE_VERSION)
  [ -n "$image" ] && [ -n "$version" ] || {
    echo "部署仓库缺少 Vibe 发布版本" >&2
    exit 1
  }
  if [ "$(read_value XBAR_VIBE_IMAGE)" != "$image" ]; then
    replace_value XBAR_VIBE_IMAGE "$image"
    echo "已同步 Vibe 镜像版本：$image"
  fi
  if [ "$(read_value XBAR_VIBE_VERSION)" != "$version" ]; then
    replace_value XBAR_VIBE_VERSION "$version"
    echo "已同步 Vibe 运行版本：$version"
  fi
}

initialize() {
  if [ -f "$ENV_FILE" ]; then
    echo "环境文件已存在，未覆盖：$ENV_FILE"
    return
  fi
  command -v openssl >/dev/null 2>&1 || {
    echo "缺少 openssl，无法生成安全密钥" >&2
    exit 1
  }
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"
  replace_value VIBE_EDGE_ORIGIN_TOKEN "$(openssl rand -hex 32)"
  chmod 600 "$ENV_FILE"
  echo "已生成：$ENV_FILE"
  echo "请修改域名和地址，并把 xbar-core-deploy/.env 中的 VIBE_EDGE_SHARED_SECRET 原样复制到这里。"
}

validate() {
  [ -f "$ENV_FILE" ] || {
    echo "缺少环境文件，请先执行：./deploy.sh init" >&2
    exit 1
  }
  if grep -Eq '^[A-Z0-9_]+=(replace-with-|copy-from-|.*\.example\.com($|/))' "$ENV_FILE"; then
    echo "环境文件仍有占位值，请先完成配置：$ENV_FILE" >&2
    exit 1
  fi
  for key in XBAR_VIBE_IMAGE VIBE_DOMAIN ACME_EMAIL VIBE_CONTROL_URL VIBE_CONTROL_HOST VIBE_CONTROL_ORIGIN_IP VIBE_UPSTREAM_URL VIBE_STATION_ID VIBE_PUBLIC_IP VIBE_IDENTITY_DIR XBAR_VIBE_VERSION VIBE_EDGE_SHARED_SECRET VIBE_EDGE_ORIGIN_TOKEN; do
    [ -n "$(read_value "$key")" ] || {
      echo "缺少必填配置：$key" >&2
      exit 1
    }
  done
  case "$(read_value VIBE_CONTROL_URL)" in
    https://*/api/vibe-coding/gateway/internal) ;;
    *) echo "VIBE_CONTROL_URL 必须是 Core 的 HTTPS 内部授权接口" >&2; exit 1 ;;
  esac
  case "$(read_value VIBE_CONTROL_URL)" in
    https://"$(read_value VIBE_CONTROL_HOST)"/*) ;;
    *) echo "VIBE_CONTROL_HOST 必须与 VIBE_CONTROL_URL 中的域名一致" >&2; exit 1 ;;
  esac
  case "$(read_value VIBE_UPSTREAM_URL)" in http://*|https://*) ;; *) echo "VIBE_UPSTREAM_URL 必须是 HTTP(S) 地址" >&2; exit 1 ;; esac
  for key in VIBE_EDGE_SHARED_SECRET VIBE_EDGE_ORIGIN_TOKEN; do
    [ "$(printf %s "$(read_value "$key")" | wc -c | tr -d ' ')" -ge 32 ] || {
      echo "$key 至少需要 32 字节" >&2
      exit 1
    }
  done
  [ "$(read_value VIBE_EDGE_SHARED_SECRET)" != "$(read_value VIBE_EDGE_ORIGIN_TOKEN)" ] || {
    echo "VIBE_EDGE_SHARED_SECRET 与 VIBE_EDGE_ORIGIN_TOKEN 禁止复用" >&2
    exit 1
  }
  compose config -q
}

require_docker() {
  command -v docker >/dev/null 2>&1 || {
    echo "未安装 Docker" >&2
    exit 1
  }
  docker compose version >/dev/null 2>&1 || {
    echo "未安装 Docker Compose v2" >&2
    exit 1
  }
}

action=${1:-up}
case "$action" in
  init)
    initialize
    ;;
  config)
    require_docker
    validate
    echo "xbar-vibe 配置有效"
    ;;
  up|install)
    require_docker
    if [ ! -f "$ENV_FILE" ]; then
      initialize
      exit 2
    fi
    validate
    compose pull
    compose up -d --wait --remove-orphans
    compose ps
    ;;
  node-info)
    require_docker
    validate
    compose run --rm identity-init
    compose run --rm --no-deps edge-a node-info
    ;;
  update)
    require_docker
    sync_release
    validate
    compose pull edge-a edge-b
    compose up -d --no-deps --wait edge-a
    compose up -d --no-deps --wait edge-b
    compose up -d --wait --remove-orphans caddy
    compose ps
    ;;
  status)
    require_docker
    validate
    compose ps
    ;;
  logs)
    require_docker
    validate
    compose logs -f --tail=200
    ;;
  down)
    require_docker
    validate
    compose down
    ;;
  *)
    echo "用法：$0 {init|config|node-info|up|update|status|logs|down}" >&2
    exit 64
    ;;
esac
