# DeepSeek Harness QVD Security Patches, Red-Team Tests & Verification Script

[简体中文](README.md) | English

| Item | Value |
|---|---|
| Target | DeepSeek Harness **0.1.2-alpha.2** (baseline) + **0.1.5-rc.2** (supplementary patches) |
| Status | Community patch (unofficial) |
| Scope (source fixes) | QVD-2026-52631 / 52632 / 52644 / 52646 |
| Partially-fixed | QVD-2026-57410 |
| Adversarial validation | 33 red-team cases across 3 suites |

This repository provides **community patches**, **adversarial tests**, and a verification script for publicly disclosed vulnerabilities in DeepSeek Harness.

- **Baseline patch** (`fixes.patch`) targets upstream **0.1.2-alpha.2** and fixes 52631 / 52632 / 52644 / 52646.
- **Supplementary patches** (5) target **0.1.5-rc.2**: upstream fixed **none** of the QVDs across the 0.1.2 → 0.1.5 range, and 57410 is only **partially** fixed. The supplementary patches close the remaining surface plus defects found by red-teaming.
- **Red-team suites** (33 cases) actively attempt to bypass this repository's own patches. Results and known bypasses are in [REDTEAM.md](./REDTEAM.md).

> This repository is **not an official security update, and not a full security audit**; it does not guarantee the absence of other undiscovered, uncovered, or version-related issues. **Known bypasses and unverified boundaries are listed explicitly in `REDTEAM.md` — nothing is hidden.**

## Quick Start

**Baseline (0.1.2-alpha.2):**

1. Confirm your DSH checkout is based on **0.1.2-alpha.2**;
2. Download `fixes.patch` and `verify-dsh-fixes.bat`;
3. Run `verify-dsh-fixes.bat` to inspect the current fix status;
4. `git apply --check fixes.patch` to dry-run the patch;
5. After review, `git apply fixes.patch` to apply.

