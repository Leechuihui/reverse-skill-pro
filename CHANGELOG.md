# Changelog

All notable changes to **reverse-skill-pro** are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

## [2.0.0] — 2026-08-24

Enhanced distribution of the reverse-skill skill router pack (based on reverse-skill v1.0.1, MIT).
All v1.0.1 contracts remain compatible: routing.json single source of truth, scope hard gate,
Evidence→Finding→Path, coherence verification.

### Added — New skills (R45–R48)
- **`fuzzing/`** — end-to-end coverage-guided fuzzing: AFL++/libFuzzer/honggfuzz/WinAFL/boofuzz/syzkaller
  selection matrix, harness templates with self-check list, seed/dictionary strategy, crash triage with
  ASan backtrace reading, Evidence conventions (`references/fuzzing-playbook.md`)
- **`emulation/`** — unidbg/Qiling/Unicorn user-mode emulation: so/JNI algorithm recovery with env-patching
  loop, anti-emulation countermeasures (fake maps / clock hook / CRC patch), bare-function Unicorn template,
  Qiling PE notes (`references/emulation-cookbook.md`)
- **`crypto-analysis/`** — crypto analysis & attacks: identification trio (encoding probe / entropy / block
  structure), RSA attack family (common factor / common modulus / Wiener / Coppersmith), padding oracle,
  PRNG recovery, classical cipher quick reference, ECC entry points (`references/attack-matrix.md`)
- **`stego-analysis/`** — stego detection & extraction: five-step static check, image/audio/document
  branches, PNG dimension CRC brute-force script, WAV LSB extraction script, encrypted-container branch
  (`references/toolchain.md`)

### Added — Automation
- **`scripts/quick-triage.ps1` / `quick-triage.sh`** — one-shot artifact triage: magic-byte detection →
  file class → type-based route suggestions → master-route keyword routing → tool-index availability check
  → `work/quick-triage-<ts>/triage.md`
- **`scripts/case-resume.ps1` / `case-resume.sh`** — case resume: parses scope/timeline/workitems/evidence
  state, prints auth-gate status, recent timeline entries (decision_delta + next), open workitems, and a
  deterministic next-action list
- **`config/mcp-presets.json`** — MCP preset profiles: transport/health_check/parallel_safe wiring info for
  8 common security MCPs plus opencode / Claude Desktop config snippets; installation still goes through
  the bootstrap-manifest supply-chain pin gate
- **`references/parallel-orchestration.md`** — parallel sub-agent orchestration templates: RE three-way
  fan-out / recon fan-out / CTF dual-track, with sub-agent task cards, merge protocol, and anti-patterns

### Changed — Routing expansion (43 → 47 rules; benchmark 173 → 189 cases)
- `config/routing.json`: added R45(fuzzing)/R46(emulation)/R47(crypto-analysis)/R48(stego-analysis) with a
  synchronized priority array; R46 keywords carry so/jni/native context constraints so the generic
  "gdb angr unicorn" case still routes to R0
- `MASTER-ROUTING.md` priority table kept 1:1 with JSON (verify-routing-coherence green)
- `routing.md` / `routing_zh.md`: new rows across domain table, by-intent table, and tool mapping table
- `skills/SKILL.md`: master module table extended with the four new modules
- `INDEX.md` regenerated via extract-summaries.ps1 (48 modules)
- Routing regression benchmark extended with 16 cases (4 per new route, bilingual); 189/189 green

### Removed
- Upstream project branding assets, sponsor materials, community links, star-history tooling, and internal
  review/release-process documents that are not part of the runtime skill pack
