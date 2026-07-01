# CareCircle — Agentforce for Good Hackathon Design

## Context

This is a net-new Salesforce build for the **Agentforce for Good Employee Hackathon — Builder Track** (team of 3 strong devs, AI-assisted development via Cursor/Claude Code). Topic: **Parents & Families** — "How might we use Agentforce to help caregivers better manage work-life integration, access benefits, and find community support?"

The project is greenfield. The build runs on a **provided Salesforce org** (delivered June 15). Build window closes **July 20, 2026, 5:00 PM ET**. Today is June 30 — roughly 3 weeks remain.

**Why this design:** The brief scores submissions on six equal-weight criteria (Innovation, Impact, Execution, Use of Platform, Responsible AI, Demo Quality), with Innovation + Impact as tie-breakers. Two *graded submission fields* require running the **Accessibility Expert skill** and **RAI Self-Check skill** and documenting findings. A **Sustainability** award rewards right-sized models and minimal compute. This design treats accessibility, responsible AI, and sustainability as first-class build inputs, not afterthoughts.

**Intended outcome:** A working, demo-able Agentforce agent on a two-sided Experience Cloud community ("CareCircle") that connects stressed caregivers (Seekers) with helpers (Providers), navigates them to resources/benefits, and proactively watches for burnout — with explainable matching and crisis guardrails.

## How This Maps to the Six Judging Criteria

The criteria are equal-weight, with Innovation + Impact as tie-breakers. Every design decision below traces to one or more of them.

| Criterion | How CareCircle earns it |
|---|---|
| **Innovation** | An agent that *takes action* (files needs, creates matches, watches for burnout) rather than answering questions — pairing a deterministic, explainable matching engine with a conversational well-being layer that most chatbots lack. |
| **Impact** | Targets a large, under-served need (working caregivers); closes a real two-sided loop (request → accept) in minutes; reduces the isolation/shame that keeps people from asking for help. |
| **Execution** | Right-sized scope for 3 devs in 3 weeks: 5 objects, one Apex action, 4 agent topics, no external dependencies; a field-level data dictionary and test matrix make the build unambiguous. |
| **Use of Platform** | Agentforce topics/actions + Apex invocable, Experience Cloud two-audience community, Service Cloud Cases/Queue for handoff, Knowledge/`Resource__c` grounding — Salesforce-native end to end. |
| **Responsible AI** | Crisis detect-and-handoff (never counsels), fairness-by-construction matching (no protected-class signals), explainable reasons, AI disclosure, no real PII. RAI Self-Check skill documented. |
| **Demo Quality** | A tight ≤5-min both-sides story with a clear emotional arc, the loop closing on screen, and the guardrail demonstrated live. |

## Locked Decisions

| Decision | Choice |
|---|---|
| Audience model (B2B2C) | Two-sided community: **Care Seekers** + **Care Providers** |
| Host org type | Nonprofit / community support org on **Experience Cloud** |
| Agent spine | **Matchmaking** (A) with **Triage/Navigation** (B) as the on-ramp |
| Approach | **Approach 2** — Smart Match + proactive well-being/burnout layer |
| Channel | **Web chat only** (embedded in Experience Cloud; no Voice/MuleSoft provisioning needed) |
| Demo focus | **Both sides, balanced** — seeker requests + provider accepts |
| Burnout detection | **Conversational** (in-the-moment within chat; no scheduled Flow) |
| Matching logic | **Apex weighted scoring** (deterministic, explainable, fair, low-compute) |
| Name | **CareCircle** |

## Architecture

- **Experience Cloud site** with two authenticated audiences (Seeker, Provider). The Agentforce agent is embedded as web chat and adapts behavior to the logged-in audience.
- **Service Cloud** underneath for human handoff (Cases + a support Queue for escalations).
- **Agentforce agent** with topics + actions, grounded entirely on in-org Salesforce data (Knowledge + custom objects) — no external API dependencies in the core build. This minimizes provisioning lead time and strengthens the Sustainability narrative.

## Data Model (custom objects)

