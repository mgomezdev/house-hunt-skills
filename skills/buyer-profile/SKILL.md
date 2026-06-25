---
name: buyer-profile
description: "Build or update BUYER-PROFILE.md. When BASELINE.md exists, reviews it with the user and interviews them on what is Critical, Nice-to-have, or Irrelevant — deriving hard requirements and preferred features from real current-home data instead of abstract questions. Falls back to a direct questionnaire if no baseline."
trigger: /profile
---

# /profile

Build or update `BUYER-PROFILE.md`. When a `BASELINE.md` exists, the interview is grounded in your actual current home — you classify each attribute rather than specifying requirements from scratch.

## Usage

```
/profile         — create or update profile (baseline-aware when BASELINE.md exists)
/profile update  — jump straight to update mode
```

## BUYER-PROFILE.md Format

Canonical format read by all downstream skills. Do not deviate from key names or section headers.

```markdown
# Buyer Profile
updated: YYYY-MM-DD
baseline_used: [true | false]

## Work Destinations
| Label | Address | Days/Week | Current Peak Drive (min) |
|-------|---------|-----------|--------------------------|
| [label] | [full address] | [n] | [n] |

## Household
adults: [n]
children: [comma-separated ages, or "none"]
pets: [description or "none"]

## Priorities (1 = most important)
1. [School Quality | Commute | Safety | Home Size | Value/Price | Lot/Outdoor | Low Maintenance]
2. ...

## Hard Requirements
min_beds: [n]
min_baths_full: [n]
min_sqft: [n]
max_price: [n]
min_garage_spaces: [n]
must_have_office: [true | false]
max_hoa_monthly: [n | null]

## Preferred Features
- [feature, one per line]

## School Drive Baselines (peak hours, from current home)
elementary_drive_min: [n | null]
middle_drive_min: [n | null]
high_drive_min: [n | null]

## Financial
budget: [n]
down_payment_pct: [n]
first_time_buyer: [true | false]
```

---

## Path A — Baseline-aware profile (BASELINE.md found)

Use this path when `BASELINE.md` exists in the current working directory.

### Step A1 — Read baseline

Read `BASELINE.md`. Extract all property, schools, crime, and commute fields.

Check if `BUYER-PROFILE.md` already exists. If so, read it and note which sections are already filled.

### Step A2 — Show the baseline card and run the preferences interview

Display the baseline summary (from the card in `/baseline` Step 8), then ask:

> "I've pulled your current home's data above. For each attribute, tell me whether it's **Critical** (the new home must match or beat it), **Nice-to-have** (you'd prefer it but can flex), or **Irrelevant** (you don't care).
>
> For anything Critical, I'll default the minimum to your current value — just say so if you want to require more or specify a different threshold.
>
> **PROPERTY**
> - Beds: [X]
> - Full baths: [X]
> - Sqft: [X,XXX]
> - Garage: [X] spaces ([Attached/Detached])
> - Lot: [X,XXX] sqft
> - Stories: [X]
> - Office: [Yes/No]
> - Game room: [Yes/No]
> - Pool: [Yes/No]
> - Fireplace: [X]
> - HOA: $[X]/mo
> - Home age: [built XXXX, X years old]
>
> **SCHOOLS** (ratings shown for all levels; drive times only where `school_levels` applies)
>
> For levels in `school_levels` (school-age children present): show rating + drive time, ask Critical/NTH/Irrelevant for both rating and drive.
> For levels NOT in `school_levels`: show rating only, label "(resale value only)", ask Critical/NTH/Irrelevant for rating only — do not ask about drive time.
>
> - Elementary rating: [GS X/10 · TEA X][  ·  Drive: X min | (resale value only)]
> - Middle rating:     [GS X/10 · TEA X][  ·  Drive: X min | (resale value only)]
> - High rating:       [GS X/10 · TEA X][  ·  Drive: X min | (resale value only)]
>
> **SAFETY**
> - Crime grade: [X] ([vs national] vs national avg)
>
> **COMMUTE** — omit this section entirely when `remote_work: true` in BASELINE.md.
> - [Label]: [X] min peak ([X] days/wk)"

Wait for the user's full response before proceeding.

### Step A3 — Parse preferences and derive requirements

