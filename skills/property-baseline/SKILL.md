---
name: property-baseline
description: "Capture a complete factual snapshot of the buyer's current home — property data, schools, crime, and commute — and write it to BASELINE.md. Run /profile afterward to classify what matters and build BUYER-PROFILE.md."
trigger: /baseline
---

# /baseline

Snapshot your current home so it can be used as the comparison anchor for every property you evaluate. Runs the full data suite against your current address and writes `BASELINE.md`.

Run `/profile` after this to classify which attributes matter and build your requirements.

## Usage

```
/baseline <address>
/baseline 1116 Bluestem Dr, Aubrey TX 76227
```

## BASELINE.md Format

This is the canonical format. The `/profile` skill reads it to drive the preferences interview. Do not deviate from key names or section headers.

```markdown
# Current Home Baseline
generated: YYYY-MM-DD
address: [full address]
school_levels: [elementary, middle, high | subset | none]   // grade levels with school-age children
remote_work: [true | false]

## Property
beds: [n]
baths_full: [n]
baths_half: [n]
sqft: [n]
lot_sqft: [n]
lot_acres: [n]
garage_spaces: [n]
garage_sqft: [n|null]
garage_attached: [true|false|null]
stories: [n|null]
year_built: [n|null]
hoa_fee: [n]
hoa_frequency: [Monthly|Quarterly|Annual|None]
hoa_monthly: [n]           // normalized to monthly for comparisons
has_office: [true|false|null]
has_game_room: [true|false|null]
has_media_room: [true|false|null]
has_loft: [true|false|null]
pool: [true|false|null]
fireplace_count: [n]
cooling: [string|null]
heating: [string|null]
rooms_total: [n|null]
living_areas: [n|null]
dining_areas: [n|null]

## Schools
district: [ISD name]
district_tea: [A|B|C|D|F|null]
elementary_name: [name|null]
elementary_gs: [1-10|null]
elementary_tea: [A|B|C|D|F|null]
elementary_drive_min: [n|null]
middle_name: [name|null]
middle_gs: [1-10|null]
middle_tea: [A|B|C|D|F|null]
middle_drive_min: [n|null]
high_name: [name|null]
high_gs: [1-10|null]
high_tea: [A|B|C|D|F|null]
high_drive_min: [n|null]

## Crime
grade: [A|B|C|D|F|null]
violent_rate_per1k: [n|null]
property_rate_per1k: [n|null]
vs_national_violent: [string|null]    // e.g. "28% below"
vs_national_property: [string|null]
trend: [Improving|Stable|Worsening|null]

## Commute
| Label | Address | Days/Week | Off-Peak (min) | Peak (min) |
|-------|---------|-----------|----------------|------------|
| [label] | [address] | [n] | [n] | [n] |
```

## Steps

### Step 1 — Load tools

```
ToolSearch: select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__tabs_create_mcp,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__javascript_tool,mcp__claude-in-chrome__find,WebSearch
```

### Step 2 — Gather context before any analysis

Ask both questions in a single message before running anything:

> "Two quick questions before I pull your home's data:
>
> 1. **School-age kids?** Do you have children in school, and if so, what grade levels — elementary (K–5), middle (6–8), and/or high school (9–12)? I'll pull drive times for the relevant levels. If no school-age kids, I'll still grab school ratings since they affect resale value, but I'll skip the drive-time analysis.
>
> 2. **Work destinations?** Where do you commute — full address or intersection is fine — and how many days a week? If you work fully remote, just say so and I'll skip commute."

Wait for the user's response. Record:
- `school_levels`: list of applicable levels from `["elementary", "middle", "high"]` (or `[]` if no school-age kids — still run ratings)
- `run_school_drives`: true if `school_levels` is non-empty
- `destinations`: list of `{label, address, days_per_week}` (or empty if remote)
- `run_commute`: true if `destinations` is non-empty

If `BUYER-PROFILE.md` already exists and has work destinations, read them and confirm rather than re-asking.

### Step 3 — Run property extraction

