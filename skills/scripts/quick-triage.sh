#!/usr/bin/env bash
# reverse-skill-pro: one-shot artifact triage (bash twin of quick-triage.ps1).
# magic bytes -> file class -> suggested routes -> tool availability -> triage report.
# Usage:
#   bash skills/scripts/quick-triage.sh --path ./app.apk
#   bash skills/scripts/quick-triage.sh --path ./target.so --hint "restore sign algorithm" --project-root /analysis
set -euo pipefail

PATH_ARG=""
HINT=""
PROJECT_ROOT=""
OUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -Path|-path|--path) PATH_ARG="${2:-}"; shift 2 ;;
    -Hint|-hint|--hint) HINT="${2:-}"; shift 2 ;;
    -ProjectRoot|-project-root|--project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
    -OutDir|-out-dir|--out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    -h|--help)
      echo 'Usage: quick-triage.sh --path FILE [--hint TEXT] [--project-root DIR] [--out-dir DIR]'
      exit 0 ;;
    *) echo "Unknown arg: \"$1\"" >&2; exit 2 ;;
  esac
done

if [[ -z "$PATH_ARG" ]]; then echo 'ERROR: --path <artifact> required' >&2; exit 2; fi
if [[ ! -f "$PATH_ARG" ]]; then echo "ERROR: file not found: $PATH_ARG" >&2; exit 2; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PYTHON=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then PYTHON="$candidate"; break; fi
done
if [[ -z "$PYTHON" ]]; then echo 'ERROR: Python 3 required' >&2; exit 2; fi

if [[ -z "$PROJECT_ROOT" ]]; then PROJECT_ROOT="$(pwd -P)"; fi

"$PYTHON" - "$PATH_ARG" "$SKILLS_ROOT" "$PROJECT_ROOT" "$OUT_DIR" "$HINT" <<'PY'
import datetime, hashlib, json, pathlib, struct, subprocess, sys

path_arg, skills_root, project_root, out_dir, hint = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
p = pathlib.Path(path_arg).resolve()
data_head = p.read_bytes()[:16]
hx = data_head.hex()
ext = p.suffix.lower()

