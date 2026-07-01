# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**CareCircle** — an Agentforce-powered, two-sided Experience Cloud community for the *Agentforce for Good* hackathon (Builder Track). It connects working caregivers ("Seekers") with verified helpers ("Providers"), navigates them to benefits/resources, and watches for caregiver burnout — with an explainable matching engine and crisis guardrails.

The authoritative design lives in `docs/superpowers/specs/2026-06-30-carecircle-design.md` (data model, agent topics, `MatchProviders` scoring algorithm, test matrix). The narrative/demo framing is in `docs/carecircle-storyline.md`. **Read the spec before changing the data model or matching logic — the field names, picklist values, and scoring weights there are the contract.**

This is a standard Salesforce DX project (`sfdx-project.json`, package dir `force-app`, API v66.0). `force-app/main/default/` is currently empty — metadata is built from the spec.

## Commands

```bash
# Org auth & deploy (org provided by hackathon; alias it once authorized)
sf org login web --alias carecircle
sf project deploy start --target-org carecircle      # deploy metadata
sf project retrieve start --target-org carecircle     # pull org changes back to source
sf org open --target-org carecircle

# Apex tests (MatchProviders is the critical class — target ≥90% coverage)
sf apex run test --target-org carecircle --code-coverage --result-format human
sf apex run test --target-org carecircle --tests MatchProvidersTest --result-format human   # single class
sf apex run --file scripts/apex/hello.apex --target-org carecircle                            # anonymous Apex

# LWC unit tests (Jest)
npm run test:unit                 # all
npm run test:unit:watch
npm run test:unit:coverage

# Lint & format (run before committing; husky pre-commit also runs lint-staged)
npm run lint                      # eslint over aura/lwc JS
npm run prettier                  # format (includes .cls via prettier-plugin-apex)
npm run prettier:verify

# Scaffold metadata
sf apex generate class --name MatchProviders --output-dir force-app/main/default/classes
sf lightning generate component --type lwc --name myCmp --output-dir force-app/main/default/lwc
```

## Architecture (the big picture)

The system is Salesforce-native end to end, with **no external API dependencies** in the core build (a deliberate choice — minimizes provisioning lead time and supports the Sustainability judging criterion).

- **Data model (5 custom objects):** `Care_Need__c` (a seeker's request) and `Provider_Profile__c` (a helper) are joined by `Match__c` (the junction carrying `Score__c`, `Match_Reason__c`, and a `Status__c` lifecycle: Suggested → Requested → Accepted → Declined → Completed). `Wellbeing_CheckIn__c` records burnout signals + escalation outcome. `Resource__c` (or Knowledge) is the grounding source for navigation answers. Full field-level dictionary is in the spec.

- **Matching is Apex, not LLM** — this is the central design decision and must be preserved. `MatchProviders` is an invocable action: hard gates first (`Verified__c`, service-type fit, capacity, location/radius), then a weighted score (location 0.40, availability 0.35, capacity 0.15, rating 0.10) normalized to 0–100. The `Match_Reason__c` text is assembled deterministically **from the same fields that produced the score**, so the human-readable explanation can never drift from the math. On no match it returns an empty list with a reason rather than fabricating a provider. Must be bulk-safe (`with sharing`, no SOQL/DML in loops, CRUD/FLS checks).

- **Agentforce agent (4 topics):** Triage & Navigate (grounded, cited Q&A) · Find Care (the spine — calls `MatchProviders`, creates `Care_Need__c` + `Match__c`) · Provider side (accept/decline matches) · Well-being check-in. The agent uses the LLM only for language understanding and natural-language framing — never for the matching math.

- **Experience Cloud site** with two authenticated audiences (Seeker, Provider); agent embedded as web chat. **Service Cloud** Cases + a support Queue back the crisis handoff.

## Non-negotiable constraints (these are graded; don't quietly break them)

- **Crisis guardrail:** the agent must never diagnose or counsel. On crisis language it hands off to a human (creates a `Case` routed to the Queue) and surfaces a real helpline. Any change touching the well-being topic must preserve this.
- **Fairness by construction:** matching scores only care-relevant attributes — never protected-class signals. Only `Verified__c` providers ever surface.
- **Honesty over fabrication:** no match → say so and offer alternatives; grounded answers cite their `Resource__c`/Knowledge source; no hallucinated facts.
- **Sustainability:** the high-frequency path (matching) makes zero inference calls — keep it that way.
- **No real PII** anywhere in data, mock records, or the demo. The product is built setting-neutral; only the *demo* is localized to South India (Bengaluru) with mock personas (Lakshmi, Raghavan, Selvi).

## Conventions

- Validate against the spec's test matrix (15 scenarios) — Apex rows 1–9 are unit tests on `MatchProviders`; rows 10–15 are agent E2E / accessibility / RAI / sustainability checks.
- Run the **Accessibility Expert skill** and **RAI Self-Check skill** before submission and capture their findings — these feed required Devpost submission fields, not just internal QA.
- Source-driven development: change metadata in `force-app` and deploy, or retrieve org changes back into source — don't let the org and the repo diverge.
