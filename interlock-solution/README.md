# Filler-Head Material Interlock
### DPHF-MaterialVerification ⇄ SAP-MII (Ignition)

An interlock that keeps a filler head's **Status LOCKED** until the material
loaded on it (Tote or Super sack) has been scan-verified in
DPHF-MaterialVerification **and** the head's own PLC tag confirms it holds that
same material.

**Design decisions (agreed):**

| Decision | Choice |
|---|---|
| Vessel → head binding | **Explicit operator assignment** (in SAP-MII) |
| Enforcement | **Soft** — DB status + UI blocking, no PLC writes |
| Transport between apps | **Shared DB + mirrored gateway tags** |
| Default state / mismatch | **Fail-safe: LOCKED until verified, no override** |

---

## 1. End-to-end flow

```
 DPHF-MaterialVerification                         SAP-MII
┌───────────────────────────────┐   ┌─────────────────────────────────────┐
│ 1. Operator selects PO +      │   │ 3. Operator opens Operational        │
│    expected material          │   │    Scenario / head assignment        │
│ 2. Scans the vessel:          │   │    - Head list is FILTERED to the    │
│    • Tote scan  → TOTE        │   │      vessel's type (Tote head vs     │
│    • GS1 label  → SUPER_SACK  │   │      Super-sack head)                │
│    Match ⇒                    │   │    - Assign vessel → FillerHead N    │
│    • IS_VERIFIED=1 in         │   │    ⇒ row in tblFillerHeadInterlock,  │
│      tblBatchManagement       │   │      status = LOCKED                 │
│    • VESSEL_TYPE logged       │   └──────────────────┬──────────────────┘
│    • tag mirror written:      │                      │
│      Interlock/Verified/*     │                      ▼
└──────────────┬────────────────┘   ┌─────────────────────────────────────┐
               │  shared IGNPEDB    │ 4. Gateway "InterlockEvaluator"      │
               └───────────────────►│    (timer, 5 s) per assignment row:  │
                                    │    ① IS_VERIFIED = 1 ?               │
                                    │    ② VESSEL_TYPE == head type ?      │
                                    │    ③ PLC FillerHead.materialNumber   │
                                    │       == verified material ?         │
                                    │    ALL pass → UNLOCKED               │
                                    │    any fail / bad quality / error    │
                                    │              → LOCKED (+ log/alarm)  │
                                    │    Mirrors to tags:                  │
                                    │    Interlock/Heads/<WC>/<Head>/Status│
                                    └──────────────────┬──────────────────┘
                                                       ▼
                                    ┌─────────────────────────────────────┐
                                    │ 5. SAP-MII UI (soft enforcement)     │
                                    │  • Head card: red LOCKED / green     │
                                    │    UNLOCKED (+ failure reason)       │
                                    │  • Start / PR / GI / status buttons  │
                                    │    enabled only when UNLOCKED, and   │
                                    │    re-checked against DB on click    │
                                    │    (Interlock/CheckPOFullyUnlocked)  │
                                    └─────────────────────────────────────┘
```

### The three unlock conditions

`INTERLOCK_STATUS = UNLOCKED` **only** when all three hold — evaluated
continuously, so a head that was unlocked **re-locks itself** if any condition
stops holding (e.g. the PLC tag changes to a different material mid-run):

1. **MATERIAL_VERIFIED** — `tblBatchManagement.IS_VERIFIED = 1` for the
   PO + material. Only DPHF-MaterialVerification's scan-verify sets this.
2. **TYPE_MATCH** — the vessel's form (`TOTE` / `SUPER_SACK`) equals the
   assigned head's container type. The assignment dropdown already filters to
   matching heads, so this mainly guards against later re-configuration.
3. **TAG_MATCH** — the head's live PLC tag (`FillerHead UDT → materialNumber`,
   e.g. `[Line4E_FILL]Global.L4E.FillerHead.FillerHead[N].MatNo`) equals the
   verified material number (leading zeros stripped). This is the "correct
   material went into the correct filler head, based on the tag" check.

**Fail-safe details:** no assignment row ⇒ UI reads LOCKED; bad tag quality ⇒
condition ③ fails ⇒ LOCKED; evaluator exception ⇒ row forced LOCKED; there is
no override path.

