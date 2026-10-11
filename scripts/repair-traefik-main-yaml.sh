#!/bin/bash
# O file provider inteiro deixa de carregar quando main.yaml está inválido.
# Traefik então responde 404 para todos os domínios, mesmo com o app no ar.
# Este script restaura o backup parseável mais recente. Não reinicia o Traefik.
set -euo pipefail

CFG_DIR=/etc/easypanel/traefik/config
MAIN="${CFG_DIR}/main.yaml"
STAMP="$(date +%Y%m%d%H%M%S)"

http_code() {
  local code
  code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 12 "$@" 2>/dev/null || true)"
  [[ -n "$code" ]] || code="000"
  printf '%s' "$code"
}

echo "===== main.yaml linhas 340-370 ====="
nl -ba "$MAIN" | awk 'NR>=340 && NR<=370 {print}'
echo "===== whitespace 348-358 ====="
sed -n '348,358p' "$MAIN" | cat -A

cp -a "$MAIN" "${MAIN}.bak-broken-${STAMP}"

choice="$(python3 - "$CFG_DIR" "$MAIN" <<'PY'
import json, sys
from pathlib import Path

cfg, current = Path(sys.argv[1]), Path(sys.argv[2])
try:
    import yaml
except ImportError:
    yaml = None

def parses(path: Path):
    text = path.read_text(encoding="utf-8", errors="replace")
    errors = []
    if yaml is not None:
        try:
            yaml.safe_load(text)
            return True, "yaml"
        except Exception as exc:
            errors.append(f"yaml: {exc}")
    stripped = text.lstrip()
    if stripped.startswith("{") or stripped.startswith("["):
        try:
            json.loads(text)
            return True, "json"
        except Exception as exc:
            errors.append(f"json: {exc}")
    if not errors:
        errors.append("sem parser yaml e arquivo não é JSON")
    return False, " | ".join(errors)

ok, detail = parses(current)
print(f"CURRENT {'OK' if ok else 'FAIL'} {detail}", file=sys.stderr)
if ok:
    print("NONE")
    raise SystemExit(0)

candidates = []
for path in cfg.glob("main.yaml.bak*"):
    if not path.is_file() or path.resolve() == current.resolve():
        continue
    good, how = parses(path)
    print(f"BACKUP {'OK' if good else 'FAIL'} {path.name} {how}", file=sys.stderr)
    if good:
        candidates.append(path)

if not candidates:
    print("NONE")
    raise SystemExit(0)

newest = max(candidates, key=lambda p: p.stat().st_mtime)
print(newest)
PY
)"

if [[ "$choice" == "NONE" || -z "$choice" ]]; then
  echo "Nenhum backup parseável. main.yaml quebrado permanece. Nada restaurado além da cópia ${MAIN}.bak-broken-${STAMP}"
  exit 1
fi

echo "RESTAURANDO $choice"
cp -a "$choice" "$MAIN"
sleep 8
echo "---- logs ----"
docker service logs easypanel-traefik --since 20s 2>&1 | grep -E 'main.yaml|Configuration loaded|ERR' | tail -15 || true
echo -n "corban:"
http_code https://corban.nexmeta.com.br/
echo
echo -n "nexmeta:"
http_code https://nexmeta.com.br/
echo
echo -n "waba:"
http_code https://wabadisparos.com.br/
echo
