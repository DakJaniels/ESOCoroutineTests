# ESO coroutine findings (Havok Lua)

Observed with **eso_coroutine_tests** and Taneth on **eso.live.11.3.6.3240040** (API **101049**, PC NA, 2026-06-01).

## Garbage collection

A coroutine in **`suspended`** state keeps its activation record (locals and upvalues) reachable. The runtime treats that **thread** as a GC root: data referenced only from inside the coroutine is not collected when external references are cleared, including after **`collectgarbage("collect")`** (tests call it twice).

In the retention test, a large table is held in a coroutine local, the coroutine yields, and the only outside reference to the table is dropped. **`coroutine.resume`** still returns the same payload afterward. Taneth’s default case uses **40 000** rows (numeric fields plus a 48-byte string per row). A manual run with **2 000 000** rows on the reference client allocated about **797 MB** Lua heap (**98126 → 815095** KB per `collectgarbage("count")`), yielded at **815164** KB, and after two full collects with the external ref cleared remained at **800874** KB (about **14 MB** freed); resume verified **2 000 000** rows and field values. A 500-row Taneth case showed **106762 → 98255** KB while suspended, with resume still returning `gc-retention-test`.

Memory tied to coroutine locals is released when **`coroutine.status(co) == "dead"`** and nothing else references the thread or its results. Long-lived workers that yield while holding encode buffers or large tables (for example LibCBOR-style pipelines) should not be left suspended if that memory should be reclaimed.

### GC retention tests

- `/taneth coroutine` — includes `garbage collection / giant payload retained across collect` (40 000 rows).
- `/script TestCoroutine.RunGiantPayloadRetentionTest(rowCount)` — same logic, optional row count for manual stress.

## Coroutine API (Lua 5.1-style)

| API | Behavior on reference client |
| --- | --- |
| `coroutine.create` | Returns `type == "thread"` (not PUC-Rio `"coroutine"`). |
| `coroutine.status` | `suspended` while yielded; `dead` after return or uncaught error. |
| `coroutine.running()` | Thread handle inside a coroutine; **`nil` on main** (no main thread object). |
| `coroutine.wrap` / `yield` / multi-value resume | Matches Lua 5.1 semantics in tests. |
| `coroutine.getname` / `setname` | Names preserved across yields. |

## Errors and tracebacks

Failed **`coroutine.resume`** returns **`false`** and an error **string** that includes Havok’s **`stack traceback:`** text. Frames may include **`<Locals>…</Locals>`** (booleans as `T`/`F`, tables as `[table:n]`, etc.) and **`(tail call): ?`** in deep chains.

During the error path inside the coroutine, **`ZO_GetCallstackFunctionNames`** lists coroutine stack functions. After the thread is dead, names from the resumer side reflect the caller (Taneth’s `RunTest`, `pcall`, and so on), not the failed coroutine body.

For debugging, **`debug.traceback(co, err, 1)`** gives a short trace focused on the thread (about **11** lines in reference runs). **`debug.traceback(err, 1)`** from code running under Taneth’s `it()` is much longer (about **42** lines), including the test runner and chat command stack. **`debug.traceback(co)`** and **`debug.traceback(co, nil, 1)`** omit those outer frames. **`debug.traceback()`**, **`debug.traceback(nil, 1)`**, and **`debug.traceback(nil, nil, 1)`** return a string on this client (not the numeric “level-only” behavior described for some PUC-Rio 5.1 builds).

## `ZO_ErrorFrame`

**`SetCurrentError`** grays the **`<Locals>…</Locals>`** block with `|caaaaaa…|r` only; it does not parse locals into a table. The simple error view strips locals; extended view shows the full colored string. The test addon’s **`formatMessage`** follows the same locals wrapping and adds traceback / **`ZO_GetCallstackFunctionNames`** output (Taneth’s `it()` closure still appears as `(anonymous)` when formatting from the runner).

## Running tests

```text
/reloadui
/taneth coroutine
```

Taneth prints per-`it` results in its dialog. The suite also emits a **`[coroutine:summary]`** digest at the end of the run; **`/script TestCoroutine.PrintDigest()`** prints the last digest again.

With **LibDebugLogger** and chat mirroring / **`logTraces`**, **`CHAT_ROUTER:AddDebugMessage`** (including this addon’s **`d()`**) may append an extra **`stack traceback:`** from the logger hook. The session summary uses **`RequestDebugPrintText`** so the digest block stays free of that noise; avoid **`d(TestCoroutine.LastDigest)`** if you need a clean paste.
