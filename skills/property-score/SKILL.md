---
name: property-score
description: "Composite property score for a DFW home. Runs /redfin, /comps, /schools, /crime, /commute, and /homefit, weights by buyer profile (fallback to defaults), outputs score (0-100), grade, and buy signal."
trigger: /score
---

# /score

Full composite evaluation for a DFW property: property data + comps + schools + crime + commute + homefit → weighted score, grade, and buy signal.

## Usage

```
/score <address>
/score 1116 Bluestem Dr, Aubrey TX 76227
```

## Output Schema

```
{
  "address": string,
  "redfin_url": string,

  // Weights used (sum to 1.0)
  "weights": {
    "comps": number,
    "schools": number,
    "crime": number,
    "commute": number,    // 0.0 if no destinations available
    "homefit": number
  },
  "profile_applied": boolean,    // true if BUYER-PROFILE.md was found and used

  // Sub-scores (0-100 each; null if dimension could not be scored)
  "scores": {
    "comps": number|null,
    "schools": number|null,
    "crime": number|null,
    "commute": number|null,  // null when no work destinations available
    "homefit": number|null
  },

  // Composite
  "composite": number,           // weighted sum, rounded to 1 decimal
  "grade": string,               // "A+" | "A" | "B" | "C" | "D" | "F"
  "signal": string,              // "Strong Buy" | "Buy" | "Worth Touring" | "Caution" | "Pass"

  // Hard filter result (from buyer profile)
  "hard_filters_passed": boolean|null,  // null if no profile
  "hard_filter_failures": string[],

  // Key considerations
  "top_considerations": string[],   // 3 specific, actionable items
  "flags": string[]
}
```

**Grade and signal thresholds:**
| Score | Grade | Signal |
|-------|-------|--------|
| 85–100 | A+ | Strong Buy |
| 70–84 | A | Buy |
| 55–69 | B | Worth Touring |
| 40–54 | C | Caution |
| 25–39 | D | Pass |
| 0–24 | F | Avoid |

## Steps

### Step 1 — Load tools

```
ToolSearch: select:WebSearch
```

### Step 2 — Get property data

Call `/redfin <address>` to get the canonical property JSON. If already available from this session, use it directly. Note `list_price`, `sqft`, `beds`, `baths_full`, `garage_spaces`, `has_office`, `lot_sqft`, `hoa_fee`, `tax_history`.

### Step 3 — Determine weights from buyer profile

**Read `BUYER-PROFILE.md` from the current working directory if it exists.**

**If BUYER-PROFILE.md exists:**

First, run hard filter check: for each required attribute in the profile, verify it against the redfin canonical JSON.

```
hard_filters_passed = all required attributes satisfied
hard_filter_failures = list of failures, e.g. "beds=3 < required 4"
profile_applied = true
```

Extract work destinations for commute scoring. If destinations present, commute is included in scoring. If no destinations listed, commute weight = 0 and its weight redistributes.

Derive weights from the profile's ranked priorities. Start from these defaults, then apply the largest boost to the top-ranked priority:

**Default weights (commute destinations available):**
```
comps=0.20, schools=0.25, crime=0.18, commute=0.20, homefit=0.17
```

**Default weights (no commute destinations):**
```
comps=0.25, schools=0.30, crime=0.22, commute=0.00, homefit=0.23
```

Priority boosts (apply to top 2 ranked priorities, then re-normalize to sum 1.0):

| Profile priority | Boosts |
|-----------------|--------|
| School quality | schools +0.07 |
| Commute | commute +0.07 |
| Safety / crime | crime +0.07 |
| Value / price | comps +0.07 |
| Home Size / Rooms | homefit +0.07 |
| Low maintenance | homefit +0.05 |
| Lot / Outdoor | homefit +0.04 |

**If no BUYER-PROFILE.md:**
```
weights = { comps: 0.25, schools: 0.30, crime: 0.22, commute: 0.00, homefit: 0.23 }
hard_filters_passed = null
hard_filter_failures = []
profile_applied = false
```
Add a flag: "No BUYER-PROFILE.md found — commute not scored, using default weights. Run /profile to personalize."