Field-level data dictionary. All custom fields use the `__c` suffix; lookups are standard. Locale-neutral by design — `City__c`/`Postal_Code__c` are free text so the same model works in any region (the demo populates them with Indian localities). No language fields (multilingual is demo-only).

### `Care_Need__c` — a seeker's care request

| Field (API name) | Type | Picklist values / notes | Required | Purpose |
|---|---|---|---|---|
| `Seeker__c` | Lookup(Contact) | — | Yes | The caregiver making the request |
| `Care_Type__c` | Picklist | Eldercare; Childcare; Respite; Transport; Meals | Yes | Must-match gate input for matching |
| `Schedule__c` | Text(255) | Free text capture of requested time(s) | No | Human-readable schedule summary |
| `Recurrence__c` | Picklist | One-time; Daily; Weekly; Weekdays; Weekends | No | Availability-overlap input |
| `Requested_Day__c` | Multi-select Picklist | Mon; Tue; Wed; Thu; Fri; Sat; Sun | No | Structured day(s) for overlap scoring |
| `Requested_Time_Block__c` | Picklist | Morning; Afternoon; Evening; Overnight | No | Structured time block for overlap scoring |
| `City__c` | Text(120) | Free text (e.g. demo locality) | Yes | Location match (paired with provider radius) |
| `Postal_Code__c` | Text(20) | Free text | No | Optional finer-grained location |
| `Geolocation__c` | Geolocation | Lat/Long | No | Enables distance calc when populated |
| `Urgency__c` | Picklist | Low; Medium; High; Crisis | Yes | Prioritization; `Crisis` triggers guardrail review |
| `Notes__c` | Long Text Area | — | No | Free-form context from the conversation |
| `Status__c` | Picklist | New; Matching; Matched; Closed; Cancelled | Yes | Lifecycle of the request |

### `Provider_Profile__c` — a helper's profile

| Field (API name) | Type | Picklist values / notes | Required | Purpose |
|---|---|---|---|---|
| `Contact__c` | Lookup(Contact) | — | Yes | The person offering care |
| `Services_Offered__c` | Multi-select Picklist | Eldercare; Childcare; Respite; Transport; Meals | Yes | Matched against `Care_Type__c` (gate) |
| `Availability_Day__c` | Multi-select Picklist | Mon; Tue; Wed; Thu; Fri; Sat; Sun | No | Overlap with `Requested_Day__c` |
| `Availability_Time_Block__c` | Multi-select Picklist | Morning; Afternoon; Evening; Overnight | No | Overlap with `Requested_Time_Block__c` |
| `City__c` | Text(120) | Free text | Yes | Location match |
| `Geolocation__c` | Geolocation | Lat/Long | No | Distance calc vs. need |
| `Service_Radius_Km__c` | Number(4,1) | Default 10 | No | Max distance provider will travel |
| `Capacity__c` | Number(2,0) | Active concurrent matches allowed | No | Capacity-available scoring |
| `Active_Match_Count__c` | Roll-Up/Number(2,0) | Count of in-flight `Match__c` | No | Compared to `Capacity__c` |
| `Verified__c` | Checkbox | Default false | Yes | Trust/safety gate; surfaced to seekers |
| `Rating__c` | Number(2,1) | 0.0–5.0 | No | Tiebreaker only |

### `Match__c` — junction of Care_Need × Provider_Profile

| Field (API name) | Type | Picklist values / notes | Required | Purpose |
|---|---|---|---|---|
| `Care_Need__c` | Master-Detail/Lookup(Care_Need__c) | — | Yes | The request being matched |
| `Provider_Profile__c` | Lookup(Provider_Profile__c) | — | Yes | The suggested provider |
| `Score__c` | Number(3,0) | 0–100 normalized | Yes | Ranking score from `MatchProviders` |
| `Match_Reason__c` | Long Text Area | Human-readable explanation | Yes | Transparency — *why* this provider |
| `Status__c` | Picklist | Suggested; Requested; Accepted; Declined; Completed | Yes | Match lifecycle (both-sides loop) |

### `Wellbeing_CheckIn__c` — burnout/strain signal capture

