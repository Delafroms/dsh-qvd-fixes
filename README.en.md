# DeepSeek Harness — QVD community fixes, red team & verification

[简体中文](./README.md) | English

| | |
|---|---|
| Target | DeepSeek Harness **0.1.2-alpha.2** (baseline patch) + **0.1.5-rc.2** (consolidated patch) |
| Nature | **Community patch — not an official security update** |
| Source fixes | QVD-2026-52631 / 52632 / 52644 / 52646 |
| Partially fixed | QVD-2026-57410 (upstream token + our transport fence) |
| Adversarial testing | 33 red-team cases across 3 suites |

> The Chinese [README.md](./README.md) carries more per-vulnerability detail; this page is a complete but condensed mirror.

## 30-second version

| Question | Answer |
|---|---|
| What is this | Community patches, adversarial tests and verification scripts for publicly disclosed DeepSeek Harness vulnerabilities. Not official, not a full audit. |
| Which patch do I apply | **0.1.5-rc.2 → `fixes-0.1.5-rc.2.patch`** (single self-consistent diff). 0.1.2-alpha.2 → `fixes.patch`. |
| How | Run `apply-dsh-fixes.bat` (pre-checks, asks, then writes), or manually `git apply --check` → `git apply`. |
| How do I verify | Run `verify-dsh-fixes.bat` (read-only, offline), then `-tests` for the regression suite. |
| What is fixed | 52631 / 52632 / 52644 / 52646 have source fixes; 57410 is partially fixed upstream (browser token) and we add the TCP-peer fence. |
| What is *not* fixed | Hardlink bypass, process-level sandbox read surface, 52631 env projection — see [REDTEAM.md](./REDTEAM.md). |
| What not to expect | It does **not** solve indirect prompt injection, and it does **not** prove the absence of other issues. |

## Repository contents

| File | Purpose |
|---|---|
| `fixes-0.1.5-rc.2.patch` | **Consolidated patch for 0.1.5-rc.2** (48 files, +2114 / −74). Recommended for 0.1.5 users. |
| `fixes.patch` | Unified diff against **0.1.2-alpha.2** (15 files, +668 / −44). Kept for 0.1.2 users and historical audit. |
| `code-runtime-isolation.patch` | Fix for an **unreported** isolation gap in the `run_code` runtime. Do not redistribute before vendor review. |
| `apply-dsh-fixes.bat` | One-click apply: locate checkout → `--check` → confirm → apply. |
| `verify-dsh-fixes.bat` | Read-only marker verification (20 checks; optional `-tests` / `-build`). |
| `ATTACK-CHAIN.md` | **Attack chains mapped to patches and test cases** (7 chains, with a cross-reference table). |
| `REDTEAM.md` | Red-team report: results, known bypasses, unverified boundaries. |
| `FIXES.md` | Per-vulnerability detail, affected files, apply and verify steps. |
| `redteam-suites.patch` | 33 adversarial test cases (3 suites). |
| ~~`qvd-2026-*.patch`~~ | The five per-vulnerability patches were folded into `fixes-0.1.5-rc.2.patch` and removed on 2026-09-23. Their design notes remain in FIXES.md. |
| `LICENSE` | MIT. |

## Important: `fixes.patch` does not apply to a clean 0.1.5-rc.2

Measured on a pristine `git archive` export, five files fail with `patch does not apply`:
`packages/fs/fs/src/index.ts`, `packages/fs/tool-fs/src/read.ts`, `packages/fs/tool-fs/src/read-image.ts`,
`packages/subprocess/subprocess-local/src/spawn.ts`, `packages/subprocess/subprocess-local/tests/spawn.spec.ts`.

Upstream changed those files between 0.1.2 and 0.1.5 (for example `read.ts` gained the word "scope-aware" in a comment).
It is **not** a line-ending problem — `--ignore-whitespace` and `-C1` do not help.

**Use the consolidated patch instead:**