Call `/redfin <address>` using the browser skill. Extract all fields from the canonical JSON:
`beds`, `baths_full`, `baths_half`, `sqft`, `lot_sqft`, `lot_acres`, `garage_spaces`, `garage_sqft`, `garage_attached`, `stories`, `year_built`, `hoa_fee`, `hoa_frequency`, `has_office`, `has_game_room`, `has_media_room`, `has_loft`, `pool`, `fireplace_count`, `cooling`, `heating`, `rooms_total`, `living_areas`, `dining_areas`.

Normalize `hoa_monthly`:
- Monthly → value as-is
- Quarterly → divide by 3
- Annual → divide by 12
- None → 0

### Step 4 — Run schools analysis

**Step 4a — Extract school names from Redfin (do NOT WebSearch for school names)**

The Redfin listing already contains the exact zoned schools under "Location → School Information" in the property details. Extract them from the page that is still open from Step 3:

```javascript
const bodyText = document.body.innerText;
const idx = bodyText.indexOf('School Information');
idx >= 0 ? bodyText.substring(idx, idx + 500) : 'School Information not found';
```

Parse out `Elementary School Name`, `Middle School Name`, `High School Name`, and `School District` from this block. These are the authoritative zoned school names from the MLS — use them for all subsequent lookups. Do not substitute names found via generic WebSearch.

**Step 4b — Look up ratings for each school by name**

For each school, run a targeted WebSearch using the exact name extracted above:

```
"[School Name]" [ISD Name] GreatSchools rating TEA accountability
```

Also run one search for the district TEA rating:
```
[ISD Name] TEA accountability rating site:schools.texastribune.org OR site:txschools.gov
```

Record per school: GS rating (1–10 or null), TEA rating (A/B/C/D/F or null). Always run ratings for all three levels — resale value depends on the full picture.

**Step 4c — Get drive times (only for levels in `school_levels`)**

For each applicable school, navigate Google Maps with an explicit driving mode URL:

```
https://www.google.com/maps/dir/?api=1&origin=PROPERTY_ADDRESS&destination=SCHOOL_ADDRESS&travelmode=driving
```

Extract the driving time from the page. Google Maps always displays a walking tab alongside the driving result — ignore the walking time (typically 15–25 min for short distances). Confirm the result you record shows "Fastest route" with a distance in miles, not a walking time. For levels not in `school_levels`, set `drive_min: null`.

### Step 5 — Run crime analysis

Execute the `/crime` logic against this address (see `/crime` skill for query patterns):

1. WebSearch local PD stats and crime indices for the city/ZIP
2. Record: grade, violent_rate_per1k, property_rate_per1k, vs_national comparisons, trend

### Step 6 — Run commute analysis

**Skip this step if `run_commute` is false.** Write a single row in the Commute table: `| Remote | — | — | — | — |` and note "works remotely."

If `run_commute` is true: for each destination, execute the `/commute` logic:

1. WebSearch estimated drive times from the property to each destination
2. Record: off_peak_min, peak_min

### Step 7 — Write BASELINE.md

Write `BASELINE.md` to the current working directory using the exact format defined above. Set `generated:` to today's date. Leave fields `null` where data was unavailable.

### Step 8 — Show baseline card

Display a clean summary of everything captured:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 BASELINE — [ADDRESS]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 PROPERTY
   X bed · X full bath · X,XXX sqft · X-car garage [Attached]
   Built XXXX · Lot: X,XXX sqft · Stories: X
   Office: Yes/No · Game room: Yes/No · Pool: Yes/No · Fireplace: X
   HOA: $XX/mo  ·  Cooling: [value]  ·  Heating: [value]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 SCHOOLS
   District: [ISD]  ·  TEA: [grade]
   Elementary  [Name]  GS: X/10  TEA: [X]  Drive: X min
   Middle      [Name]  GS: X/10  TEA: [X]  Drive: X min
   High        [Name]  GS: X/10  TEA: [X]  Drive: X min
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 SAFETY
   Grade: [X]  ·  Violent: X.X/1k ([vs national])
   Property crime: XX.X/1k ([vs national])  ·  Trend: [X]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 COMMUTE
   [Label] → [address]  (X days/wk)
     Off-peak: XX min  ·  Peak: XX min
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 9 — Hand off to profile

Tell the user:

> "Baseline saved to `BASELINE.md`. Run `/profile` next — it will walk through this data and ask what's Critical, Nice-to-have, or Irrelevant for your search, then build your `BUYER-PROFILE.md`."