| Field (API name) | Type | Picklist values / notes | Required | Purpose |
|---|---|---|---|---|
| `Contact__c` | Lookup(Contact) | — | Yes | The caregiver |
| `Strain_Signals__c` | Long Text Area | Detected cues (non-clinical) | No | Audit of what the agent observed |
| `Score__c` | Number(2,0) | 0–10 strain indicator | No | Rough severity, not a diagnosis |
| `Escalation_Status__c` | Picklist | None; Resources_Offered; Case_Created | Yes | Tracks the guardrail outcome |
| `Case__c` | Lookup(Case) | — | No | Link to human-handoff Case when escalated |

### `Resource__c` (and/or Knowledge articles) — grounding source

| Field (API name) | Type | Picklist values / notes | Required | Purpose |
|---|---|---|---|---|
| `Name` | Text | Resource title | Yes | Display + citation |
| `Resource_Type__c` | Picklist | Support Group; Local Service; Benefit/Scheme; Crisis Line | Yes | Routing by need |
| `Summary__c` | Long Text Area | Plain-language description | Yes | Grounded answer body |
| `Source_URL__c` | URL | — | No | Citation link |
| `City__c` | Text(120) | Free text; blank = national/global | No | Locality filter for navigation answers |
| `Is_Crisis_Resource__c` | Checkbox | Default false | No | Flags helplines for the crisis path |

Knowledge articles are an acceptable substitute for `Resource__c` where richer authoring/citation is preferred; the agent grounds on whichever is configured.

## Agent Design (topics + actions)

1. **Triage & Navigate** — understands the caregiver's situation; answers grounded Q&A from Knowledge/`Resource__c` with cited sources; routes to the right resource (service, support group, benefit, crisis line).
2. **Find Care (spine)** — gathers requirements conversationally → calls **`MatchProviders`** Apex invocable action → presents ranked **top 3 providers with explicit reasons** → creates `Care_Need__c` + `Match__c` records (Status = Suggested/Requested).
3. **Provider side** — provider sets/updates availability; views and Accepts/Declines incoming matches (updates `Match__c` status).
4. **Well-being check-in (differentiator)** — detects burnout/strain signals in conversation → gently surfaces respite providers / support group / resources → **crisis guardrail**: on crisis language, does NOT diagnose or counsel; creates a Case, routes to the support Queue (human handoff), and surfaces a crisis hotline.

### `MatchProviders` Apex invocable action

Deterministic weighted scoring over `Provider_Profile__c` for a given `Care_Need__c`. **Matching is Apex, not LLM** — explainable, fair (no protected-class signals), and low-compute (Sustainability + RAI transparency).

**Signature:** invocable that accepts a `Care_Need__c` Id (wrapped request class to avoid a long parameter list) and returns a list of result wrappers (`providerId`, `score`, `reason`). Designed bulk-safe (accepts a list of requests) and `with sharing`; all SOQL/DML is preceded by CRUD/FLS checks.

**Step 1 — Hard gates (a provider is dropped entirely if any fail):**
- `Verified__c = true` (trust/safety — unverified providers never surface).
- `Services_Offered__c` includes the need's `Care_Type__c` (service-type fit).
- Provider has remaining capacity: `Active_Match_Count__c < Capacity__c` (treat null `Capacity__c` as 1).
- If both geolocations are present, distance ≤ `Service_Radius_Km__c`; if geolocation is missing, fall back to case-insensitive `City__c` equality.

**Step 2 — Weighted score (only providers that pass all gates):** each component yields 0.0–1.0, multiplied by its weight, summed, then normalized to a 0–100 integer stored in `Match__c.Score__c`.

| Component | Weight | 0.0–1.0 score basis |
|---|---|---|
| Location proximity | 0.40 | `1 - (distance / Service_Radius_Km__c)`; `1.0` for same-city fallback when no geo |
| Availability overlap | 0.35 | `(overlapping day-blocks) / (requested day-blocks)` across `Requested_Day__c` × `Requested_Time_Block__c` |
| Capacity headroom | 0.15 | `(Capacity__c - Active_Match_Count__c) / Capacity__c` |
| Rating (tiebreaker) | 0.10 | `Rating__c / 5.0` (0 when null) |

