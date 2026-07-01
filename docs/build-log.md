# CareCircle — Build Log

Running record of what has been built, deployed, and decided during implementation. Updated after every meaningful change. The authoritative design is in [`superpowers/specs/2026-06-30-carecircle-design.md`](superpowers/specs/2026-06-30-carecircle-design.md).

## Status at a glance

| Area | Status | Notes |
|---|---|---|
| Data model (5 objects) | ✅ Built & deployed | Deployed to **Hackathon Org** (orgfarm-e12067a131) |
| `MatchProviders` Apex + tests | ✅ Done | TDD; **10/10 pass, 92% coverage**, run as least-privilege user via `TestDataFactory` |
| Permission set | ✅ Done | `CareCircle` PS deployed + assigned; grants object/field FLS |
| Agent backing actions (Apex) | ✅ Done | 4 invocable actions, **32 tests pass, 96% coverage** |
| Agentforce agent (4 topics) | ⬜ Pending | Wire topics to the actions below |
| Crisis handoff Queue | ✅ Done | `CareCircle Support` queue (Case) deployed |
| Experience Cloud site | ⬜ Pending | Two audiences, embedded chat |
| Crisis guardrail (Case + Queue) | ⬜ Pending | RAI non-negotiable |
| Demo data (non-PII) | ✅ Done | Idempotent seed script; matching verified end-to-end |
| Accessibility + RAI skill runs | ⬜ Pending | Graded submission fields |

## Manifest

`manifest/package.xml` mirrors all deployed metadata and is updated with every new component.

## Changelog

### 2026-07-01 — Data model

Created 5 custom objects with the full field dictionary from the spec:

- **`Care_Need__c`** (AutoNumber `CN-{00000}`) — Seeker, Care_Type, Schedule, Recurrence, Requested_Day, Requested_Time_Block, City, Postal_Code, Geolocation, Urgency, Notes, Status.
- **`Provider_Profile__c`** (Text name) — Contact, Services_Offered, Availability_Day, Availability_Time_Block, City, Geolocation, Service_Radius_Km, Capacity, Active_Match_Count, Verified, Rating.
- **`Match__c`** (AutoNumber `M-{00000}`) — Care_Need, Provider_Profile, Score, Match_Reason, Status.
- **`Wellbeing_CheckIn__c`** (AutoNumber `WB-{00000}`) — Contact, Strain_Signals, Score, Escalation_Status, Case.
- **`Resource__c`** (Text name) — Resource_Type, Summary, Source_URL, City, Is_Crisis_Resource.

