#!/bin/bash
# Monitora app, corban e nexmeta. Se algum não terminar em HTTP 200,
# roda a correção do Traefik e, em seguida, a rota do Corban.
# Não reinicia o Traefik.
#
# Uso (root): install | run | status | uninstall
set -euo pipefail

INSTALL_DIR=/root/nex-infra
SELF="${INSTALL_DIR}/monitor-nex-sites.sh"
REPAIR="${INSTALL_DIR}/repair-traefik-main-yaml.sh"
HEAL="${INSTALL_DIR}/heal-nex-corban-pos-redeploy.sh"
ALIGN="${INSTALL_DIR}/align-traefik-entrypoints.sh"
LOG=/var/log/monitor-nex-sites.log
LOCK=/var/lock/monitor-nex-sites.lock
STATE_DIR=/var/lib/nex-monitor
HEAVY_STAMP="${STATE_DIR}/last-heavy-repair"
CFG_DIR=/etc/easypanel/traefik/config
MAIN="${CFG_DIR}/main.yaml"
UNIT_DIR=/etc/systemd/system
SERVICE_UNIT=monitor-nex-sites.service
TIMER=monitor-nex-sites.timer
HEAVY_COOLDOWN=600

URL_APP="http://app.nexmeta.com.br/"
URL_CORBAN="https://corban.nexmeta.com.br/"
URL_NEXMETA="https://nexmeta.com.br/"

log() { printf '[%s] %s\n' "$(date -Is)" "$*" | tee -a "$LOG"; }

http_code() {
  local code
  code="$(curl -sk -o /dev/null -w '%{http_code}' --max-redirs 3 -L --max-time 12 "$@" 2>/dev/null || true)"
  [[ -n "$code" ]] || code="000"
  printf '%s' "$code"
}

probe() {
  APP_CODE="$(http_code "$URL_APP")"
  CORBAN_CODE="$(http_code "$URL_CORBAN")"
  NEXMETA_CODE="$(http_code "$URL_NEXMETA")"
}

healthy() {
  [[ "$APP_CODE" == "200" && "$CORBAN_CODE" == "200" && "$NEXMETA_CODE" == "200" ]]
}

report() {
  printf 'app:%s corban:%s nexmeta:%s\n' "$APP_CODE" "$CORBAN_CODE" "$NEXMETA_CODE"
}

parse_error() {
  docker service logs easypanel-traefik --tail 80 2>&1 \
    | grep -q 'did not find expected node content\|Error while building configuration' 
}

fast_fix_main() {
  [[ -f "$MAIN" ]] || return 0
  local tmp removed
  tmp="$(mktemp)"
  removed="$(python3 - "$MAIN" "$tmp" <<'PY'
import sys
from pathlib import Path
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
text = src.read_text(encoding="utf-8", errors="replace")

def strip_bad_commas(text):
    out = []
    i = 0
    n = len(text)
    in_str = False
    quote = ""
    esc = False
    removed = 0
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if quote == "'" and c == "'" and i + 1 < n and text[i + 1] == "'":
                out.append(text[i + 1])
                i += 2
                continue
            if quote == '"' and esc:
                esc = False
            elif quote == '"' and c == "\\":
                esc = True
            elif c == quote:
                in_str = False
            i += 1
            continue
        if c in ("'", '"'):
            in_str = True
            quote = c
            esc = False
            out.append(c)
            i += 1
            continue
        if c == ",":
            j = len(out) - 1
            while j >= 0 and out[j] in " \t\r\n":
                j -= 1
            prev = out[j] if j >= 0 else ""
            k = i + 1
            while k < n and text[k] in " \t\r\n":
                k += 1
            nxt = text[k] if k < n else ""
            if prev in "{[," or nxt in "}]":
                removed += 1
                i += 1
                continue
        out.append(c)
        i += 1
    return "".join(out), removed

fixed = text
removed = 0
while True:
    fixed, more = strip_bad_commas(fixed)
    removed += more
    if more == 0:
        break
if fixed.count("{") != fixed.count("}"):
    print("-1")
    raise SystemExit(0)
dst.write_text(fixed, encoding="utf-8")
print(removed)
PY
)"
  if [[ "${removed:-0}" =~ ^[0-9]+$ && "$removed" -gt 0 ]]; then
    cp -a "$MAIN" "${MAIN}.bak-monitor-${STAMP:-$(date +%Y%m%d%H%M%S)}"
    cp -a "$tmp" "$MAIN"
    log "main.yaml: removidas ${removed} vírgulas inválidas"
    sleep 8
  fi
  rm -f "$tmp"
}

heavy_allowed() {
  [[ -f "$HEAVY_STAMP" ]] || return 0
  local now last
  now="$(date +%s)"
  last="$(cat "$HEAVY_STAMP" 2>/dev/null || echo 0)"
  (( now - last >= HEAVY_COOLDOWN ))
}