**Supplementary patches (0.1.5-rc.2):** see [Supplementary patches for 0.1.5-rc.2](#supplementary-patches-for-015-rc2) below.

## Contents

| File | Description |
|---|---|
| `fixes.patch` | Unified diff against 0.1.2-alpha.2; fixes 52631/52632/52644/52646 (15 files, +668 / −44). **Note: its `assertConfinedUnderPolicy` is the older version with the fail-open defect — on 0.1.5 you must also apply supplementary patch 4** |
| `qvd-2026-57410-transport-fence.patch` | Supplementary: TCP peer check (a loopback Host from a non-loopback peer is refused) |
| `qvd-2026-52632-editor-read-fence.patch` | Supplementary: `tool-str-replace-editor`'s `view` now carries a read policy |
| `qvd-2026-52632-plugin-fs-fence.patch` | Supplementary: dynamic-plugin fs façade forces the session policy |
| `qvd-2026-52646-confined-spawn-fail-closed.patch` | Supplementary: confined-spawn guard made fail-closed (red-team finding) |
| `guard-repeat-text-reminder.patch` | Supplementary: new repeat-text guard package |
| `redteam-suites.patch` | 33 adversarial cases across 3 suites |
| `REDTEAM.md` | Red-team report: attack results, known bypasses, unverified boundaries (Chinese) |
| `FIXES.md` | Per-vulnerability explanation, affected files, apply/verify instructions (Chinese) |
| `verify-dsh-fixes.bat` | Read-only Windows verification script (20 checks; optional regression tests / rebuild) |
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
| QVD-2026-52646 | 10.0 (Critical) | Source fix + **fail-closed hardening** (red-team finding) |
| QVD-2026-57410 | 9.8 (Critical) | **Partially fixed**: upstream added a token; this repo adds the TCP peer check |
| QVD-2026-52644 | High (no exact number published) | Source fix |
| QVD-2026-52631 | 7.8 (High) | Source fix (**env projection gap remains**, see below) |
| QVD-2026-52632 | 7.5 (High) | Source fix (**process-level read gap and hardlink bypass remain**) |

> Scores come from QAX CERT disclosure and CN-SEC coverage. For 52644 only "High" was published without an exact number; no number is invented here.

### QVD-2026-52631 — loader config expression injection (CVSS 7.8)
- **Cause**: the loader evaluated `!!js` expressions in `cordis.yml` via `with (ctx) { eval(expr) }` wrapped in `new Function`; the expression fell through `ctx` to the host global scope, reaching `process` / `require` / `module`.
- **Consequences**: once an attacker can plant a malicious `!!js` in `cordis.yml` / `cordis.patch.yml` (e.g. by tricking a user into cloning a malicious repo or applying a tampered profile), it runs **synchronously as arbitrary Node code with host-process privileges** at load time — reading files, running commands, stealing API keys from environment variables — and, via HMR watching, can persist as a "write-once, replayed-every-start" backdoor. Prerequisite: the attacker must first be able to deliver or write the malicious config; this is not a one-click remote trigger.
- **Fix**: `node:vm` isolated evaluation; context crosses as one JSON string and is rebuilt inside the vm (zero host-object injection); `process` exposes only `env/platform/arch/version/execPath/cwd` and `getBuiltinModule('node:url')`; `runInContext(..., { timeout: 1000 })` bounds runtime.
- **Residual (not closed — architectural limit)**: inside the vm, `process.env` is a **full projection** (`env: process.env`), so `!!js process.env.<KEY>` can read any environment variable. The vm has no network and no filesystem, but a value can be carried out through a thrown error (visible in logs / UI), forming a complete exfiltration chain.
  **The threat model is worse than the original description**: it does not require tricking a user into pasting config — **installing one third-party plugin is enough** (a bundle-layer `cordis.patch.yml` comes from an npm package and can equally contain `!!js`).
  **Why this repository cannot fix it**: source-layered projection needs provenance, and provenance is dropped at `composeEntries`' `layers.flat()` (`EntryOptions` carries no source field). Preserving it requires a data-structure change across three packages, and **getting it wrong breaks profile composition entirely — DSH would not start**. This needs an upstream "config provenance trust" model. See `FIXES.md`.

### QVD-2026-52632 — fs-sandbox read escape (CVSS 7.5)
- **Cause**: `fs-sandbox` constrained only writes; reads could escape the workspace.
- **Consequences**: information disclosure. In-process: the model can read arbitrary paths outside the workspace; process-level: a confined shell subprocess can read the entire host filesystem. An attacker can steal `~/.ssh` private keys, `.env`, cloud credentials, API keys, and other project sources. It does not directly write files or run commands, but the stolen credentials enable lateral movement or further intrusion.
- **Fix**: `readText` / `streamText` / `readBytes` now validate the target against policy at the execution point and throw structured `FS_SANDBOX_DENIED`; `tool-fs` resolves the session policy and passes it in, mapping denials via `mapError`.
- **Supplementary fixes**:
  - `qvd-2026-52632-editor-read-fence.patch` — `tool-str-replace-editor`'s `view` command previously read files **without a policy** (its write path already had one); now fixed.
  - `qvd-2026-52632-plugin-fs-fence.patch` — the fs service a dynamic Cordis plugin reaches via `inject: ['fs']` passed reads through when no policy was supplied (the write path already defaulted to `resolve()`; **that read/write asymmetry was itself the defect**). The fence is applied at the **boundary where a dynamic plugin enters the system** (the `sandboxContext` façade), **without changing the host contract**.
- **Known gaps (not fixed)**:
  1. **Process-level read path**: bwrap `--ro-bind / /`, landlock `readOnly: ['/']`, and seatbelt allow-default still expose the entire host filesystem read-only to confined shell subprocesses. A read-only session's bash/pwsh can still read `~/.ssh`, `.env`, etc. **deferred — requires platform-specific validation** (needs Linux/macOS to verify the backends).
  2. **Hardlink bypass** (confirmed by red teaming): a hardlink inside the workspace pointing at an outside inode is **invisible to path-based containment**, and the read succeeds. Exploiting it requires the attacker to **already be able to create a hardlink inside the workspace** (i.e. an existing write primitive), so it is a limitation rather than a standalone hole. **Mitigation**: keep sensitive files off the same volume as the workspace (hardlinks cannot cross volumes).
  See `REDTEAM.md` and `FIXES.md`.

### QVD-2026-52644 — cordis sandbox tool escape (CVSS High)
- **Cause**: the `execute` of a sandbox-defined tool received the real execution context carrying `agent` / `ctx` / `session` objects.
- **Consequences**: a key step of sandbox escape. Model code reaches the real runtime `Context` via `exec.agent.ctx`, escalating from "restricted vm code execution" to "access to host services (including secret storage)". It is typically one link in an attack chain, combined with 52646 to reach host RCE.
- **Fix**: a whitelisted `sandboxToolExec` execution view exposing only `name` / `callId` / `arguments` (JSON clone) / `signal`.

### QVD-2026-52646 — bash/pwsh subprocess escape (CVSS 10.0)
- **Cause**: under a confined policy bash/pwsh could still spawn directly, bypassing the sandbox.
- **Consequences**: the most severe — a chained path to **arbitrary command execution on the host**. Full chain: indirect prompt injection → induce the model to call `cordis_define` + `cordis_run` → vm escape to the host exec → unconstrained `subprocess.spawn` → run arbitrary commands with the DSH process's privileges (public demos reached root). Under the default composition it does not depend on any deployment misconfiguration.
- **Fix**: `SubprocessSpawnSpec` gains `sandboxPolicy` and `argvConfined`; `subprocess-local` enforces `assertConfinedUnderPolicy` at the spawn execution point (a confined policy without `argvConfined` is refused); `bash-local` / `pwsh-local` stamp `argvConfined: true` when confined.
- **Supplementary fix (red-team finding)**: `qvd-2026-52646-confined-spawn-fail-closed.patch` — the original guard's `mode !== undefined` precondition let `sandboxPolicy: {}` (policy present, mode missing) **pass silently**, exactly the "policy silently degrades" case the guard exists to prevent. Now fail-closed: **once a policy is present, only the literal `danger-full-access` is exempt**.
  **Severity (honest assessment)**: `mode` is required by the type, so this is **input from outside the type system** — not a remotely triggerable vulnerability, but a **defense-in-depth gap**.

### QVD-2026-57410 — unauthorized access / forged Host (CVSS 9.8, **partially fixed**)
- **Cause**: privileged RPC decided "is this a local loopback caller?" from the **HTTP `Host` header alone**; `Host` is entirely client-controlled and trivially forged.
- **Consequences**: **unauthenticated remote code execution**. An attacker forges the Host header to unlock privileged RPC, registers a temporary LLM provider pointing at their own fake model server, and drives the bash tool with deterministic tool calls — **no real model and no valid API key required** — to run commands on an instance exposed to the network (public PoCs obtain a root shell). Prerequisite: the service must be reachable on a non-loopback network; a `127.0.0.1`-only listener is not directly threatened by this path.
- **Upstream handling (partial)**: 0.1.2+ ships browser-token session auth (launch token + signed cookie + 401/403 gate).
- **Residual (fixed by this repository)**: the trust decision **still has no transport input** — `ConnectionTrustRequest` carries only `headers`, and `BrowserAuth.authorizeIndex` (the token → cookie exchange) has **no peer check at all**. The upstream PoC's own remediation text says "validate the TCP `remoteAddress` rather than the `Host` header"; that was not adopted.
  **Meaning**: the token becomes the only line of defense. Once it leaks (URL in logs, Referer, a screenshot, a shared link), a forged `Host: 127.0.0.1` yields a browser cookie.
- **Supplementary fix**: `qvd-2026-57410-transport-fence.patch` — adds a **transport fence** (a loopback Host arriving over a non-loopback socket is refused) and gives the token exchange a peer check; new `trustedProxies` config (empty by default = strictest).

## What running verify-dsh-fixes.bat does

- **Read-only**: matches fix markers in the source with `findstr`, prints `[PASS]` / `[FAIL]` / `[SKIP]`.
- **Two classes of check**:
  - **Baseline** (11): a miss is `[FAIL]` and affects the exit code;
  - **Optional supplementary patches + red-team suites** (9): a miss is `[SKIP]` and does **not** count as failure — supplementary patches are optional increments, and not applying them says nothing about the baseline.
- **Three outcomes**: all baseline `[PASS]` → exit 0; some `[FAIL]` → exit 1 (prints only, changes nothing); no checkout found → exit 2 (no side effect).
- **Locating the checkout**: the script's own directory if it contains `package.json`; else env `DSH_REPO`; else two levels up.
- **Optional `-tests` / `-build`**: require a manual `Y` and invoke `pnpm` on your own machine. Missing `pnpm`/deps just fails with an error, nothing is broken.
- No network, no upload, no download, no external program execution.

> **Limit of static detection (important)**: `[PASS]` only means the **marker string is present**, not that the logic is correct — commented-out code contains the same string. The real evidence is the regression tests run by `-tests` and the adversarial results recorded in `REDTEAM.md`.

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

## Supplementary patches for 0.1.5-rc.2

> **⚠️ Read this first: `fixes.patch` and the supplementary patches target different versions and are not interchangeable.**
>
> | Patch set | Target | Note |
> |---|---|---|
> | `fixes.patch` | **0.1.2-alpha.2** | Unified diff against that version (15 files) |
> | 5 supplementary patches | **0.1.5-rc.2** | Independent; **cannot be merged into `fixes.patch`** |
>
> **Why they cannot be merged**: `fixes.patch` is a diff generated against 0.1.2-alpha.2; folding 0.1.5 content into it would make it inapplicable to 0.1.2.
>
> **⚠️ On 0.1.5-rc.2 you must apply "baseline → supplementary", in that order — the baseline alone is not enough.**
> Reason: the `assertConfinedUnderPolicy` inside `fixes.patch` is the **older version carrying the fail-open defect** (its `mode !== undefined` precondition lets `sandboxPolicy: {}` pass silently). **Applying only the baseline installs a defective guard**; supplementary patch 4 is the fail-closed version and **overwrites** the same function the baseline wrote.

After migrating the baseline patches to **0.1.5-rc.2** (the current npm `latest`), every public PoC attack surface for the five QVDs was **re-checked item by item**:

| QVD | 0.1.5-rc.2 status | Evidence |
|---|---|---|
| 52631 config-load RCE | still unfixed | `vendor/loader/src/config/utils.ts:5` is still `new Function + with(ctx){eval}` |
| 52632 read-only sandbox leak | still unfixed | `fs-sandbox/src/index.ts:7` still says "Reads pass through untouched" |
| 52644 VM sandbox escape | still unfixed | `guard.ts` still forwards `exec` verbatim to `rawExecute` |
| 52646 chained escape RCE | still unfixed | `spawn.ts` has no `argvConfined` / `assertConfinedUnderPolicy` |
| 57410 Host-header unauth RCE | **partially fixed** | a token was added, but the trust decision still has no transport input |

> **Upgrading the version does not mean the vulnerabilities are fixed.** On 0.1.5-rc.2 the baseline patches are **not legacy baggage — they are still required.**

**How to apply** (on a 0.1.5-rc.2 checkout, **in order — baseline first**):

```bat
rem 1) baseline first (diff against 0.1.2-alpha.2, still applies to 0.1.5)
git apply --check fixes.patch
git apply       fixes.patch

rem 2) then the 5 supplementary patches (any order; they do not overlap)
git apply --check qvd-2026-57410-transport-fence.patch
git apply       qvd-2026-57410-transport-fence.patch
git apply --check qvd-2026-52632-editor-read-fence.patch
git apply       qvd-2026-52632-editor-read-fence.patch
git apply --check qvd-2026-52632-plugin-fs-fence.patch
git apply       qvd-2026-52632-plugin-fs-fence.patch
git apply --check qvd-2026-52646-confined-spawn-fail-closed.patch
git apply       qvd-2026-52646-confined-spawn-fail-closed.patch
git apply --check guard-repeat-text-reminder.patch
git apply       guard-repeat-text-reminder.patch
```

**How the patches relate** (which ones overwrite the baseline):

| Supplementary patch | Relation to the baseline |
|---|---|
| `qvd-2026-52646-confined-spawn-fail-closed.patch` | **Overwrites** the `assertConfinedUnderPolicy` the baseline wrote (the old one has the fail-open defect) |
| `qvd-2026-52632-plugin-fs-fence.patch` | **Extends** the `guard.ts` the baseline modified (the baseline only added `sandboxToolExec`) |
| The other 3 | No overlap with the baseline; pure additions |

The patches are generated with LF endings; if a CRLF checkout reports `does not apply`, retry with `--ignore-whitespace`.

## Red-team testing (adversarial validation)

Full report: **[REDTEAM.md](./REDTEAM.md)** (Chinese). Summary:

| Suite | Cases | Result |
|---|---|---|
| Read-fence adversarial | 16 | 15 blocked / **1 known bypass (hardlink)** |
| Confined-spawn adversarial | 13 | 13 blocked (after the fail-open fix) |
| Agent-loop termination | 4 | 4 passed |
| **Total** | **33** | |

**Conclusion on the Agent Loop repetition**: with model/harness separation measured against a scripted adapter, a plain-text response (no tool-call block) results in **exactly one request** — the termination logic is correct and **this is not a harness state-machine defect**. The real gap was that **no guard covered plain-text repetition** (`repeat-tool-reminder` only observes `tools/post-execute`, so it needs a tool call to fire). `guard-repeat-text-reminder.patch` adds that layer.

**Test environment**: Windows 11 x64, non-administrator account. All attacks run only against temp directories, test files, canaries, and mock sinks, with **no external side effects**.

### Known bypasses (nothing hidden)

| Bypass | Impact | Status |
|---|---|---|
| **Hardlink to an outside inode** | Requires an existing workspace write primitive; same-volume secrets become readable | **Not fixed** |
| Policy-less reads pass through | Host contract; the plugin surface is covered by the `sandboxContext` fence | By design |
| `danger-full-access` is unfenced | That mode means "unrestricted" | By design |
| Process-level sandbox read path | A read-only session's shell can still read host files | **deferred** |
| 52631 env full projection | `!!js process.env.X` reads any environment variable | **Not fixed (architectural limit)** |

### Not yet verified (Unknown / Not Verified)

- Bypass attempts against the loader `!!js` vm isolation
- Repetition reproduction with a real model (not a scripted adapter)
- TOCTOU: the window for swapping a path between the fence check and the read
- Process-level sandbox backend behavior on Linux/macOS

> This repository does not write `Not Tested` as `Secure`, nor `Attack Not Observed` as `Attack Impossible`.

## Not covered: indirect prompt injection

Indirect prompt injection is an **inherent model-level risk** that **cannot be eliminated by a code patch**. Tencent Zhuque Lab's controlled 14,560-run evaluation (2026-08) shows DSH's baseline defense against it is still early-stage (~5.3% full success): untrusted web pages, documents, email, Skills, PDF metadata, hidden Unicode, etc. can induce the model to invoke sensitive tools.

This patch only closes the code/sandbox/auth vulnerabilities of the five QVDs; it does **not** address prompt injection. Mitigation is operational only: treat all external content as untrusted, keep sensitive actions human-approved, run with least privilege, process untrusted content in an isolated container/VM.

Reference: Tencent Zhuque Lab, "A.I.G Red Team on DeepSeek Harness" — https://matrix.tencent.com/zh/2026/08/20/deepseek-harness-agent-injection-risk

## Security advice

- **Plugins are code**: do not load plugins from unknown or unreviewed sources.
- **Web/search content is untrusted**: be wary of content returned by fetch/search tools; it may steer later actions.
- **Stay local**: bind DSH Web to `127.0.0.1`, never `0.0.0.0`.
- **Use official sources only**.
- **Prefer official fixes**: this patch targets 0.1.2-alpha.2 (supplementary patches target 0.1.5-rc.2); later official releases may already fix these, check the official changelog. **But note**: as of 0.1.5-rc.2 upstream fixed **none** of the QVDs, and 57410 only half — upgrading is not the same as being safe.
- **Read-only mode does not protect secrets**: this patch narrows in-process reads, but process-level sandboxes still expose the whole host read-only to confined shells; move `.ssh`, `.env`, and cloud credentials out of agent-readable directories, **and keep them off the same volume as the workspace** (hardlink bypass).
- **Do not expose DSH Web beyond loopback**: the residual 57410 surface means the token is the only line of defense, and a token can leak through logs, screenshots, or shared links.
- Run `--check` and verify in a test environment before applying.

## File checksums (tamper check)

```bat
certutil -hashfile "verify-dsh-fixes.bat" SHA256
certutil -hashfile "fixes.patch" SHA256
certutil -hashfile "FIXES.md" SHA256
certutil -hashfile "REDTEAM.md" SHA256
certutil -hashfile "LICENSE" SHA256
```

**Baseline and script:**

| File | SHA-256 |
|---|---|
| `verify-dsh-fixes.bat` | `6A0D8ECBF5B216347713A73D14437B3813FC043A2DB55685DD570EE9B731CD5B` |
| `fixes.patch` | `727290C97B539F4988A83803A6B4AE5E9F44F10FC1DC5D8A0981F466D3F13D0E` |
| `FIXES.md` | `D332DB66BDB47ECF2F13BD492D8328242367D300E78B154653F750CD35EED3E5` |
| `REDTEAM.md` | `A2BEAC9074F55517376481EBE5B4E768D19E6C39F162389021BEE12E45A03DF1` |
| `LICENSE` | `B546772903BAEBAFB411FD4A5E1A5B91855659BF38C56165A7096712615C8AF9` |

**Supplementary patches for 0.1.5-rc.2:**

| File | SHA-256 |
|---|---|
| `qvd-2026-57410-transport-fence.patch` | `280BE449C172D1165FD8BCF87F87F198E20293382CD948A00DD57B32A558C612` |
| `qvd-2026-52632-editor-read-fence.patch` | `81A7766AB9385125F45537482C8CB8883A6226A59627E39D841FDE6348B28531` |
| `qvd-2026-52632-plugin-fs-fence.patch` | `9DAD56A2603ADEB3BEDCE64DBB1996380471D16F1616BFD93F5D8BAC4A5EBFDC` |
| `qvd-2026-52646-confined-spawn-fail-closed.patch` | `B930F5E4F1AF615F9983588101CF84ECF3A1CD55F8E83D031DFE563DAE17D6F3` |
| `guard-repeat-text-reminder.patch` | `F9FD48F9D74132DD6879F9920FDC108532566D0189A1FB5CDB3502FC10E848E3` |
| `redteam-suites.patch` | `07C023D9C9B9859DF713C6F1777041F48E4BC06112E2FEAF19119994B2D552EB` |

Notes:
- The READMEs (`README.md` / `README.en.md`) are excluded from the table because their hash would be written inside the files themselves, which cannot prove the files unmodified; rely on the independent files instead.
- The script does not self-verify: embedding its own hash is self-referential, and an attacker could patch the check too; so we publish the values and use `certutil` to compare manually.
- Update this table whenever a file changes.

## License & attribution

- Scripts and documentation in this repository: MIT License, copyright **Delafroms** (see `LICENSE`).
- DeepSeek Harness upstream: MIT License (© its authors). The patch modifies upstream MIT code; keep the upstream copyright notice and mark your modifications, and do not claim upstream code as your own.
- Distribute only this patch and documentation; do not repackage the whole DSH checkout or `node_modules`.

## References

- DeepSeek Harness upstream: https://github.com/deepseek-ai/DeepSeek-Harness
- Per-vulnerability details: `FIXES.md` (Chinese)
- Red-team report: `REDTEAM.md` (Chinese)
- QVD PoC collection: https://github.com/Unclecheng-li/poc-lab
- Tencent Zhuque Lab, "A.I.G Red Team on DeepSeek Harness": https://matrix.tencent.com/zh/2026/08/20/deepseek-harness-agent-injection-risk