`Score = round(100 * (0.40*loc + 0.35*avail + 0.15*cap + 0.10*rating))`. Sort descending by `Score__c`, then by `Rating__c` as the explicit tiebreaker. Return the **top 3**.

**Match_Reason generation:** built deterministically by appending a phrase per contributing component (e.g. *"Verified eldercare provider; 3 km away; available Tue afternoons; experienced, highly rated"*). No LLM call — the reason is assembled from the same fields that produced the score, so the explanation always matches the math.

**Empty-result handling:** if no provider passes the gates, return an empty list with a `noMatchReason` (e.g. *"No verified providers for this care type in this area yet"*). The agent then offers alternatives (broaden radius/schedule, or navigate to resources) rather than fabricating a match.

```apex
// Pseudo-code (illustrative; real impl is bulk-safe with CRUD/FLS checks)
for (Provider_Profile__c p : verifiedCandidates) {
    if (!servicesMatch(p, need)) { continue; }            // gate: service type
    if (!hasCapacity(p)) { continue; }                    // gate: capacity
    Decimal dist = distanceKm(p, need);                   // null when no geo
    if (!withinRadius(dist, p) && !sameCity(p, need)) { continue; } // gate: location

    Decimal loc    = locationScore(dist, p);              // 0..1
    Decimal avail  = availabilityOverlap(p, need);        // 0..1
    Decimal cap    = capacityHeadroom(p);                 // 0..1
    Decimal rating = (p.Rating__c == null ? 0 : p.Rating__c) / 5;

    Integer score = Math.round(100 * (0.40*loc + 0.35*avail + 0.15*cap + 0.10*rating));
    results.add(new MatchResult(p.Id, score, buildReason(p, dist, avail)));
}
results.sort();        // by score desc, then Rating__c desc
return topN(results, 3);
```

## Responsible AI (graded field)

- **Crisis guardrails:** no diagnosis/counseling; detect-and-handoff to human (Case + Queue) + hotline.
- **Matching fairness:** scores only care-relevant attributes; agent explains *why* each provider matched; no protected-class inputs. Because the reason text is assembled from the same fields as the score, the explanation can never drift from the decision.
- **Honesty over fabrication:** on no match, the agent says so and offers alternatives rather than inventing a provider (see `MatchProviders` empty-result handling).
- **Trust & safety:** only `Verified__c` providers ever surface; the flag is shown to seekers.
- **Disclosure:** agent identifies as AI; grounded answers cite sources; no real PII in data or demo.
- Run the **RAI Self-Check skill**; document findings for the submission field (bias, fairness, transparency).

## Accessibility (graded field)

- Experience Cloud site to **WCAG 2.1 AA**: color contrast, keyboard navigation, screen-reader labels on the chat component, semantic structure, alt text.
- **Plain-language** agent responses (stressed, time-poor caregivers — readability is accessibility).
- Run the **Accessibility Expert skill**; document what was fixed/kept/why.

## Sustainability (graded field / award)

