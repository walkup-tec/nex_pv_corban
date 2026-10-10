#!/bin/bash
# Heal NEX Corban depois do deploy do EasyPanel.
# O redeploy tira a porta publicada e o Traefik volta a procurar o serviço
# na rede overlay, que neste VPS não alcança o container. Resultado: 502.
#
# Este script só mexe em:
# - publish host :30322 do serviço nex_pv_corban
# - /etc/easypanel/traefik/config/nex-pv-corban.yaml
# Não altera main.yaml e não reinicia o Traefik.
#
# Uso no VPS, como root: install | run | status | uninstall
set -euo pipefail

SERVICE_NAME=nex_pv_corban
HOST_PORT=30322
TARGET_PORT=30322
CFG_DIR=/etc/easypanel/traefik/config
YAML="${CFG_DIR}/nex-pv-corban.yaml"
LOG=/var/log/heal-nex-corban.log
LOCK=/var/lock/heal-nex-corban.lock
INSTALL_DIR=/root/nex-infra
SELF="${INSTALL_DIR}/heal-nex-corban-pos-redeploy.sh"
UNIT_DIR=/etc/systemd/system
TIMER=heal-nex-corban.timer
SERVICE_UNIT=heal-nex-corban.service
WATCH=heal-nex-corban-watch.service
DOMAIN=corban.nexmeta.com.br
PANEL_HOST=nex-pv-corban.achpyp.easypanel.host
SENTINEL=https://nexmeta.com.br/
URL="http://172.17.0.1:${HOST_PORT}/"

log() { printf '[%s] %s\n' "$(date -Is)" "$*" | tee -a "$LOG"; }

http_code() {
  curl -sk -o /dev/null -w '%{http_code}' --max-time 12 "$@" 2>/dev/null || echo 000
}

ok_code() {
  case "$1" in
    200|301|302|303|307|308) return 0 ;;
    *) return 1 ;;
  esac
}

publish_ok() {
  docker service inspect "$SERVICE_NAME" --format '{{json .Endpoint.Ports}}' 2>/dev/null \
    | grep -q "\"PublishedPort\":${HOST_PORT}"
}

ensure_publish() {
  docker service ls --format '{{.Name}}' | grep -qx "$SERVICE_NAME" || {
    log "serviço ${SERVICE_NAME} ausente"
    return 1
  }
  if publish_ok; then
    return 0
  fi
  log "republicando :${HOST_PORT} mode=host target=${TARGET_PORT}"
  docker service update \
    --publish-add "mode=host,published=${HOST_PORT},target=${TARGET_PORT},protocol=tcp" \
    "$SERVICE_NAME" >>"$LOG" 2>&1
  sleep 6
}

yaml_ok() {
  [[ -f "$YAML" ]] || return 1
  grep -q "172.17.0.1:${HOST_PORT}" "$YAML" || return 1
  grep -q "$DOMAIN" "$YAML" || return 1
  grep -q "$PANEL_HOST" "$YAML" || return 1
}

write_yaml() {
  local resolver="letsencrypt"
  resolver="$(
    docker service inspect easypanel-traefik \
      --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' 2>/dev/null \
      | grep -iE '^TRAEFIK_CERTIFICATESRESOLVERS_' \
      | head -1 \
      | sed -E 's/^TRAEFIK_CERTIFICATESRESOLVERS_([^_]+)_.*/\1/' \
      | tr '[:upper:]' '[:lower:]' || true
  )"
  [[ -n "${resolver:-}" ]] || resolver="letsencrypt"

  python3 - "$YAML" "$URL" "$DOMAIN" "$PANEL_HOST" "$resolver" <<'PY'
import json, sys
from pathlib import Path
path, url, domain, panel, resolver = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
rule = f"Host(`{domain}`) || Host(`{panel}`)"
data = {
  "http": {
    "middlewares": {
      "nex-corban-redirect-https": {"redirectScheme": {"scheme": "https", "permanent": True}}
    },
    "routers": {
      "nex-corban-http": {
        "entryPoints": ["http"],
        "middlewares": ["nex-corban-redirect-https"],
        "service": "nex-corban-svc",
        "rule": rule,
        "priority": 100000,
      },
      "nex-corban-https": {
        "entryPoints": ["https"],
        "service": "nex-corban-svc",
        "rule": rule,
        "priority": 100000,
        "tls": {"certResolver": resolver},
      },
    },
    "services": {
      "nex-corban-svc": {
        "loadBalancer": {
          "servers": [{"url": url}],
          "passHostHeader": True,
        }
      }
    },
  }
}
tmp = path.with_suffix(".yaml.tmp")
tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
tmp.replace(path)
print(f"wrote {path}")
PY
}

