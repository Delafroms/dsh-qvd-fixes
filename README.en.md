# DeepSeek Harness QVD Security Patch & Verification Script (0.1.2-alpha.2)

[简体中文](README.md) | English

| Item | Value |
|---|---|
| Target | DeepSeek Harness 0.1.2-alpha.2 |
| Status | Community patch (unofficial) |
| Scope (source fixes) | QVD-2026-52631 / 52632 / 52644 / 52646 |
| Upstream-fixed | QVD-2026-57410 |

This repository provides a **community patch** and verification script for publicly disclosed vulnerabilities in DeepSeek Harness, based on the upstream **0.1.2-alpha.2** baseline. **Four vulnerabilities (52631 / 52632 / 52644 / 52646) have source-code fixes**; **57410 is a version verification of the already-existing fix in this baseline — this repository does not modify it**.

> This repository is **not an official security update, and not a full security audit**; it does not guarantee the absence of other undiscovered, uncovered, or version-related issues.

## Quick Start

1. Confirm your DSH checkout is based on **0.1.2-alpha.2**;
2. Download `fixes.patch` and `verify-dsh-fixes.bat`;
3. Run `verify-dsh-fixes.bat` to inspect the current fix status;
4. `git apply --check fixes.patch` to dry-run the patch;
5. After review, `git apply fixes.patch` to apply.

## Contents

| File | Description |
|---|---|
| `fixes.patch` | Unified diff against 0.1.2-alpha.2; fixes 52631/52632/52644/52646 (15 files, +668 / −44). 57410 is already fixed upstream, no change here |
| `FIXES.md` | Per-vulnerability explanation, affected files, apply/verify instructions (Chinese) |
| `verify-dsh-fixes.bat` | Read-only Windows verification script (static marker checks; optional regression tests / rebuild) |
| `README.md` | Chinese README |
| `README.en.md` | This English README |
| `LICENSE` | MIT |

## ⚠️ Safety & responsibility

- `verify-dsh-fixes.bat` is a **read-only** script: no network, no download, no execution of external programs, no system modification. Optional `-tests` / `-build` only invoke `pnpm` on your own machine and require a manual `Y` confirmation.
- Applying `fixes.patch` is your choice: `git apply fixes.patch` modifies DSH source; run `git apply --check` first and back up.
- Everything is provided **AS-IS**; the MIT license disclaims liability (see `LICENSE`). Verify in a test environment first.
- This repository is **not affiliated with DeepSeek**; it is not an official fix or release. Refer to the upstream repository.

## The five vulnerabilities

| QVD | CVSS | Handling here |
|---|---|---|
| QVD-2026-52646 | 10.0 (Critical) | Source fix |
| QVD-2026-57410 | 9.8 (Critical) | Version verification (already in baseline) |
| QVD-2026-52644 | High (no exact number published) | Source fix |
| QVD-2026-52631 | 7.8 (High) | Source fix |
| QVD-2026-52632 | 7.5 (High) | Source fix (process-level read gap remains) |

> Scores come from QAX CERT disclosure and CN-SEC coverage. For 52644 only "High" was published without an exact number; no number is invented here.

### QVD-2026-52631 — loader config expression injection (CVSS 7.8)
- **Cause**: the loader evaluated `!!js` expressions in `cordis.yml` via `with (ctx) { eval(expr) }` wrapped in `new Function`; the expression fell through `ctx` to the host global scope, reaching `process` / `require` / `module`.
- **Consequences**: once an attacker can plant a malicious `!!js` in `cordis.yml` / `cordis.patch.yml` (e.g. by tricking a user into cloning a malicious repo or applying a tampered profile), it runs **synchronously as arbitrary Node code with host-process privileges** at load time — reading files, running commands, stealing API keys from environment variables — and, via HMR watching, can persist as a "write-once, replayed-every-start" backdoor. Prerequisite: the attacker must first be able to deliver or write the malicious config; this is not a one-click remote trigger.
- **Fix**: `node:vm` isolated evaluation; context crosses as one JSON string and is rebuilt inside the vm (zero host-object injection); `process` exposes only `env/platform/arch/version/execPath/cwd` and `getBuiltinModule('node:url')`; `runInContext(..., { timeout: 1000 })` bounds runtime.

