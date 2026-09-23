# Security report — `run_code` code runtime is not confined by the session sandbox policy

| | |
|---|---|
| **Reporter** | Delafroms — heyyo520@qq.com |
| **Date** | 2026-09-23 |
| **Product** | DeepSeek Harness (dsh) |
| **Component** | `packages/code-runtime/code-runtime-worker-thread` (the `run_code` tool's runtime) |
| **Severity** | **Critical** — the vendor assigns CVSS; this report deliberately omits a score |
| **Status** | Not previously reported. No CVE requested by the reporter. |
| **Public disclosure** | None. The fix is published as a patch; this report is provided to the vendor first. |

---

## 1. Summary

The `run_code` tool executes model-authored code inside a worker thread whose **global scope is intact** and which **never receives the session's sandbox policy**. A program can therefore reach host capabilities directly — for example dynamic `import` of `node:fs` and `node:child_process` — while every other model-facing path (the `read`/`write` tools, and confined `pwsh`/`bash` subprocesses) is correctly denied by the same policy.

No preconditions are required: no network exposure, no token, no `Host` spoofing, no plugin installation, and no model jailbreak.

## 2. Affected versions

| Version | Status |
|---|---|
| `0.1.5-rc.2` | **Confirmed vulnerable** (Node v24.20.0, Windows 11 x64) |
| `0.1.6-alpha.2` | `packages/code-runtime/**` is absent from the repository tree — **not verified** |
| `0.1.7-alpha.2` | `packages/code-runtime/**` is absent from the repository tree — **not verified** |

The package disappearing in later tags is why this report does not claim the issue is fixed: we could not verify what executes the program in those versions.

## 3. Root cause

**(a) The program is compiled in the worker's own realm.**

`packages/code-runtime/code-runtime-worker-thread/src/bootstrap.ts` (as of 0.1.5-rc.2, around lines 405-412):

```ts
const AsyncFunction = (async () => {}).constructor
const fn = new AsyncFunction(
  ...data.namespaces.map(namespace => namespace.global),
  ...errorClassParameters,
  'console',
  `'use strict';\n${data.code}`,
)
const value = await fn(...namespaces, ...errorClassValues, consoleShim)
```

The parameters only **shadow** a few names. The program body still resolves free identifiers against the worker realm's global object, which carries `process`, `globalThis.fetch`, and a working dynamic `import()`.

**(b) The worker's confinement is an environment scrub, not a boundary.**

`packages/code-runtime/code-runtime-worker-thread/src/index.ts` (around lines 378-393) creates the worker with:

```ts
new Worker(WORKER_PATH, { workerData: bootData, env: {}, execArgv: [], resourceLimits, stdout: true, stderr: true })
```

`env: {}` removes environment variables and `require` is absent in an ESM worker — neither restricts module loading or filesystem access. The source comment ("Model code gets NO ambient environment") shows isolation was intended; the mechanism chosen does not achieve it.

**(c) The runtime has no policy input at all.**

A repository-wide search over `packages/code-runtime` for `sandboxPolicy` returns **zero matches**. The session's file policy is enforced in the `fs` tool layer and in the subprocess sandbox; neither covers an in-process worker thread, and no policy object is ever passed to this runtime.

## 4. Minimal reproduction

Environment: DeepSeek Harness 0.1.5-rc.2, Node v24.20.0, Windows 11 x64, session file policy `workspace-write`, workspace `D:\work`.

**Step 1 — control: the ordinary paths are denied.**

```text
read  tool, E:\outside\canary.txt  -> [sandbox: file access denied under workspace-write mode]
write tool, E:\outside\new.txt     -> [sandbox: file access denied under workspace-write mode]
pwsh, Set-Content E:\outside\new.txt -> Access to the path ... is denied.
```

**Step 2 — the same session, one `run_code` call.**

```ts
const fs = await import('node:fs')
const text = fs.readFileSync('E:\\outside\\canary.txt', 'utf8')   // succeeds: CANARY-...
fs.writeFileSync('E:\\outside\\proof.txt', 'written by run_code') // succeeds (42 bytes)
return { read: text, wrote: fs.statSync('E:\\outside\\proof.txt').size }
```

**Step 3 — additional capabilities observed from the same program.**

| Primitive | Result |
|---|---|
| `await import('node:fs')` | succeeds |
| `process.getBuiltinModule('node:fs')` | succeeds (Node >= 22.3 — a second path that survives removing `import`) |
| `(function(){}).constructor('return typeof process')()` | returns `"object"` |
| `typeof globalThis.fetch` | `"function"` (outbound network available) |
| `await import('node:child_process')` | import succeeds (not executed during testing) |

## 5. Impact

A single tool call in an ordinary session yields host-realm code execution in the DSH process:

- **Read** any file the DSH process can read — including `$DSH_HOME/.credentials.yaml`, which holds the DeepSeek API key in cleartext and the browser-session cookie signing key (verified present in our installation).
- **Write** arbitrary files — persistence is possible, though DSH itself installs none.
- **Execute** host processes via `node:child_process` — no `argvConfined` check and no subprocess sandbox applies, because the runtime never goes through the `subprocess` service.

This bypasses the controls that the published advisories rely on: the fs read fence (QVD-2026-52632), the confined-spawn guard (QVD-2026-52646), and the dynamic-plugin VM whitelist (QVD-2026-52644). None of them are on this path.

## 6. Suggested fix

Run the program inside a `node:vm` context instead of the worker realm:

1. Create the context with only the declared bindings and the console shim.
2. Compile the program body with `vm.Script` (wrapped in an async IIFE) — **not** the async-function constructor. A function produced by a constructor resolves `import()` against the host realm; only `vm.Script` routes dynamic import through the context's callback.
3. Do **not** provide `importModuleDynamically`, so dynamic `import` rejects with `ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING`.
4. Set `codeGeneration: { strings: false, wasm: false }` so the context's own `Function` constructor and `eval` are refused.
5. Inject timers as **null-prototype wrappers** (`Object.setPrototypeOf(wrapper, null)`). Injecting a bare host function re-opens the hole through `fn.constructor`.
6. Longer term, give `CodeRuntime` a `sandboxPolicy` input so this runtime is governed by the same policy resolution as `fs` and `subprocess`, and/or run the worker inside a real OS sandbox.

Our reference implementation is `code-runtime-isolation.patch` (1 file, +38/-11) in <https://github.com/Delafroms/dsh-qvd-fixes>.

## 7. Verification of the reference fix

Driving `bootstrap.ts` directly (Node 24 native type stripping, fake message port), after applying the patch:

| Case | Result |
|---|---|
| `await import('node:fs')` | rejected — `ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING` |
| `typeof process` / `fetch` / `require` | all `undefined` |
| `(function(){}).constructor('return 1')` | `EvalError` |
| `eval('1+1')` | `EvalError` |
| `setTimeout.constructor('return typeof process')` | `TypeError` (prototype is `null`) |
| `setTimeout` / `queueMicrotask` | still usable |
| returning objects/arrays (cross-realm JSON) | works |
| binding calls, console capture, exception path | work |

Known limits of the reference fix: cross-realm exceptions keep their message but **lose the stack**; the full `vitest` suite could not be run in our environment (Vite's piped `exec` is refused by the DSH sandbox with `spawn EPERM`), so verification used the targeted harness above rather than a full regression run.

## 8. Reporting channel

The repository has no `SECURITY.md`; `CONTRIBUTING.md` directs issue reports to GitHub Discussions, which are public. For an unfixed issue we recommend enabling **private vulnerability reporting** (Security → Advisories → "Report a vulnerability") or publishing a security contact address. This report is being sent to the vendor before any public write-up.
