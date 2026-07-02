# CareCircle

CareCircle is a Salesforce DX project for the Agentforce for Good hackathon. It is an Agentforce-powered, two-sided Experience Cloud community that helps working caregivers find verified local help, navigate grounded resources and benefits, and escalate caregiver burnout or crisis signals to a human support path.

The core design choice is deliberate: matching is deterministic Apex, not LLM ranking. Agentforce handles language understanding and conversational framing, while Apex owns record writes, provider scoring, explanations, and safety-critical state changes.

## Current Build State

Source currently includes the custom data model, permission set, crisis support queue, demo seed script, and Apex invocable actions that back the planned Agentforce topics. The Agentforce agent and Experience Cloud site are still assembled/configured in the org following `docs/agent-build-guide.md`; do not assume their metadata is complete in source until retrieved and added to `manifest/package.xml`.

## Architecture

- **Salesforce DX project:** default package directory is `force-app`, API version `66.0`.
- **Target org:** deploy CareCircle work to `Hackathon Org` (`dhinesh.t@hackathonorg.com`). Use `--target-org "Hackathon Org"` on Salesforce CLI commands.
- **Experience Cloud:** two authenticated audiences, Care Seekers and Care Providers, with the agent embedded as web chat.
- **Agentforce:** four topics planned: Triage & Navigate, Find Care, Provider Respond to Match, and Wellbeing Check-In.
- **Apex actions:** `FindCareAction`, `FindResourcesAction`, `ProviderMatchResponse`, and `WellbeingCheckInAction` are the agent-facing invocable actions. `FindCareAction` calls `MatchProviders` internally.
- **Service Cloud:** `CareCircle Support` queue receives Case handoffs from the crisis path.
- **Grounding:** navigation answers use structured `Resource__c` records in the core build. Knowledge can be added later if richer authoring is needed.

## Key Metadata

Custom objects:

- `Care_Need__c` captures a caregiver request, including care type, schedule, location, urgency, and lifecycle status.
- `Provider_Profile__c` stores provider services, availability, location/radius, capacity, verification, and rating.
- `Match__c` joins a care need to a provider and stores score, reason, and match lifecycle status.
- `Wellbeing_CheckIn__c` records burnout/strain signals and escalation outcome.
- `Resource__c` stores cited support groups, local services, benefits/schemes, and crisis resources.

Important Apex classes:

- `MatchProviders` applies hard gates, weighted scoring, and deterministic reason generation. It returns the top matches or an honest no-match reason.
- `FindCareAction` creates a care need, runs matching, and creates suggested matches.
- `FindResourcesAction` returns cited resources and never fabricates results.
- `ProviderMatchResponse` lets providers accept or decline actionable matches.
- `WellbeingCheckInAction` logs wellbeing signals and creates a Case for crisis escalation.
- `TestDataFactory` centralizes least-privilege test setup.

`manifest/package.xml` is the deployment manifest and must stay in sync whenever metadata is added or removed.

## Matching Rules

`MatchProviders` first applies hard gates:

- provider is verified;
- provider offers the requested care type;
- provider has remaining capacity;
- provider is inside radius when geolocation is available, or in the same city as a fallback.

Passing providers are scored from 0-100 using the spec weights: location `0.40`, availability `0.35`, capacity `0.15`, and rating `0.10`. `Match_Reason__c` is assembled from the same fields used by the score, so the explanation stays aligned with the math. The matching path must remain bulk-safe, `with sharing`, and enforce CRUD/FLS using user-mode data access.

## Safety, Security, and RAI Constraints

- The agent must never diagnose, counsel, or provide mental-health advice.
- Crisis language must create a human handoff Case and surface a real, verified helpline.
- Only verified providers may be shown to seekers.
- Matching must not use protected-class signals.
- No real PII belongs in source, test data, demo scripts, or docs.
- No-match and no-resource cases must be stated honestly; do not invent providers, benefits, or citations.
- High-frequency matching makes zero inference calls; keep scoring in Apex for sustainability and explainability.

## Setup and Deployment

Install dependencies:

```bash
npm install
```

Confirm or authorize the target org:

```bash
sf org login web --alias "Hackathon Org"
sf org display --target-org "Hackathon Org"
```

Deploy source metadata through the maintained manifest:

```bash
sf project deploy start --target-org "Hackathon Org" --manifest manifest/package.xml
```

Assign the permission set when needed:

```bash
sf org assign permset --name CareCircle --target-org "Hackathon Org"
```

Open the org:

```bash
sf org open --target-org "Hackathon Org"
```

Seed non-PII demo data:

```bash
sf apex run --file scripts/apex/seed-demo-data.apex --target-org "Hackathon Org"
```

## Testing and Verification

Run the full Apex action suite:

```bash
sf apex run test --target-org "Hackathon Org" \
  --tests MatchProvidersTest --tests FindCareActionTest \
  --tests ProviderMatchResponseTest --tests WellbeingCheckInActionTest \
  --tests FindResourcesActionTest \
  --code-coverage --result-format human --wait 15
```

Run the focused matcher suite:

```bash
sf apex run test --target-org "Hackathon Org" --tests MatchProvidersTest --result-format human --wait 15
```

Run local formatting verification:

```bash
npm run prettier:verify
```

LWC lint and unit tests are available if Lightning components are added:

```bash
npm run lint
npm run test:unit
```

Before trusting any Apex test result, confirm the preceding deploy succeeded; otherwise tests may be running against stale org code.

## Repository Structure

```text
force-app/main/default/
  classes/          Apex invocable actions, matcher, and tests
  objects/          CareCircle custom objects and fields
  permissionsets/   CareCircle object, field, and class access
  queues/           CareCircle Support queue
manifest/
  package.xml       Source deploy/retrieve manifest
scripts/apex/
  seed-demo-data.apex
docs/
  superpowers/specs/2026-06-30-carecircle-design.md
  agent-build-guide.md
  carecircle-storyline.md
  build-log.md
```

## Documentation

- `docs/superpowers/specs/2026-06-30-carecircle-design.md` is the authoritative contract for the data model, matching weights, guardrails, and test matrix.
- `docs/agent-build-guide.md` is the runbook for assembling and testing the Agentforce agent in the org.
- `docs/carecircle-storyline.md` contains demo narrative and positioning.
- `docs/build-log.md` records meaningful build/deploy/doc changes and known blockers.
- `CLAUDE.md` captures repository workflow rules and Salesforce-specific implementation gotchas.