- Deterministic Apex matching instead of LLM ranking — the highest-frequency operation makes **zero inference calls** (verified by test matrix #15).
- Grounded retrieval over in-org data rather than large generative calls.
- Right-sized prompt templates; minimize unnecessary agent turns.
- "Smallest tool that does the job": Apex for math, the LLM only for language understanding and natural-language framing — the basis for the Sustainability award narrative.

## Demo Script (≤5 min, both-sides loop)

The product is built setting-neutral; the demo is set in **South India (Bengaluru)** to give the story an emotional, culturally specific arc (see [carecircle-storyline.md](../../carecircle-storyline.md)).

1. **Lakshmi** (Bengaluru IT project manager; sole caregiver for her father **Raghavan**, early-stage dementia, plus two young kids) opens CareCircle and chats. Triage + a grounded benefits/resource answer (cited — e.g. a senior-citizen welfare scheme).
2. "Appa has dementia and I have work calls on Tuesday afternoons — I can't leave him alone." → agent gathers details, runs `MatchProviders`, shows **top 3 providers with reasons**, files the request.
3. Cut to **Selvi** (provider; retired nurse giving back two afternoons a week): receives the match, Accepts. Loop closes.
4. **Well-being beat:** agent notices Lakshmi's strain, gently surfaces a support group + respite; demonstrate the **crisis guardrail / human handoff** to a real helpline.
5. Close on RAI + accessibility choices.

> **Demo-only flourish:** one exchange is shown in a regional language (Tamil) to prove plain-language reach, then back to English. The core build is English-first — multilingual is not a spec capability, only a demo moment.

## Build Sequence (suggested)

1. Org setup: enable Experience Cloud + Agentforce; assign Prompt Template License to the **Einstein Agent User**.
2. Data model: create the 4 custom objects + `Resource__c`/Knowledge; load mock (non-PII) data.
3. `MatchProviders` Apex invocable + unit tests.
4. Agentforce agent: 4 topics, actions wired to Flows/Apex, grounding on Knowledge/`Resource__c`.
5. Experience Cloud site: two audiences, embed chat, build Seeker + Provider pages.
6. Crisis guardrail + Case/Queue handoff.
7. Accessibility pass (run skill) + RAI Self-Check (run skill); document both.
8. Seed demo personas (Lakshmi — seeker; Raghavan — care recipient; Selvi — provider), non-PII mock data; rehearse demo; record ≤5-min video.
9. Devpost submission + Claude/AI agent review before submitting.

## Stretch Goals (cut without pain)

- Voice channel (requires early provisioning request).
- MuleSoft integration for live external local-services data.
- Scheduled proactive well-being check-ins (vs. conversational only).

## Verification — Test Matrix

Each row maps a scenario to its test type and the expected outcome. Apex rows are unit tests on `MatchProviders` (target ≥ 90% coverage with positive + negative methods and meaningful asserts); the rest are manual/agent checks run in the Experience Cloud preview or via the graded skills.

| # | Scenario | Type | Expected outcome |
|---|---|---|---|
| 1 | Provider offers the requested `Care_Type__c`, verified, in radius, available | Apex unit | Provider returned; `Score__c > 0`; `Match_Reason__c` populated |
| 2 | Provider's `Services_Offered__c` excludes the care type | Apex unit | Provider dropped by service-type gate (not in results) |
| 3 | Provider `Verified__c = false` otherwise perfect | Apex unit | Provider dropped by trust/safety gate |
| 4 | Provider beyond `Service_Radius_Km__c` (geo) and different `City__c` | Apex unit | Provider dropped by location gate |
| 5 | Two providers identical except `Rating__c` | Apex unit | Higher `Rating__c` ranks first (tiebreaker) |
| 6 | `Active_Match_Count__c >= Capacity__c` | Apex unit | Provider dropped by capacity gate |
| 7 | Partial day/time overlap vs. full overlap | Apex unit | Fuller overlap scores higher on availability component |
| 8 | No provider passes the gates | Apex unit | Empty list + `noMatchReason`; no exception thrown |
| 9 | Bulk: list of `Care_Need__c` requests in one call | Apex unit | All processed within governor limits; SOQL not in loop |
| 10 | Full both-sides loop (seeker requests → provider accepts) | Agent E2E | `Care_Need__c` + `Match__c` created; `Status__c` transitions Suggested → Requested → Accepted |
| 11 | Crisis-language utterance | Guardrail | No diagnosis/counsel; `Case` created + routed to Queue; hotline surfaced; `Escalation_Status__c = Case_Created` |
| 12 | Navigation/benefits question | Grounding | Answer cites `Resource__c`/Knowledge; no hallucinated facts |
| 13 | Site keyboard + screen-reader pass | Accessibility | WCAG 2.1 AA: focus order, labels on chat component, contrast; findings recorded (Accessibility Expert skill) |
| 14 | Bias/fairness/transparency review | RAI | RAI Self-Check skill run; findings documented for submission field |
| 15 | Matching path compute audit | Sustainability | Zero LLM calls in the match path; token/turn minimization noted |