**Implementation decisions (deviations / clarifications from spec):**
- `Match__c` uses **Lookup** (not Master-Detail) to `Care_Need__c` and `Provider_Profile__c`, with `deleteConstraint = Restrict`. Keeps `Active_Match_Count__c` as an app-maintained Number rather than a roll-up, so tests can set it directly and the matcher stays deterministic.
- Restricted picklists throughout to enforce the spec's controlled vocabularies.
- `Match_Reason__c` set to 1000-char Long Text Area; made not-required at the field level (populated by `MatchProviders`, but relaxed so manual test inserts don't fail).

**Deploy:** initial deploy failed on 3 required Contact lookups (`Seeker__c`, both `Contact__c`) — Salesforce requires an explicit `deleteConstraint` on required lookups. Added `<deleteConstraint>Restrict</deleteConstraint>` to all three. Redeploy succeeded: **43/43 components** deployed to Hackathon Org.

### 2026-07-01 — MatchProviders (Apex, TDD)

Built `MatchProviders` + `MatchProvidersTest` test-first (stub → watched 10 tests fail → implemented → green).

- **Design fidelity:** hard gates (verified / service-type / capacity / location-radius-or-same-city), then weighted score (loc 0.40, avail 0.35, cap 0.15, rating 0.10) → 0–100 int; sort by score desc then rating desc; top N (default 3). Reason string assembled from the same fields that produced the score. Empty result returns `noMatchReason`. Bulk-safe: needs + verified providers each loaded in one SOQL, no queries in loops; `with sharing` + `WITH USER_MODE`.
- **Tests:** 10 methods covering test-matrix rows 1–9 plus a `maxResults` cap. **Result: 10/10 pass, MatchProviders 92% coverage** (spec target ≥90% met).

**Blocker hit & fixed — FLS / `WITH USER_MODE`:** after deploy, all tests failed with `No such column 'Requested_Day__c'`. Root cause: fields deployed via Metadata API grant **no field-level security** to any profile/permset by default, and `WITH USER_MODE` enforces FLS — so the columns were invisible to the running user (looked like "no such column"). Fix: built the `CareCircle` permission set (object CRUD + FLS on all non-required fields + Apex class access), deployed and assigned it to the admin user. Kept `WITH USER_MODE` (spec requires FLS enforcement) rather than downgrading to system mode. Tests green immediately after.

### 2026-07-01 — CareCircle permission set

`force-app/main/default/permissionsets/CareCircle.permissionset-meta.xml`: full CRUD + View/Modify All on the 5 objects, read/edit FLS on every non-required custom field (required/autonumber fields are not FLS-eligible and are accessible once the object is), and access to the `MatchProviders` Apex class. Deployed and assigned.

### 2026-07-01 — TestDataFactory + least-privilege test execution

`TestDataFactory` centralizes all test-data creation (contacts, needs, providers with/without geo) and provisions a **least-privilege test user**: Standard User profile + the `CareCircle` permission set only. `MatchProvidersTest` now creates its data and runs every assertion inside `System.runAs(testUser)`, so the tests execute under real CRUD/FLS enforcement as a non-admin community user would — not as an admin with View/Modify All. This makes the suite a genuine guarantee that the permission set grants exactly what the code needs; a missing object or field grant would now fail a test rather than pass silently.

**Compile fix:** `createProviderWithGeo` originally typed lat/lng as `Double`; Apex won't bind Decimal literals (`13.0827`) to `Double` params. Changed to `Decimal` params and convert via `.doubleValue()` when assigning the geolocation compound fields. Re-run: **10/10 pass, MatchProviders 92%**, executing as the least-privilege user.

### 2026-07-01 — Demo data seed

`scripts/apex/seed-demo-data.apex` — idempotent, non-PII, fictional Bengaluru personas (tagged `[DEMO]`; re-running deletes prior demo records first). Seeds:

- **Lakshmi** (seeker) — eldercare need, Jayanagar, Tue afternoons, High urgency (father Raghavan, early-stage dementia).
- **4 providers** chosen to exercise the engine live: **Selvi** (verified, same locality, full availability, 4.9★ → ranks #1), **Anand** (verified, 3.5 km, 4.3★ → #2), **Priya** (verified but Whitefield with a 5 km radius → dropped by the location gate), **Ravi** (unverified, otherwise perfect → never surfaces; proves the trust/safety gate).
- **4 resources** — dementia support group, senior-citizen welfare scheme, Jayanagar respite service, and a 24×7 caregiver crisis line (`Is_Crisis_Resource__c = true`).

**End-to-end verification:** ran `MatchProviders` against the seeded need — returned **Selvi #100** then **Anand #77** with deterministic reasons; Priya and Ravi correctly excluded. The full matching path works on real org data, not just unit tests.

**Gotchas:** `Contact.Description`, `Care_Need__c.Notes__c`, and `Wellbeing_CheckIn__c.Strain_Signals__c` are Long Text Areas and **cannot be filtered with `=`/`LIKE` in SOQL**. Reworked cleanup to key off the demo Contacts' `LastName` (a filterable Text field) and delete related records by relationship.

> **Pre-submission TODO:** the crisis-line resource uses a placeholder URL/number — replace with a real, verified helpline before the demo/submission (RAI: the crisis path must surface a genuine resource).

### 2026-07-01 — Agent backing actions (4 invocable Apex actions, parallel build)

Built the four Agentforce topic actions by fanning out four subagents in parallel (one per action, each authoring only its own class + test; no shared-file edits). Integrated centrally: permission set, manifest, deploy, and test run.

- **`FindCareAction`** (Find Care spine) — creates `Care_Need__c`, calls `MatchProviders`, creates `Match__c` (Suggested), sets need to Matched. Request accepts `;`- or `,`-delimited multiselect inputs (normalized to `;`). **100% coverage.**
- **`ProviderMatchResponse`** (provider accept/decline) — Accept → Match Accepted + provider `Active_Match_Count__c`++ + need Matched; Decline → Match Declined; guards invalid transitions (only Suggested/Requested actionable). **96%.**
- **`WellbeingCheckInAction`** (crisis guardrail) — logs `Wellbeing_CheckIn__c`; thresholds: `isCrisis || score>=8` → creates `Case` routed to `CareCircle Support` queue + returns a real crisis `Resource__c` (`Case_Created`); `score>=4` → `Resources_Offered`; else `None`. Never generates advice — records + routes only. **97%.**
- **`FindResourcesAction`** (grounded triage) — queries `Resource__c` by type/city, locality-specific before national (null city), capped; empty → `noResultsMessage`, never fabricates. **98%.**

All four are `public with sharing`, bulk-safe (no SOQL/DML in loops), and use `WITH USER_MODE` / `AccessLevel.USER_MODE`.

**Integration changes (central, by me — not the subagents):**
- `CareCircle` permission set: added **Case** object CRUD (read/create/edit) and class access for all four actions. (Wellbeing field FLS was already present.)
- New **`CareCircle Support`** Queue (`force-app/main/default/queues/`) over Case, for the crisis handoff — verified live in the org.
- Manifest updated with the 8 new classes + queue.

**Blocker hit & fixed:** `ProviderMatchResponseTest` used `'Elder Care'` (with a space) for `Care_Type__c`, which is a restricted picklist whose value is `Eldercare` → `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST` on insert (5 failing tests). Fixed the literals; scanned the other three test files for the same class of bug (none). Full deploy: **56/56 components**; full suite: **32/32 tests pass, 96% org-wide**, every action class ≥93%.
