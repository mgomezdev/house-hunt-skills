---
name: property-schools
description: "Look up school ratings, TEA accountability data, and drive times from a DFW property to each zoned school. Reads BUYER-PROFILE.md for current school drive baseline. Outputs school table and schools score (0-100)."
trigger: /schools
---

# /schools

Look up zoned school ratings and drive times for a DFW property address. Compares drive times against buyer's current baseline when available.

## Usage

```
/schools <address>
/schools 1116 Bluestem Dr, Aubrey TX 76227
```

## Output Schema

```
{
  "address": string,
  "district": string,
  "district_tea_rating": string|null,    // "A" | "B" | "C" | "D" | "F" | null
  "schools": [{
    "name": string,
    "type": string,                       // "Elementary" | "Middle" | "High"
    "grades": string,                     // e.g. "K-5"
    "greatschools_rating": number|null,   // 1-10
    "tea_rating": string|null,            // "A" | "B" | "C" | "D" | "F" | null
    "distance_miles": number|null,
    "drive_min": number|null,             // estimated drive time from property (peak)
    "baseline_drive_min": number|null,    // from BUYER-PROFILE.md; null if not set
    "drive_delta_min": number|null,       // drive_min - baseline_drive_min; positive = longer
    "enrollment": number|null,
    "notes": string|null                  // e.g. "magnet", "charter", "boundary school"
  }],
  "boundary_schools_only": boolean,
  "schools_score": number                 // 0-100
}
```

## Steps

### Step 1 — Load tools

```
ToolSearch: select:WebSearch,WebFetch
```

### Step 2 — Read buyer profile baseline

Check for `BUYER-PROFILE.md` in the current working directory. If present, read it and extract any stored school drive times for the buyer's current home. These are stored under a section like "School Drive Times" or "Current Schools" with fields:

```
Elementary drive: X min
Middle drive: X min
High drive: X min
```

Record these as `baseline_drive_min` per school type. If no profile or no school drive data in profile, all `baseline_drive_min` values are `null`.

### Step 3 — Extract zoned school names from Redfin

**Do NOT WebSearch for school names** — generic searches return wrong schools. Redfin's listing contains the exact zoned schools under "Location → School Information" in the property details. If the Redfin tab is still open from a prior `/redfin` run this session, extract from it:

```javascript
const bodyText = document.body.innerText;
const idx = bodyText.indexOf('School Information');
idx >= 0 ? bodyText.substring(idx, idx + 500) : 'School Information not found';
```

Parse out `Elementary School Name`, `Middle School Name`, `High School Name`, and `School District`. If the Redfin tab is not available, navigate to the property page first using the autocomplete API (see `/redfin` skill Step 3), then run the extraction above.

### Step 4 — Look up ratings for each school by name

Using the exact school names from Step 3, run targeted WebSearch calls — one per school:

```
"[Exact School Name]" [ISD Name] GreatSchools rating TEA accountability
```

Also run one WebSearch for the district-level TEA rating:
```
[ISD Name] TEA accountability rating site:schools.texastribune.org OR site:txschools.gov
```

If a GreatSchools page URL is returned, `WebFetch` it to get the specific numeric rating. TEA ratings: A (Exemplary) / B (Recognized) / C (Acceptable) / D / F. Record district-level and per-campus ratings where available.

### Step 5 — Get drive times to each school

For each school, navigate Google Maps with an explicit driving mode URL — do not WebSearch for drive time:

```
https://www.google.com/maps/dir/?api=1&origin=PROPERTY_ADDRESS&destination=SCHOOL_ADDRESS&travelmode=driving
```

Read the driving time from the page. Google Maps always shows a walking tab alongside the driving result — ignore it (typically 15–25 min for short distances). Confirm you are reading the "Fastest route" entry that shows distance in miles. If the school is within 0.5 mi, set `drive_min = 4` (short in-neighborhood drive).

Compute `drive_delta_min = drive_min - baseline_drive_min` for each school where both values are available. Positive = this property has a longer school run than current home.

### Step 7 — Schools score (0–100)

**Quality sub-score per school:**

GreatSchools → points: 9–10=100, 7–8=80, 5–6=60, 3–4=40, 1–2=20, null=50

TEA → points: A=100, B=80, C=60, D=35, F=10, null=50

`quality_score = (greatschools_pts * 0.6) + (tea_pts * 0.4)`

**Drive time modifier per school (applied after quality score):**

| Drive time | Modifier |
|-----------|---------|
| ≤ 5 min (walkable) | +5 |
| 6–10 min | +2 |
| 11–15 min | 0 |
| 16–20 min | −3 |
| 21–30 min | −8 |
| > 30 min | −15 |

`school_score = min(100, max(0, quality_score + drive_modifier))`

**Weighted composite by school type:**
```
schools_score = round(
  (elementary_score * 0.40) +
  (middle_score     * 0.30) +
  (high_score       * 0.30)
)
```

Redistribute weight evenly across present types if a type is missing.

### Step 8 — Present results

Emit the canonical JSON in a `json` block, then the card:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 SCHOOLS — [ADDRESS]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 District    [ISD Name]  ·  TEA: [A/B/C/D/F or —]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 School              Type    GS    TEA   Drive    vs Current
 [School Name]       Elem    X/10  [A]   X min    +X min / −X min / baseline n/a
 [School Name]       Middle  X/10  [B]   X min    +X min / −X min / baseline n/a
 [School Name]       High    X/10  [B]   X min    +X min / −X min / baseline n/a
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 SCHOOLS SCORE   XX/100
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- Show `+X min` in the "vs Current" column when this property's drive is longer than baseline, `−X min` when shorter, `baseline n/a` when no profile baseline exists.
- Use `—` for any null field.
- Note drive times are estimates from web search; verify via Google Maps before touring.
