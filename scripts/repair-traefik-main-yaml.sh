#!/bin/bash
# main.yaml inválido derruba o file provider inteiro e o Traefik responde 404.
# Remove vírgula sobrando (o que quebra na linha 353/354) e só publica o arquivo
# se um Traefik temporário conseguir carregá-lo. Não reinicia o Traefik do ar.
set -euo pipefail

CFG_DIR=/etc/easypanel/traefik/config
MAIN="${CFG_DIR}/main.yaml"
STAMP="$(date +%Y%m%d%H%M%S)"
IMG="$(docker service inspect easypanel-traefik --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}')"
CLEANER=/tmp/strip-traefik-commas.py

http_code() {
  local code
  code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 12 "$@" 2>/dev/null || true)"
  [[ -n "$code" ]] || code="000"
  printf '%s' "$code"
}

cat >"$CLEANER" <<'PY'
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
    print(f"braces_desbalanceadas {fixed.count('{')} {fixed.count('}')}")
    raise SystemExit(2)
dst.write_text(fixed, encoding="utf-8")
print(f"commas_removed={removed}")
PY

echo "===== main.yaml 345-365 ====="
nl -ba "$MAIN" | awk 'NR>=345 && NR<=365 {print}'
cp -a "$MAIN" "${MAIN}.bak-broken-${STAMP}"

traefik_accepts() {
  local file="$1"
  local dir log
  dir="$(mktemp -d)"
  cp -a "$file" "${dir}/main.yaml"
  log="$(timeout 8 docker run --rm --network none \
    -e TRAEFIK_ENTRYPOINTS_HTTP_ADDRESS=:8080 \
    -e TRAEFIK_ENTRYPOINTS_HTTPS_ADDRESS=:8443 \
    -e TRAEFIK_PROVIDERS_FILE_DIRECTORY=/data/config \
    -e TRAEFIK_PROVIDERS_FILE_WATCH=false \
    -e TRAEFIK_LOG_LEVEL=ERROR \
    -v "${dir}:/data/config:ro" \
    "$IMG" 2>&1 || true)"
  rm -rf "$dir"
  if printf '%s\n' "$log" | grep -q 'did not find expected node content\|Error while building configuration'; then
    printf '%s\n' "$log" | grep -E 'main.yaml|ERR' | tail -3
    return 1
  fi
  if printf '%s\n' "$log" | grep -qi 'unable to find image\|executable file not found\|unknown flag'; then
    printf '%s\n' "$log" | tail -20
    return 2
  fi
  return 0
}

install_file() {
  local file="$1"
  echo "INSTALANDO $file"
  cp -a "$file" "$MAIN"
  sleep 8
  echo "---- logs ----"
  docker service logs easypanel-traefik --since 15s 2>&1 | grep -E 'main.yaml|Configuration loaded|ERR' | tail -12 || true
  echo -n "corban:"
  http_code https://corban.nexmeta.com.br/
  echo
  echo -n "nexmeta:"
  http_code https://nexmeta.com.br/
  echo
  echo -n "waba:"
  http_code https://wabadisparos.com.br/
  echo
}

try_file() {
  local src="$1"
  local cleaned="/tmp/traefik-candidate-${STAMP}.yaml"
  local rc
  python3 "$CLEANER" "$src" "$cleaned"
  if traefik_accepts "$cleaned"; then
    install_file "$cleaned"
    exit 0
  else
    rc=$?
  fi
  if [[ "$rc" -eq 2 ]]; then
    echo "O Traefik temporário não chegou a ler o arquivo. Nada foi trocado."
    exit 1
  fi
}

echo "---- teste do main.yaml sem a vírgula sobrando ----"
try_file "$MAIN"

echo "---- procurando backup que o Traefik aceita ----"
shopt -s nullglob
for candidate in $(ls -1t "${CFG_DIR}"/main.yaml.bak*); do
  case "$candidate" in
    *bak-broken-*|*bak-ep-*) continue ;;
  esac
  echo "TESTE $candidate"
  try_file "$candidate"
done

echo "Nenhum arquivo passou. Cópia quebrada: ${MAIN}.bak-broken-${STAMP}"
exit 1