### QVD-2026-52632 — fs-sandbox read escape (CVSS 7.5)
- **Cause**: `fs-sandbox` constrained only writes; reads could escape the workspace.
- **Consequences**: information disclosure. In-process: the model can read arbitrary paths outside the workspace; process-level: a confined shell subprocess can read the entire host filesystem. An attacker can steal `~/.ssh` private keys, `.env`, cloud credentials, API keys, and other project sources. It does not directly write files or run commands, but the stolen credentials enable lateral movement or further intrusion.
- **Fix**: `readText` / `streamText` / `readBytes` now validate the target against policy at the execution point and throw structured `FS_SANDBOX_DENIED`; `tool-fs` resolves the session policy and passes it in, mapping denials via `mapError`.
- **Known gap**: this patch only narrows the **in-process** read path. The **process-level** sandbox backends (bwrap `--ro-bind / /`, landlock `readOnly: ['/']`, seatbelt allow-default) still expose the entire host filesystem read-only to confined shell subprocesses. See `FIXES.md` "已知残留与限制".

### QVD-2026-52644 — cordis sandbox tool escape (CVSS High)
- **Cause**: the `execute` of a sandbox-defined tool received the real execution context carrying `agent` / `ctx` / `session` objects.
- **Consequences**: a key step of sandbox escape. Model code reaches the real runtime `Context` via `exec.agent.ctx`, escalating from "restricted vm code execution" to "access to host services (including secret storage)". It is typically one link in an attack chain, combined with 52646 to reach host RCE.
- **Fix**: a whitelisted `sandboxToolExec` execution view exposing only `name` / `callId` / `arguments` (JSON clone) / `signal`.

### QVD-2026-52646 — bash/pwsh subprocess escape (CVSS 10.0)
- **Cause**: under a confined policy bash/pwsh could still spawn directly, bypassing the sandbox.
- **Consequences**: the most severe — a chained path to **arbitrary command execution on the host**. Full chain: indirect prompt injection → induce the model to call `cordis_define` + `cordis_run` → vm escape to the host exec → unconstrained `subprocess.spawn` → run arbitrary commands with the DSH process's privileges (public demos reached root). Under the default composition it does not depend on any deployment misconfiguration.
- **Fix**: `SubprocessSpawnSpec` gains `sandboxPolicy` and `argvConfined`; `subprocess-local` enforces `assertConfinedUnderPolicy` at the spawn execution point (a confined policy without `argvConfined` is refused); `bash-local` / `pwsh-local` stamp `argvConfined: true` when confined.

### QVD-2026-57410 — unauthorized access / forged Host (CVSS 9.8, version verification, not fixed here)
- **Cause**: historical versions lacked browser-session auth; a forged Host header or missing credential could access the API.
- **Consequences**: **unauthenticated remote code execution**. An attacker forges the Host header to unlock privileged RPC, registers a temporary LLM provider pointing at their own fake model server, and drives the bash tool with deterministic tool calls — **no real model and no valid API key required** — to run commands on an instance exposed to the network (public PoCs obtain a root shell). Prerequisite: the service must be reachable on a non-loopback network; a `127.0.0.1`-only listener is not directly threatened by this path.
- **Handling**: audit confirms 0.1.2-alpha.2 already ships browser-token session auth (launch token + signed cookie + 401/403 gate). This repository does **not** modify that file; it only records the existing auth implementation in this baseline.

## What running verify-dsh-fixes.bat does

- **Read-only**: matches fix markers in the source with `findstr`, prints `[PASS]` / `[FAIL]`.
- **Three outcomes**: all `[PASS]` → exit 0; some `[FAIL]` → exit 1 (prints only, changes nothing); no checkout found → exit 2 (no side effect).
- **Locating the checkout**: the script's own directory if it contains `package.json`; else env `DSH_REPO`; else a hardcoded local fallback path.
- **Optional `-tests` / `-build`**: require a manual `Y` and invoke `pnpm` on your own machine. Missing `pnpm`/deps just fails with an error, nothing is broken.
- No network, no upload, no download, no external program execution.

## What applying fixes.patch does

```bat
git apply --check fixes.patch   rem verify only, no change
git apply fixes.patch           rem apply
git apply -R fixes.patch        rem revert
```