def sha256(f):
    h = hashlib.sha256()
    with open(f, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()

file_class, routes, skills = 'unknown', [], []
if hx.startswith('504b0304'):
    if ext == '.apk':   file_class, routes, skills = 'android-apk', ['R1'], ['apk-reverse']
    elif ext == '.crx': file_class, routes, skills = 'browser-extension', ['R30'], ['browser-extension-reverse']
    elif ext == '.jar': file_class, routes, skills = 'java-archive', ['R1'], ['apk-reverse']
    else:               file_class, routes, skills = 'zip-archive', ['R48'], ['stego-analysis']
elif hx.startswith('7f454c46'): file_class, routes, skills = 'elf-binary', ['R6'], ['ida-reverse']
elif hx.startswith('4d5a'):
    file_class, routes, skills = 'pe-binary', ['R6'], ['ida-reverse']
    if ext in ('.dll', '.exe'): routes.append('R5'); skills.append('dotnet-reverse')
elif hx.startswith('6465780a'): file_class, routes, skills = 'android-dex', ['R1'], ['apk-reverse']
elif hx.startswith(('cffaedfe', 'feedface')): file_class, routes, skills = 'mach-o', ['R31'], ['macos-reverse']
elif hx.startswith('cafebabe'): file_class, routes, skills = 'java-class-or-macho', ['R31', 'R1'], ['macos-reverse', 'apk-reverse']
elif hx.startswith('89504e47'): file_class, routes, skills = 'png-image', ['R48'], ['stego-analysis']
elif hx.startswith('ffd8ff'):   file_class, routes, skills = 'jpeg-image', ['R48'], ['stego-analysis']
elif hx.startswith('47494638'): file_class, routes, skills = 'gif-image', ['R48'], ['stego-analysis']
elif hx.startswith('25504446'): file_class, routes, skills = 'pdf-document', ['R48'], ['stego-analysis']
elif hx.startswith('52617221'): file_class, routes, skills = 'rar-archive', ['R41'], ['ctf-sandbox']
elif hx.startswith('377abcaf271c'): file_class, routes, skills = '7z-archive', ['R41'], ['ctf-sandbox']
elif hx.startswith('52494646'): file_class, routes, skills = 'riff-media(wav/avi)', ['R48'], ['stego-analysis']
elif hx.startswith('0061736d'): file_class, routes, skills = 'wasm-module', ['R0'], ['reverse-engineering']
elif hx.startswith('1f8b08'):   file_class, routes, skills = 'gzip-stream', ['R8'], ['firmware-pentest']
elif ext in ('.pcap', '.pcapng'): file_class, routes, skills = 'packet-capture', ['R21'], ['protocol-reverse']
elif ext in ('.bin', '.img', '.rom'): file_class, routes, skills = 'raw-firmware-image?', ['R8'], ['firmware-pentest']

keyword_id, keyword_skill = '', ''
if hint.strip():
    mr = skills_root / 'scripts' / 'master-route.sh'
    tmp = pathlib.Path(project_root) / 'work' / ('qt-route-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    try:
        subprocess.run(['bash', str(mr), '--hint', hint, '--out-dir', str(tmp), '--project-root', project_root],
                       check=False, capture_output=True)
        sf = tmp / 'route-scope.md'
        if sf.exists():
            for line in sf.read_text(encoding='utf-8').splitlines():
                if line.startswith('- primary:'): keyword_id = line.split(':', 1)[1].strip()
                if line.startswith('- primary_skill:'): keyword_skill = line.split(':', 1)[1].strip()
    finally:
        pass

tools_ok, tools_missing = [], []
ti_path = skills_root / 'tool-index.json'
if ti_path.exists():
    ti = json.loads(ti_path.read_text(encoding='utf-8'))
    for t in ti.get('tools', []):
        if t.get('skill') in skills:
            (tools_ok if t.get('available') else tools_missing).append(t['name'])

if not out_dir:
    out_dir = str(pathlib.Path(project_root) / 'work' / ('quick-triage-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S')))
pathlib.Path(out_dir).mkdir(parents=True, exist_ok=True)

lines = [
    '# reverse-skill-pro Quick Triage',
    f'- created: {datetime.datetime.now(datetime.timezone.utc).isoformat()}',
    f'- artifact: {p}',
    f'- size_kb: {round(p.stat().st_size / 1024, 1)}',
    f'- sha256: {sha256(p)}',
    f'- head_hex: {hx[:32]}',
    f'- file_class: {file_class}',
    '',
    '## Suggested routes (by file type)',
]
lines += [f'- {r}' for r in routes] or ['- (unknown type; run master-route with a task hint)']
lines += ['', '## Keyword route (master-route)', f'- hint: {hint}', f'- primary: {keyword_id} ({keyword_skill})',
          '', '## Tools for suggested skills',
          f"- available: {', '.join(tools_ok) if tools_ok else '(none resolved)'}",
          f"- missing: {', '.join(tools_missing) if tools_missing else '(none)'}",
          '', '## Next actions',
          '1. case-init (auth gate) before touching any network target',
          '2. open PRIMARY SKILL.md from the routes above',
          '3. missing tools -> bootstrap-reverse (manifest only)']
report = pathlib.Path(out_dir) / 'triage.md'
report.write_text('\n'.join(lines) + '\n', encoding='utf-8')

print(f'=== quick-triage: {p.name} ===')
print(f'class={file_class}')
print(f'sha256={sha256(p)}')
print(f'type-routes: {",".join(routes)}')
if hint: print(f'hint-route : {keyword_id} ({keyword_skill})')
print(f'tools ok={len(tools_ok)} missing={len(tools_missing)}')
print(f'report -> {report}')
PY