### Step 4 — Run comps analysis

Execute the `/comps` logic inline:

1. WebSearch for 4–6 comparable recent sales (query patterns and adjustment rates in `/comps` skill)
2. Apply sqft/bath/garage/lot/age/features adjustments at DFW rates
3. Compute FMV range and `vs_list_pct`
4. Record `comps_score` (0–100)

### Step 5 — Run schools analysis

Execute the `/schools` logic inline:

1. WebSearch GreatSchools ratings and TEA accountability for this address
2. Weight elementary 40%, middle 30%, high 30%
3. Record `schools_score` (0–100)

### Step 6 — Run crime analysis

Execute the `/crime` logic inline:

1. WebSearch local PD stats, CrimeGrade, or NeighborhoodScout for this city/ZIP
2. Score violent crime (0–55 pts) + property crime (0–45 pts) vs national averages
3. Record `crime_score` (0–100)

### Step 7 — Run homefit analysis

Execute the `/homefit` logic inline:

1. Diff the redfin canonical JSON against the profile's current home attributes (beds, baths, sqft, lot, garage, stories, HOA)
2. Check all hard requirements against canonical JSON fields
3. Check preferred features against canonical fields and room names
4. Estimate 5-year CapEx from `year_built` and sqft
5. Record `homefit_score` (0–100); cap at 49 if any hard filter fails

### Step 8 — Run commute analysis

**Only if destinations are available** (from profile or arguments):

Execute the `/commute` logic inline:

1. For each destination, WebSearch estimated peak-hour drive time from property address
2. Score each leg by peak drive time (≤20 min=100, 21–30=85, 31–40=70, 41–50=55, 51–60=40, 61–75=22, >75=5)
3. Weight legs by days/week if available; otherwise take the mean
4. Record `commute_score` (0–100)

If no destinations available, set `scores.commute = null` and `weights.commute = 0.00`. Re-normalize the other three weights to sum to 1.0.

### Step 9 — Compute composite score

```
composite = round(
  (scores.comps    * weights.comps)                           +
  (scores.schools  * weights.schools)                         +
  (scores.crime    * weights.crime)                           +
  (scores.commute  * weights.commute if not null else 0)      +
  (scores.homefit  * weights.homefit),
  1
)
```

Look up grade and signal from threshold table.

**If hard_filters_passed = false:** cap composite at 49, set signal to "Caution" minimum. List filter failures in flags.

**Top 3 considerations:** derive from the lowest-scoring dimension(s) and notable data points (e.g. overpriced by X%, weak elementary rating, commute >45 min peak, high CapEx risk).

**Flags:** surface issues requiring follow-up (high HOA, sharp tax increase, no comp data, hard filter failure, commute not scored due to missing destinations, CapEx risk from property age).

### Step 10 — Present results

Emit the canonical JSON in a `json` block, then the scorecard:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 SCORE — [ADDRESS]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [GRADE]  [SIGNAL]  ·  [composite]/100
 Profile: [Applied / Not found — using defaults]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Dimension       Score   Weight   Contribution
 Comps/Value     XX/100   XX%       XX.X
 Schools         XX/100   XX%       XX.X
 Crime/Safety    XX/100   XX%       XX.X
 Commute         XX/100   XX%       XX.X  (or "—  not scored")
 Homefit         XX/100   XX%       XX.X
                                   ──────
 COMPOSITE                           XX.X
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 HARD FILTERS   [All passed / X failed: list]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 TOP 3 CONSIDERATIONS
   1. [Specific, actionable item]
   2. [Specific, actionable item]
   3. [Specific, actionable item]

 FLAGS
   · [Any notable issues, or "None"]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 PROPERTY SNAPSHOT
   $XXX,XXX  ·  X,XXX sqft  ·  $XXX/sqft
   X bed  ·  X full bath  ·  Built XXXX
   Lot: X,XXX sqft  ·  Garage: X spaces
   HOA: $XXX/[freq]  ·  Tax (last yr): $XX,XXX
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then offer: "Want me to run `/comps`, `/schools`, `/crime`, `/commute`, or `/homefit` standalone for the full detailed report on any dimension?"
