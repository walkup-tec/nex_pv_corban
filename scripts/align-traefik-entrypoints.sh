#!/bin/bash
# Alinha os entryPoints dos arquivos do Traefik com os nomes do processo em execução.
# 404 "page not found" neste VPS acontece quando o router diz web/websecure
# e o Traefik escuta http/https, ou o contrário.
# Só troca esses nomes dentro de entryPoints. Não mexe em URL de backend,
# não reinicia o Traefik e grava backup antes de alterar.
set -euo pipefail

CFG_DIR=/etc/easypanel/traefik/config
STAMP="$(date +%Y%m%d%H%M%S)"

http_code() {
  local code
  code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 12 "$@" 2>/dev/null || true)"
  [[ -n "$code" ]] || code="000"
  printf '%s' "$code"
}

svc="$(docker service ls --format '{{.Name}}' | grep -Ei 'traefik' | head -1 || true)"
if [[ -z "$svc" ]]; then
  echo "ERRO: serviço Traefik não encontrado"
  docker service ls
  exit 1
fi

echo "traefik_service=$svc"
docker service ps "$svc" --format 'table {{.Name}}\t{{.CurrentState}}\t{{.Error}}' | head -5
echo "---- entrypoints no processo ----"
docker service inspect "$svc" --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
  | grep -E 'ENTRYPOINTS_.*_ADDRESS' || true
echo "---- erros recentes ----"
docker service logs "$svc" --tail 80 2>&1 | grep -Ei 'entrypoint|error|ERR' | tail -20 || true

mapfile -t eps < <(docker service inspect "$svc" --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' | python3 -c '
import re, sys
http_ep = https_ep = ""
for line in sys.stdin:
    m = re.match(r"TRAEFIK_ENTRYPOINTS_([A-Za-z0-9]+)_ADDRESS=(.+)", line.strip())
    if not m:
        continue
    name, addr = m.group(1).lower(), m.group(2)
    if addr.rstrip("/").endswith(":443"):
        https_ep = name
    elif addr.rstrip("/").endswith(":80"):
        http_ep = name
if not http_ep or not https_ep:
    sys.exit(1)
print(http_ep)
print(https_ep)
')
http_ep="${eps[0]:-}"
https_ep="${eps[1]:-}"
if [[ -z "$http_ep" || -z "$https_ep" ]]; then
  echo "ERRO: não encontrei entrypoints nas portas :80 e :443. Nada foi alterado."
  exit 1
fi
echo "live_entrypoints=${http_ep}/${https_ep}"

python3 - "$CFG_DIR" "$http_ep" "$https_ep" "$STAMP" <<'PY'
import re, sys, shutil
from pathlib import Path

cfg, http_ep, https_ep, stamp = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
http_aliases = {"web", "http"}
https_aliases = {"websecure", "https"}

def fix_inner(inner):
    changes = 0
    def tok(m):
        nonlocal changes
        name = m.group(1)
        low = name.lower()
        if low in https_aliases and low != https_ep:
            changes += 1
            return f'"{https_ep}"'
        if low in http_aliases and low != http_ep:
            changes += 1
            return f'"{http_ep}"'
        return m.group(0)
    return re.sub(r'["\']([A-Za-z0-9_-]+)["\']', tok, inner), changes

def fix_text(text):
    total = 0
    def repl(m):
        nonlocal total
        new_inner, n = fix_inner(m.group(2))
        total += n
        return m.group(1) + new_inner + m.group(3)
    text = re.sub(r'("entryPoints"\s*:\s*\[)(.*?)(\])', repl, text, flags=re.S)
    lines = text.splitlines(keepends=True)
    out = []
    in_ep = False
    for line in lines:
        if re.match(r"^\s*entryPoints\s*:\s*$", line):
            in_ep = True
            out.append(line)
            continue
        if in_ep:
            m = re.match(r"^(\s*-\s*)(websecure|web|https|http)\s*$", line.strip("\r"), re.I)
            if m:
                name = m.group(2).lower()
                new = https_ep if name in https_aliases else http_ep
                if new != name:
                    total += 1
                nl = "\n" if line.endswith("\n") else ""
                out.append(f"{m.group(1)}{new}{nl}")
                continue
            in_ep = False
        out.append(line)
    return "".join(out), total

changed_files = 0
for path in sorted(cfg.iterdir()):
    if not path.is_file():
        continue
    if path.suffix.lower() not in {".yaml", ".yml", ".json"}:
        continue
    if "bak" in path.name:
        continue
    original = path.read_text(encoding="utf-8", errors="replace")
    if original.count("{") != original.count("}"):
        print(f"SKIP {path.name}: chaves desbalanceadas")
        continue
    updated, n = fix_text(original)
    if n == 0 or updated == original:
        print(f"ok {path.name}")
        continue
    if updated.count("{") != original.count("{"):
        print(f"ABORT {path.name}: alteração desbalanceou chaves")
        continue
    backup = path.with_name(path.name + f".bak-ep-{stamp}")
    shutil.copy2(path, backup)
    path.write_text(updated, encoding="utf-8")
    changed_files += 1
    print(f"FIXED {path.name} tokens={n} bak={backup.name}")

print(f"files_changed={changed_files}")
PY

sleep 8
echo -n "corban:"
http_code https://corban.nexmeta.com.br/
echo
echo -n "nexmeta:"
http_code https://nexmeta.com.br/
echo
echo -n "waba:"
http_code https://wabadisparos.com.br/
echo