ensure_yaml() {
  if yaml_ok; then
    return 0
  fi
  local before after
  before="$(http_code "$SENTINEL")"
  log "regravando ${YAML}"
  mkdir -p "$CFG_DIR"
  write_yaml >>"$LOG" 2>&1
  sleep 8
  after="$(http_code "$SENTINEL")"
  if ok_code "$before" && ! ok_code "$after"; then
    log "nexmeta.com.br caiu (${before} -> ${after}) — removendo ${YAML}"
    rm -f "$YAML"
    return 1
  fi
}

cmd_run() {
  mkdir -p "$(dirname "$LOG")" "$(dirname "$LOCK")"
  exec 9>"$LOCK"
  flock -n 9 || exit 0
  ensure_publish || true
  ensure_yaml || true
  local local_code corban_code
  local_code="$(http_code "$URL")"
  corban_code="$(http_code "https://${DOMAIN}/")"
  if [[ "$local_code" != "200" || "$corban_code" != "200" ]]; then
    log "local:${local_code} corban:${corban_code}"
  fi
}

cmd_watch() {
  docker events --filter type=service --filter type=container \
    --format '{{.Action}} {{.Actor.Attributes.name}} {{.Actor.Attributes.com.docker.swarm.service.name}}' |
  while read -r _action name svc; do
    case "${name}${svc}" in
      *nex_pv_corban*)
        sleep 40
        "$SELF" run || true
        ;;
    esac
  done
}

install_units() {
  cat >"${UNIT_DIR}/${SERVICE_UNIT}" <<EOF
[Unit]
Description=Heal NEX Corban apos deploy
After=docker.service
[Service]
Type=oneshot
TimeoutStartSec=180
ExecStart=${SELF} run
EOF

  cat >"${UNIT_DIR}/${TIMER}" <<EOF
[Unit]
Description=Heal NEX Corban a cada 30s
[Timer]
OnBootSec=45s
OnActiveSec=30s
OnUnitActiveSec=30s
AccuracySec=5s
Persistent=true
[Install]
WantedBy=timers.target
EOF

  cat >"${UNIT_DIR}/${WATCH}" <<EOF
[Unit]
Description=Heal NEX Corban quando o servico e recriado
After=docker.service
[Service]
Type=simple
Restart=always
RestartSec=5
ExecStart=${SELF} watch
[Install]
WantedBy=multi-user.target
EOF
}

cmd_install() {
  [[ "$(id -u)" -eq 0 ]] || { echo "rode como root"; exit 1; }
  mkdir -p "$INSTALL_DIR" "$(dirname "$LOG")"
  local src
  src="${BASH_SOURCE[0]}"
  if [[ -f "$src" ]]; then
    local src_real self_real
    src_real="$(readlink -f "$src")"
    self_real="$(readlink -f "$SELF" 2>/dev/null || echo "$SELF")"
    if [[ "$src_real" != "$self_real" ]]; then
      cp -f "$src" "$SELF"
    fi
  fi
  [[ -f "$SELF" ]] || { echo "script nao encontrado em $SELF"; exit 1; }
  sed -i 's/\r$//' "$SELF"
  chmod +x "$SELF"
  install_units
  systemctl daemon-reload
  systemctl enable "$TIMER" "$WATCH" >/dev/null
  systemctl restart "$TIMER" "$WATCH"
  "$SELF" run || true
  cmd_status
}

cmd_uninstall() {
  systemctl disable --now "$TIMER" "$WATCH" 2>/dev/null || true
  rm -f "${UNIT_DIR}/${TIMER}" "${UNIT_DIR}/${SERVICE_UNIT}" "${UNIT_DIR}/${WATCH}"
  systemctl daemon-reload
}

cmd_status() {
  echo "timer=$(systemctl is-active "$TIMER" 2>/dev/null || echo inactive)"
  echo "watch=$(systemctl is-active "$WATCH" 2>/dev/null || echo inactive)"
  echo "yaml=$([[ -f $YAML ]] && echo present || echo MISSING)"
  echo -n "local:${HOST_PORT}="
  http_code "$URL"
  echo
  echo -n "corban="
  http_code "https://${DOMAIN}/"
  echo
  echo -n "nexmeta="
  http_code "$SENTINEL"
  echo
}

case "${1:-}" in
  run) cmd_run ;;
  watch) cmd_watch ;;
  install) cmd_install ;;
  uninstall) cmd_uninstall ;;
  status) cmd_status ;;
  *)
    echo "Uso: $0 install|run|watch|status|uninstall"
    exit 1
    ;;
esac