---

## 2. What changes where

### Database (shared IGNPEDB) — `sql/`
| File | Contents |
|---|---|
| `01_create_tblFillerHeadInterlock.sql` | New `tblFillerHeadInterlock` (one row per PO+material+head, default LOCKED) and `tblFillerHeadInterlockLog` (every transition). Adds `VESSEL_TYPE` to `MatVerificationLogs` and `CONTAINER_TYPE` to `tblDeviceMaster`. |
| `named-queries/*.sql` | Seven named queries: AssignHead, GetRowsToEvaluate, UpdateEvaluation, InsertLog, GetStatusForHead, CheckPOFullyUnlocked, GetHeadsForAssignment. |

### DPHF-MaterialVerification — `ignition/01_materialverification_vessel_type.py`
- New session prop `VesselType`; tote scan handlers stamp `TOTE`, GS1
  label handlers stamp `SUPER_SACK`.
- Verify-button success branch additionally writes the tag mirror
  `[default]Interlock/Verified/*` and logs the vessel type.
- **No behavioural change** to the existing verification logic — it still
  writes `IS_VERIFIED = 1` exactly as today.

### SAP-MII — `ignition/02_gateway_interlock_evaluator.py`, `ignition/03_sapmii_ui_hooks.py`
- **Gateway timer script** `InterlockEvaluator` (5 s): the single writer of
  `INTERLOCK_STATUS`, evaluates the three conditions, mirrors to
  `[default]Interlock/Heads/<WC>/<Head>/*`, logs transitions, warns on re-lock.
- **Assignment view** (OperationalScenario): head dropdown fed by
  `GetHeadsForAssignment` (type-filtered); Assign button calls `AssignHead`.
- **POExecution**: status-changing buttons bound to the head Status tag for
  instant enable/disable, plus a DB re-check (`CheckPOFullyUnlocked`) at click
  time so a stale tag can never let a status change through.

### Gateway tags — `tags/interlock-tags.json`
- `Interlock/Verified/*` — last successful verification (written by MatVer).
- `Interlock/Heads/<WC>/<Head>/*` — per-head Status/Message mirror (written by
  the evaluator, bound by SAP-MII views).

---

## 3. Deployment order

1. Run `sql/01_create_tblFillerHeadInterlock.sql` on IGNPEDB.
2. Classify heads: set `tblDeviceMaster.CONTAINER_TYPE` = `TOTE` /
   `SUPER_SACK` for every filler head (or confirm `[type]` already encodes it
   and drop the new column from the queries).
3. Import `tags/interlock-tags.json` under the `[default]` provider.
4. Create the 7 named queries in the SAP-MII project (`Interlock/` folder).
5. Add the gateway timer script `InterlockEvaluator` (5000 ms, dedicated).
6. MaterialVerification project: add `VesselType` session prop, the two-line
   additions to the scan handlers, and the verify-success publish block.
7. SAP-MII project: assignment view + POExecution button bindings/gate.
8. Test matrix (per work center):
   - verify Tote → assign Tote head with matching PLC tag → UNLOCKED ✅
   - verify Tote → try Super-sack head → not offered / TYPE_MATCH=0 ⛔
   - unverified material → assigned head stays LOCKED ⛔
   - PLC tag differs from verified material → LOCKED, reason shows both ⛔
   - unlocked head, then PLC tag changes mid-run → re-locks + warn log ⛔
   - DB/tag failure → stays/goes LOCKED (fail-safe) ⛔

## 4. Open items / assumptions
- **Assumption:** GS1 label scans (17/36/38-digit, `(240)…(10)…`) are the
  Super-sack path, tote-ID scans the Tote path. If Super sacks can also be
  identified another way, stamp `VesselType` there too.
- `tblDeviceMaster.[type]` may already distinguish Tote vs Super-sack heads —
  if so, skip `CONTAINER_TYPE` and map `[type]` values in the two queries that
  reference it.
- Enforcement is deliberately **soft** (UI-only). If you later want hard
  enforcement, the evaluator is the natural place to also write a PLC
  interlock bit (the `ScalesLocked` pattern already exists in the Handfill UDT).