cmd_run() {
  mkdir -p "$(dirname "$LOG")" "$STATE_DIR" "$(dirname "$LOCK")"
  exec 9>"$LOCK"
  flock -n 9 || exit 0
  probe
  if healthy; then
    exit 0
  fi
  log "FORA $(report)"

  if parse_error; then
    fast_fix_main || true
    probe
    if healthy; then
      log "NO AR depois da vírgula $(report)"
      exit 0
    fi
    if [[ -x "$REPAIR" ]] && heavy_allowed; then
      log "correção completa do main.yaml"
      date +%s >"$HEAVY_STAMP"
      bash "$REPAIR" >>"$LOG" 2>&1 || true
      probe
      if healthy; then
        log "NO AR depois da correção completa $(report)"
        exit 0
      fi
    fi
  fi

  if [[ -f "$MAIN" ]] && grep -qE 'entryPoints[^]]{0,80}websecure|entryPoints[^]]{0,40}"web"' "$MAIN" && [[ -x "$ALIGN" ]]; then
    log "alinhando entrypoints"
    bash "$ALIGN" >>"$LOG" 2>&1 || true
    probe
    if healthy; then
      log "NO AR depois dos entrypoints $(report)"
      exit 0
    fi
  fi

  if [[ "$CORBAN_CODE" != "200" && -x "$HEAL" ]]; then
    log "republicando rota do Corban"
    bash "$HEAL" run >>"$LOG" 2>&1 || true
    probe
  fi

  if healthy; then
    log "NO AR $(report)"
  else
    log "AINDA FORA $(report)"
  fi
}

install_units() {
  cat >"${UNIT_DIR}/${SERVICE_UNIT}" <<EOF
[Unit]
Description=Monitor NEX — corrige quando algum domínio sai de 200
After=docker.service
[Service]
Type=oneshot
TimeoutStartSec=300
ExecStart=${SELF} run
EOF

  cat >"${UNIT_DIR}/${TIMER}" <<EOF
[Unit]
Description=Monitor dos domínios NEX a cada 30s
[Timer]
OnBootSec=25s
OnActiveSec=30s
OnUnitActiveSec=30s
AccuracySec=5s
Persistent=true
[Install]
WantedBy=timers.target
EOF
}

cmd_install() {
  [[ "$(id -u)" -eq 0 ]] || { echo "rode como root"; exit 1; }
  mkdir -p "$INSTALL_DIR" "$STATE_DIR" "$(dirname "$LOG")"
  local src_dir src
  src="${BASH_SOURCE[0]}"
  src_dir="$(cd "$(dirname "$src")" && pwd)"
  if [[ -f "$src" && "$(readlink -f "$src")" != "$(readlink -f "$SELF")" ]]; then
    cp -f "$src" "$SELF"
  fi
  local extra src_file dst_file
  for extra in repair-traefik-main-yaml.sh heal-nex-corban-pos-redeploy.sh align-traefik-entrypoints.sh; do
    src_file="${src_dir}/${extra}"
    dst_file="${INSTALL_DIR}/${extra}"
    [[ -f "$src_file" ]] || continue
    if [[ -f "$dst_file" && "$(readlink -f "$src_file")" == "$(readlink -f "$dst_file")" ]]; then
      continue
    fi
    cp -f "$src_file" "$dst_file"
  done
  sed -i 's/\r$//' "$SELF" "$REPAIR" "$HEAL" "$ALIGN" 2>/dev/null || true
  chmod +x "$SELF" "$REPAIR" "$HEAL" "$ALIGN" 2>/dev/null || true
  [[ -f "$SELF" ]] || { echo "script ausente em $SELF"; exit 1; }
  install_units
  systemctl daemon-reload
  systemctl enable "$TIMER" >/dev/null
  systemctl restart "$TIMER"
  "$SELF" run || true
  cmd_status
}

cmd_uninstall() {
  systemctl disable --now "$TIMER" 2>/dev/null || true
  rm -f "${UNIT_DIR}/${TIMER}" "${UNIT_DIR}/${SERVICE_UNIT}"
  systemctl daemon-reload
}

cmd_status() {
  probe
  echo "timer=$(systemctl is-active "$TIMER" 2>/dev/null || echo inactive)"
  echo "app=${APP_CODE}"
  echo "corban=${CORBAN_CODE}"
  echo "nexmeta=${NEXMETA_CODE}"
}

case "${1:-}" in
  run) cmd_run ;;
  install) cmd_install ;;
  uninstall) cmd_uninstall ;;
  status) cmd_status ;;
  *)
    echo "Uso: $0 install|run|status|uninstall"
    exit 1
    ;;
esac