Parse the user's response into three buckets:

**Critical attributes** → become Hard Requirements in the profile:

| Baseline attribute | Derived Hard Requirement | Default minimum |
|-------------------|--------------------------|----------------|
| beds | `min_beds` | baseline value |
| baths_full | `min_baths_full` | baseline value |
| sqft | `min_sqft` | baseline value |
| garage_spaces | `min_garage_spaces` | baseline value |
| has_office = true | `must_have_office: true` | — |
| hoa_monthly | `max_hoa_monthly` | baseline value |
| crime grade | record in flags (not a hard filter field) | — |
| commute peak (per dest) | record max acceptable in notes | baseline value + 10 min buffer |
| school GS rating | record preferred minimum GS | baseline GS rating - 1 |
| school drive time | record in school drive baselines | baseline drive |

If the user specifies a different threshold for a Critical attribute (e.g. "I want at least 4 beds, not 3"), use their stated value instead of the baseline.

**Nice-to-have attributes** → become Preferred Features bullet list entries:
- Use natural language: "garage ≥3 spaces", "pool", "office", "GS rating ≥8", etc.

**Irrelevant attributes** → omit from both hard requirements and preferred features.

### Step A4 — School drive baselines

From the baseline data, populate the school drive baseline section with current drive times for any school type the user marked as Critical or Nice-to-have. If marked Irrelevant, set to null.

```
elementary_drive_min: [from BASELINE.md, or null if irrelevant]
middle_drive_min:     [from BASELINE.md, or null if irrelevant]
high_drive_min:       [from BASELINE.md, or null if irrelevant]
```

### Step A5 — Ask for remaining fields not in baseline

Ask only the questions that cannot be derived from baseline data:

> "A few more things to round out your profile:
>
> 1. **Household** — How many adults in the home? Any kids (and ages)? Pets?
> 2. **Budget** — What's your max purchase price? Rough down payment %? First-time buyer?
> 3. **Priorities** — Rank these 1–7 (I'll use this to weight your score):
>    1. School Quality
>    2. Commute
>    3. Safety / Crime
>    4. Home Size / Rooms
>    5. Value / Price
>    6. Lot / Outdoor Space
>    7. Low Maintenance
> 4. **Anything else** — Any hard requirements or nice-to-haves I haven't asked about?"

### Step A6 — Write BUYER-PROFILE.md

Combine all derived requirements (from Step A3) with the remaining answers (from Step A5) and write `BUYER-PROFILE.md` using the canonical format. Set `baseline_used: true` and `updated:` to today's date.

Confirm:
> "Profile saved. Top priority: [#1]. Hard requirements: [summarize key fields]. Run `/score <address>` to evaluate any property."

---

## Path B — Direct questionnaire (no BASELINE.md)

Use this path when `BASELINE.md` does not exist.

Recommend running `/baseline <current address>` first if the user owns or rents a current home:
> "I don't see a `BASELINE.md`. If you run `/baseline <your current address>` first, the profile interview will be grounded in your actual home data — much easier than specifying requirements from scratch. Want to do that first, or continue with a direct questionnaire?"

If they choose to continue directly, ask by section in order. Wait for response after each section before moving to the next.

---

**Section A — Work Destinations**
> "Where do you work? (Address or intersection.) How many days per week do you commute, and what's your current peak-hour drive time?"

**Section B — Household**
> "Who's in the household — adults, kids (ages), pets?"

**Section C — Priorities**
> "Rank these 1–7, most to least important:
> 1. School Quality  2. Commute  3. Safety  4. Home Size  5. Value/Price  6. Lot/Outdoor  7. Low Maintenance"

**Section D — Hard Requirements**
> "What are your absolute minimums?
> - Beds / full baths / sqft / max price / garage spaces / must have office? / max HOA per month?"

**Section E — Preferred Features**
> "What would be nice to have but isn't a dealbreaker? (pool, game room, single story, large lot, etc.)"

**Section F — School Drive Baselines**
> "How long is your current drive to your kids' schools during the school rush — elementary, middle, high?"

**Section G — Financial**
> "Budget, down payment %, first-time buyer?"

After all sections, write `BUYER-PROFILE.md` with `baseline_used: false`. Confirm and offer next step.
