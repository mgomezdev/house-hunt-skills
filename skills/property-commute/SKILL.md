---
name: property-commute
description: "Analyze drive commute times from a DFW property to one or more work destinations. Reads destinations from BUYER-PROFILE.md or accepts them as arguments. Scores each leg and outputs a weighted commute score (0-100)."
trigger: /commute
---

# /commute

Analyze drive commute times from a DFW property to work destinations and produce a commute score.

## Usage

```
/commute <property address>
/commute <property address> to <destination>
/commute 1116 Bluestem Dr, Aubrey TX 76227 to Legacy West, Plano TX
```

If no destination is given, read them from `BUYER-PROFILE.md`. If no profile exists and no destination is provided, ask the user for at least one work address before proceeding.

## Output Schema

```
{
  "property_address": string,
  "destinations": [{
    "label": string,              // e.g. "Work - Legacy West" or user-provided label
    "address": string,
    "days_per_week": number|null, // from profile, or null if unknown
    "off_peak_min": number|null,  // estimated off-peak drive time in minutes
    "peak_min": number|null,      // estimated peak-hour drive time in minutes
    "distance_miles": number|null,
    "annual_drive_cost": number|null,  // miles × 2 × 235 days × $0.21/mi fuel+wear
    "leg_score": number           // 0-100 for this destination
  }],
  "weighted_commute_score": number,  // 0-100; weighted by days_per_week if available
  "vs_current_commute": string|null, // e.g. "8 min longer peak" or null if no baseline
  "commute_score": number            // same as weighted_commute_score (canonical field name)
}
```

## Steps

### Step 1 — Load tools

```
ToolSearch: select:WebSearch
```

### Step 2 — Get destinations

**Priority order:**
1. Destinations passed directly in the command (e.g. `to <address>`)
2. Work destinations in `BUYER-PROFILE.md` — read the file if present; extract each destination's address, label, and days/week
3. Ask the user if neither source provides destinations

If BUYER-PROFILE.md has a "current commute" baseline (peak drive time from current home), record it for comparison.

### Step 3 — Search for drive times

For each destination, run one `WebSearch`:

```
drive time from "[property address]" to "[destination address]" peak hours DFW
```

Extract from results:
- Off-peak drive time (minutes)
- Peak-hour drive time (minutes) — this is the primary metric in DFW
- Route distance (miles)

If search results don't clearly separate peak vs off-peak, use a ±30% heuristic: `peak_min ≈ off_peak_min * 1.35` for DFW highway commutes.

**Annual drive cost (one way × 2 × 235 working days):**
```
annual_drive_cost = distance_miles * 2 * 235 * 0.21
```
(IRS mileage rate minus highway depreciation component; round to nearest $100)

### Step 4 — Score each leg (0–100)

Score is based on **peak-hour drive time**, since that's what the commuter experiences daily:

| Peak drive time | Leg score |
|----------------|-----------|
| ≤ 20 min | 100 |
| 21–30 min | 85 |
| 31–40 min | 70 |
| 41–50 min | 55 |
| 51–60 min | 40 |
| 61–75 min | 22 |
| > 75 min | 5 |

### Step 5 — Weighted commute score

If `days_per_week` is known for each destination:
```
weighted_commute_score = sum(leg_score × days_per_week) / sum(days_per_week)
```

If `days_per_week` is unknown for all destinations:
```
weighted_commute_score = mean(leg_scores)
```

Round to nearest integer. `commute_score = weighted_commute_score`.

**vs_current_commute:** If BUYER-PROFILE.md has current peak commute times for the same destinations, compute the difference per leg and summarize (e.g. "12 min longer peak to Work A").

### Step 6 — Present results

Emit the canonical JSON in a `json` block, then the card:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 COMMUTE — [PROPERTY ADDRESS]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Destination            Off-peak   Peak    Miles   Annual cost
 [label / address]      XX min     XX min  XX.X    $X,XXX
 [label / address]      XX min     XX min  XX.X    $X,XXX
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 vs Current commute:  [X min longer/shorter peak / — if no baseline]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 COMMUTE SCORE   XX/100
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Note: drive times are web-search estimates. Verify in Google Maps before touring.