```bat
git apply --check fixes-0.1.5-rc.2.patch
git apply       fixes-0.1.5-rc.2.patch
```

The consolidated patch is content-equivalent to baseline + the five supplementary patches, but **self-consistent** — it cannot leave you with the old fail-open spawn guard installed.

## Vulnerabilities

| QVD | CVSS | Handling in this repository |
|---|---|---|
| QVD-2026-52646 | 10.0 | Source fix + fail-closed hardening (found by red team) |
| QVD-2026-57410 | 9.8 | **Partial** — upstream added a token; we add the TCP peer fence |
| QVD-2026-52644 | High (no official score) | Source fix |
| QVD-2026-52631 | 7.8 | Source fix (**env projection still open**) |
| QVD-2026-52632 | 7.5 | Source fix (**process-level read surface and hardlink bypass remain**) |

Scores come from the QiAnXin CERT disclosure and CN-SEC relays. No number is invented for 52644.

## Red team summary

| Suite | Cases | Result |
|---|---|---|
| Read-fence adversarial | 16 | 14 blocked / **1 known bypass (hardlink)** / 1 current behavior |
| Confined-spawn adversarial | 13 | 13 blocked (after the fail-open fix) |
| Agent-loop termination | 4 | 4 passed |

All 33 cases attack **this repository's own patches**. See [REDTEAM.md](./REDTEAM.md) and [ATTACK-CHAIN.md](./ATTACK-CHAIN.md).

## Checksums (SHA-256)

| File | SHA-256 |
|---|---|
| `fixes.patch` | `727290C97B539F4988A83803A6B4AE5E9F44F10FC1DC5D8A0981F466D3F13D0E` |
| `fixes-0.1.5-rc.2.patch` | `9A2FA061BE21B3BE4CFB98CD3F7ACCA0741C4DDBF71EF1503D6FF06BB9A4ABF5` |
| `code-runtime-isolation.patch` | `C85FC4E4318B638F8F6D83FFCF67B60CE21661E76032342865AEA32945E59C66` |

Verify with `certutil -hashfile <file> SHA256`. README files are excluded from the table on purpose: a hash printed inside a file cannot prove that file is unmodified.

## Not covered: indirect prompt injection

Indirect prompt injection is an inherent **model-level** risk that no code patch removes. Tencent Zhuque Lab's 14,560 controlled trials (2026-08) show DSH's baseline defenses against such attacks are still early (full success ≈5.3%). This repository closes the five QVD code/sandbox/auth issues only.

## Security recommendations

- **Plugins are code**: do not load unreviewed plugins — they run in the host process.
- Treat web/search content as untrusted; keep human approval on sensitive operations.
- Keep DSH Web bound to `127.0.0.1`; never expose it to a LAN or the internet.
- Do not rely on read-only mode to protect secrets: move `.ssh`, `.env` and cloud credentials out of agent-readable directories, and **keep them on a different volume** than the workspace (hardlink mitigation).
- Apply patches with `--check` first, in a test environment.

## License and attribution

- Scripts and documentation in this repository: MIT, copyright **Delafroms** — see `LICENSE`.
- DeepSeek Harness upstream: MIT, © its authors. These patches modify upstream MIT sources; keep the upstream notices and mark the modifications.
- This repository is **not affiliated with DeepSeek** and is not an official fix.

## References

- Upstream: https://github.com/deepseek-ai/DeepSeek-Harness
- Attack chains: [ATTACK-CHAIN.md](./ATTACK-CHAIN.md)
- Per-vulnerability detail: [FIXES.md](./FIXES.md)
- Red team report: [REDTEAM.md](./REDTEAM.md)
- Public PoC collections: https://github.com/Unclecheng-li/poc-lab
- Tencent Zhuque Lab, A.I.G red-team report on DeepSeek Harness: https://matrix.tencent.com/zh/2026/08/20/deepseek-harness-agent-injection-risk
