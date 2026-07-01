# CareCircle — The Storyline (South India)

*A narrative for the Devpost description, demo video, and pitch. Written for a judge who has never seen the project. Set in South India.*

---

## The Problem (open here)

Across South India — Tamil Nadu, Karnataka, Kerala, Andhra Pradesh, and Telangana — a quiet shift is straining millions of families. The joint family that once shared the work of caregiving is dissolving. Adult children move to Chennai, Bengaluru, and Hyderabad for IT and service jobs — or to the Gulf — while aging parents stay behind in the home town. Daughters and daughters-in-law, who still carry the cultural weight of *being the caregiver*, now do it **alone, and while working full-time.**

The numbers are moving fast. Kerala is already India's most-aged state, with over **16% of its population above 60**, and the South as a whole is ageing decades ahead of the North. Yet formal eldercare barely exists outside private hospitals, government schemes are buried in Tamil/Kannada/Malayalam paperwork most people never see, and asking a neighbour for help can feel like admitting the family has failed.

The help is out there — a trusted neighbour, a temple or church community group, a verified attender, a government pension scheme. **The problem isn't supply. It's connection — and a culture where caregivers suffer in silence.**

That's the gap CareCircle was built to close.

---

## Meet Lakshmi (the hero)

Lakshmi is 36. She's a project manager at an IT services firm in **Bengaluru**. She's also the primary caregiver for her father, **Raghavan**, who has early-stage dementia and lives with her — and mother to two children under ten. Her husband works in Dubai; her brother is in the US. The caregiving, by unspoken family default, is entirely hers.

On Tuesday afternoons, Lakshmi has back-to-back client calls. On those same afternoons, Raghavan cannot be left alone — he wanders. For three weeks she has been taking the calls from her car outside the medical shop, her father in the passenger seat. She is one missed call away from breaking. She would never say this out loud — not to her in-laws, not to her colleagues.

She doesn't have time to research eldercare. She has time to type one sentence into a chat box — in **Tamil or English, whichever comes first.**

---

## The Turn (what CareCircle does)

Lakshmi opens CareCircle — a community care platform — and types the way she'd talk to a trusted friend who happens to know everything.

**She types:** *"Appa has dementia and I'm completely drained. I have work calls on Tuesday afternoons and I can't leave him alone."*

The agent doesn't hand her a form. It **listens, then acts** — and it responds in her language:

1. **It navigates.** It recognises Raghavan may qualify for support under schemes like the **National Programme for Health Care of the Elderly (NPHCE)** and state senior-citizen welfare benefits, and surfaces a plain-language, Tamil-or-English answer — grounded in real resources, with the source cited, not invented.

2. **It matches.** It gathers what actually matters — care type, when, where (locality, e.g. *Jayanagar* / *T. Nagar*) — and runs a transparent matching engine across **verified local caregivers, attenders, and community volunteers**. It returns the **top 3 people who can help, and *why* each one matched**: *"Selvi is a verified respite volunteer in your area, 3 km away, available Tuesday afternoons, experienced with dementia care, speaks Tamil and Kannada."* Lakshmi picks Selvi. The request is filed in one tap.

3. **It catches what a form never would.** As Lakshmi types, the agent hears the exhaustion of someone running on empty. It doesn't diagnose. It doesn't lecture. It gently surfaces a local caregivers' support circle (a temple-community group, an NGO like the Dignity Foundation, an online Tamil-speaking peer group) and a respite option — and if her words ever cross into crisis, it **stops, hands off to a real human, and surfaces a helpline** such as a regional mental-health / elder helpline. Safety is not a feature here; it's a boundary the AI knows never to cross.

---

## The Other Side (close the loop)

Cut to **Selvi.** She's a retired nurse in Bengaluru who signed up to give back two afternoons a week — the kind of neighbour the joint family used to provide and the city took away. She gets a notification: *a match.* She sees Raghavan's need, taps **Accept**, and the circle closes.

No agency fees. No waitlist. No parking-lot phone calls. Two strangers from the same community, connected by an agent that understood the problem and did something about it.

**This is the moment the demo lives for:** the loop completing, both sides served, across language and locality, in under five minutes.

---

## Why It Matters (the impact frame)

CareCircle isn't a chatbot that answers questions. It's an **agent that takes action on a community's behalf** — and it was designed, from the first decision, around the South Indian caregivers most likely to be left behind:

- **For the exhausted caregiver,** every answer is in plain language and offered in **regional languages (Tamil, Kannada, Telugu, Malayalam) alongside English** — and built to WCAG 2.1 AA, because accessibility isn't a checkbox when your user is reading on three hours of sleep, on a phone, between calls.
- **For trust,** matching is deterministic and *explainable* — the agent tells you why, every time. Caregivers and volunteers are verified — critical in a context where letting a stranger into the home is a real safety decision.
- **For safety,** the agent knows its limits: it connects, it never counsels; it escalates to humans the instant a conversation turns serious, and points to real Indian helplines.
- **For the planet,** the heavy lifting — matching — runs on efficient, right-sized logic, not a large model burning compute on every request. We chose the smallest tool that does the job well.
- **For dignity,** it removes the shame. Asking for help becomes one private sentence in a chat box, not a public admission.

---

## The One-Liner

> **CareCircle is an Agentforce-powered community platform for South Indian families that connects exhausted working caregivers with verified local help, resources, and government benefits — in their own language, matching them in minutes, watching for burnout, and knowing exactly when to hand the conversation to a human.**

---

## The Tagline Options

- *No caregiver should have to carry it alone.* — *யாரும் தனியாக சுமக்கத் தேவையில்லை.*
- *The village the city took away — rebuilt as a circle.*
- *Help was always there. Now it finds you — in your language.*
- *Care for the people who care.*

---

## Design Implications (carried back into the spec)

This South India setting changes a few build decisions — to fold into `2026-06-30-carecircle-design.md`:

- **Multilingual agent** — support at least English + one regional language (recommend **Tamil**, matching the demo). Agentforce/prompt templates should respond in the user's language; plain-language principle applies per language.
- **Localised resources** — seed `Resource__c`/Knowledge with *real* Indian/South-Indian references: NPHCE, state senior-citizen welfare schemes, NGOs (e.g. Dignity Foundation, HelpAge India), and an India mental-health/elder helpline for the crisis path.
- **Locality-based matching** — `Provider_Profile__c` and `Care_Need__c` use Indian locality/city granularity (area + city) and language spoken as a match attribute.
- **Verification emphasis** — the `Verified` flag carries extra weight in the narrative; surface it prominently to seekers.
- **Demo personas** — Lakshmi (seeker, Bengaluru), Raghavan (her father), Selvi (provider). Use non-PII mock data.
- **Currency/tone** — any cost references in INR; respectful, family-aware tone in agent copy.
