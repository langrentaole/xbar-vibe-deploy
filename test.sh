#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

set_value() {
  key=$1
  value=$2
  temporary="$SANDBOX/env.tmp"
  awk -v key="$key" -v value="$value" 'BEGIN { FS = "=" } $1 == key { print key "=" value; next } { print }' "$SANDBOX/.env" >"$temporary"
  mv "$temporary" "$SANDBOX/.env"
}

cp "$ROOT_DIR/.env.example" "$SANDBOX/.env"
set_value XBAR_VIBE_IMAGE langrentaole/xbar-vibe:old
set_value VIBE_DOMAIN vibe.test
set_value ACME_EMAIL ops@test.invalid
set_value VIBE_CONTROL_URL https://core.test/api/vibe-coding/gateway/internal
set_value VIBE_CONTROL_HOST core.test
set_value VIBE_CONTROL_ORIGIN_IP 203.0.113.10
set_value VIBE_UPSTREAM_URL http://host.docker.internal:8080
set_value VIBE_STATION_ID station-test-id
set_value VIBE_PUBLIC_IP 203.0.113.20
set_value VIBE_IDENTITY_DIR /var/lib/xbar-vibe
set_value XBAR_VIBE_VERSION old
set_value VIBE_EDGE_SHARED_SECRET 0123456789abcdef0123456789abcdef
set_value VIBE_EDGE_ORIGIN_TOKEN fedcba9876543210fedcba9876543210

mkdir -p "$SANDBOX/bin"
cat >"$SANDBOX/bin/docker" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$SANDBOX/bin/docker"

PATH="$SANDBOX/bin:$PATH" XBAR_VIBE_ENV_FILE="$SANDBOX/.env" "$ROOT_DIR/deploy.sh" update >/dev/null
expected_image=$(sed -n 's/^XBAR_VIBE_IMAGE=//p' "$ROOT_DIR/.env.example")
expected_version=$(sed -n 's/^XBAR_VIBE_VERSION=//p' "$ROOT_DIR/.env.example")
actual_image=$(sed -n 's/^XBAR_VIBE_IMAGE=//p' "$SANDBOX/.env")
actual_version=$(sed -n 's/^XBAR_VIBE_VERSION=//p' "$SANDBOX/.env")
[ "$actual_image" = "$expected_image" ] || {
  echo "update 未同步 Vibe 镜像版本：$actual_image" >&2
  exit 1
}
[ "$actual_version" = "$expected_version" ] || {
  echo "update 未同步 Vibe 运行版本：$actual_version" >&2
  exit 1
}
[ "$(sed -n 's/^VIBE_DOMAIN=//p' "$SANDBOX/.env")" = "vibe.test" ] || {
  echo "update 不应修改客户域名" >&2
  exit 1
}
[ "$(sed -n 's/^VIBE_EDGE_SHARED_SECRET=//p' "$SANDBOX/.env")" = "0123456789abcdef0123456789abcdef" ] || {
  echo "update 不应修改客户密钥" >&2
  exit 1
}

echo "xbar-vibe-deploy tests passed"