- Matching version (0.1.2-alpha.2 with the same structure) → 15 source files are modified.
- Mismatched version → `git apply` fails the check and writes **nothing**.
- The patch uses LF endings; on Windows CRLF checkouts, use `git apply --ignore-whitespace fixes.patch` if it reports `does not apply`.

## Usage

1. Verify: run `verify-dsh-fixes.bat` at the DSH checkout root (or `set DSH_REPO=<path>` then run).
2. Optional regression/rebuild: `verify-dsh-fixes.bat -tests` or `-build` (needs `pnpm` + deps).
3. Apply: `git apply --check fixes.patch` → `git apply fixes.patch` on a 0.1.2-alpha.2-based checkout.

## Not covered: indirect prompt injection

Indirect prompt injection is an **inherent model-level risk** that **cannot be eliminated by a code patch**. Tencent Zhuque Lab's controlled 14,560-run evaluation (2026-08) shows DSH's baseline defense against it is still early-stage (~5.3% full success): untrusted web pages, documents, email, Skills, PDF metadata, hidden Unicode, etc. can induce the model to invoke sensitive tools.

This patch only closes the code/sandbox/auth vulnerabilities of the five QVDs; it does **not** address prompt injection. Mitigation is operational only: treat all external content as untrusted, keep sensitive actions human-approved, run with least privilege, process untrusted content in an isolated container/VM.

Reference: Tencent Zhuque Lab, "A.I.G Red Team on DeepSeek Harness" — https://matrix.tencent.com/zh/2026/08/20/deepseek-harness-agent-injection-risk

## Security advice

- **Plugins are code**: do not load plugins from unknown or unreviewed sources.
- **Web/search content is untrusted**: be wary of content returned by fetch/search tools; it may steer later actions.
- **Stay local**: bind DSH Web to `127.0.0.1`, never `0.0.0.0`.
- **Use official sources only**.
- **Prefer official fixes**: this patch targets 0.1.2-alpha.2; later official releases may already fix these, check the official changelog.
- **Read-only mode does not protect secrets**: this patch narrows in-process reads, but process-level sandboxes still expose the whole host read-only to confined shells; move `.ssh`, `.env`, and cloud credentials out of agent-readable directories.
- Run `--check` and verify in a test environment before applying.

## File checksums (tamper check)

```bat
certutil -hashfile "verify-dsh-fixes.bat" SHA256
certutil -hashfile "fixes.patch" SHA256
certutil -hashfile "FIXES.md" SHA256
certutil -hashfile "LICENSE" SHA256
```

| File | SHA-256 |
|---|---|
| `verify-dsh-fixes.bat` | `CC35A3D559D7E271DB55DAD5D7E1582DDA437FFD0D3B4E851DE4A379221E11CE` |
| `fixes.patch` | `727290C97B539F4988A83803A6B4AE5E9F44F10FC1DC5D8A0981F466D3F13D0E` |
| `FIXES.md` | `15A371BCBD1FCB60A76E38CA9D3172EE525FDEEAFEA41540C721B11B95CB90B7` |
| `LICENSE` | `B546772903BAEBAFB411FD4A5E1A5B91855659BF38C56165A7096712615C8AF9` |

Notes:
- The READMEs (`README.md` / `README.en.md`) are excluded from the table because their hash would be written inside the files themselves, which cannot prove the files unmodified; rely on the independent files `verify-dsh-fixes.bat`, `fixes.patch`, `FIXES.md`, `LICENSE` instead.
- The script does not self-verify: embedding its own hash is self-referential, and an attacker could patch the check too; so we publish the values and use `certutil` to compare manually.
- Update this table whenever a file changes.

## License & attribution

- Scripts and documentation in this repository: MIT License, copyright **Delafroms** (see `LICENSE`).
- DeepSeek Harness upstream: MIT License (© its authors). The patch modifies upstream MIT code; keep the upstream copyright notice and mark your modifications, and do not claim upstream code as your own.
- Distribute only this patch and documentation; do not repackage the whole DSH checkout or `node_modules`.

## References

- DeepSeek Harness upstream: https://github.com/deepseek-ai/DeepSeek-Harness
- Per-vulnerability details: `FIXES.md` (Chinese).
