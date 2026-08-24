#!/usr/bin/env bash
# reverse-skill-pro: resume an existing case (bash twin of case-resume.ps1).
# Usage:
#   bash skills/scripts/case-resume.sh --case-root work/my-case [--last 5]
set -euo pipefail

CASE_ROOT=""
LAST=5
PROJECT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -CaseRoot|-case-root|--case-root) CASE_ROOT="${2:-}"; shift 2 ;;
    -Last|-last|--last) LAST="${2:-5}"; shift 2 ;;
    -ProjectRoot|-project-root|--project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
    -h|--help) echo 'Usage: case-resume.sh --case-root DIR [--last N]'; exit 0 ;;
    *) echo "Unknown arg: \"$1\"" >&2; exit 2 ;;
  esac
done

if [[ -z "$CASE_ROOT" ]]; then echo 'ERROR: --case-root required' >&2; exit 2; fi
if [[ ! -d "$CASE_ROOT" && -n "$PROJECT_ROOT" ]]; then CASE_ROOT="$PROJECT_ROOT/work/$CASE_ROOT"; fi
if [[ ! -f "$CASE_ROOT/scope.md" ]]; then
  echo "ERROR: not a valid case (missing scope.md): $CASE_ROOT" >&2
  exit 2
fi

PYTHON=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then PYTHON="$candidate"; break; fi
done
if [[ -z "$PYTHON" ]]; then echo 'ERROR: Python 3 required' >&2; exit 2; fi

"$PYTHON" - "$CASE_ROOT" "$LAST" <<'PY'
import pathlib, re, sys

case_root, last_n = pathlib.Path(sys.argv[1]), int(sys.argv[2])
scope = (case_root / 'scope.md').read_text(encoding='utf-8')

def field(name):
    m = re.search(rf'(?m)^-\s*{re.escape(name)}:\s*(.+)$', scope)
    return m.group(1).strip() if m else ''

auth = field('status') or '?'
ready = field('ready_for_act') or '?'
net = field('mode') or '?'
preset = field('preset') or 'none'
primary_id = field('primary_id')
primary_skill = field('primary_skill')
case_id = field('case_id')

print(f'=== case-resume: {case_id or case_root.name} ===')
print(f'auth={auth} ready_for_act={ready} network={net} preset={preset}')
print(f'primary={primary_id} ({primary_skill})')

wi_total = wi_open = wi_done = 0
wi_open_ids = []
wi_path = case_root / 'workitems.md'
if wi_path.exists():
    for line in wi_path.read_text(encoding='utf-8').splitlines():
        m = re.match(r'^\|\s*(WI-\d+)\s*\|', line)
        if m:
            wi_total += 1
            if re.search(r'\|\s*(open|in_progress|pending)\s*\|', line):
                wi_open += 1; wi_open_ids.append(m.group(1))
            elif re.search(r'\|\s*(done|closed|complete)\s*\|', line):
                wi_done += 1
print(f'workitems: total={wi_total} open={wi_open} done={wi_done}')

ev_dir = case_root / 'evidence'
ev = sorted([p.stem for p in ev_dir.glob('E-*.md')]) if ev_dir.exists() else []
findings = 0
fpath = case_root / 'findings.md'
if fpath.exists():
    findings = len(re.findall(r'(?m)^##\s+F-', fpath.read_text(encoding='utf-8')))
print(f'evidence: {len(ev)} items   findings: {findings}')

tl_path = case_root / 'timeline.md'
if tl_path.exists():
    tl = tl_path.read_text(encoding='utf-8')
    entries = re.findall(r'(?ms)^## (.+?)$(.*?)(?=^## |\Z)', tl)
    print(f'--- last {min(last_n, len(entries))} timeline entries ---')
    for head, body in entries[-last_n:]:
        action = re.search(r'(?m)^-\s*action:\s*(.+)$', body)
        nxt = re.search(r'(?m)^-\s*next:\s*(.+)$', body)
        delta = re.search(r'(?m)^-\s*decision_delta:\s*\[(.*)\]', body)
        print(f'[{head.strip()}] {action.group(1).strip() if action else ""}')
        if delta: print(f'    delta: {delta.group(1).strip()}')
        if nxt: print(f'    next : {nxt.group(1).strip()}')

print('--- NEXT ACTIONS ---')
if auth != 'granted':
    print('1. auth NOT granted -> fill scope.md auth + in_scope first (MUST before ACT)')
elif ready != 'true':
    print('1. complete signoff checklist -> set ready_for_act=true')
else:
    print(f'1. continue PRIMARY skill: skills/{primary_skill}')
if wi_open_ids:
    print(f'2. finish open workitems: {", ".join(wi_open_ids)}')
if ev:
    print(f'3. evidence on file: {", ".join(ev[:8])}')
else:
    print('3. no evidence yet -> append via skills/scripts/append-evidence.ps1 as you progress')
print('4. on completion: docs-generator report + field-journal write-back')
PY
