---
name: property-homefit
description: "Assess how well a DFW property fits the buyer's lifestyle, requirements, and household. Diffs redfin canonical JSON against BUYER-PROFILE.md (current home + requirements). Estimates condition and 5-year CapEx from year built. Outputs homefit score (0-100)."
trigger: /homefit
---

# /homefit

Assess lifestyle fit, attribute match, and condition for a DFW property. Requires the redfin canonical JSON and reads `BUYER-PROFILE.md` when available.

## Usage

```
/homefit <address>
/homefit 1116 Bluestem Dr, Aubrey TX 76227
```

## Output Schema

```
{
  "address": string,

  // Attribute delta — property vs current home (null when no profile)
  "attribute_delta": {
    "beds":           { "current": number|null, "property": number|null, "delta": number|null },
    "baths_full":     { "current": number|null, "property": number|null, "delta": number|null },
    "sqft":           { "current": number|null, "property": number|null, "delta": number|null },
    "lot_sqft":       { "current": number|null, "property": number|null, "delta": number|null },
    "garage_spaces":  { "current": number|null, "property": number|null, "delta": number|null },
    "stories":        { "current": number|null, "property": number|null, "delta": number|null },
    "hoa_monthly":    { "current": number|null, "property": number|null, "delta": number|null }
  },

  // Hard requirement check
  "hard_filters_passed": boolean|null,    // null if no profile
  "hard_filter_results": [{
    "requirement": string,                // e.g. "min_beds: 4"
    "property_value": string,             // e.g. "beds: 3"
    "passed": boolean
  }],

  // Room / layout flags (from redfin canonical JSON)
  "has_office":      boolean|null,
  "has_game_room":   boolean|null,
  "has_media_room":  boolean|null,
  "has_loft":        boolean|null,
  "room_count":      number|null,
  "living_areas":    number|null,

  // Preferred features
  "preferred_features_present":  string[],   // preferred items found in property
  "preferred_features_absent":   string[],   // preferred items not found

  // Condition & CapEx
  "year_built":         number|null,
  "property_age_years": number|null,
  "condition_tier":     string,    // "New" | "Modern" | "Mid-Age" | "Aging" | "Dated"
  "capex_5yr_low":      number,    // estimated 5-year CapEx low ($)
  "capex_5yr_high":     number,    // estimated 5-year CapEx high ($)
  "capex_notes":        string[],  // specific systems nearing end-of-life

  // Score
  "homefit_score": number          // 0-100
}
```

## Steps

### Step 1 — Get property data

Use the redfin canonical JSON from `/redfin <address>` if already available this session. Otherwise call `/redfin <address>` now.

Extract: `beds`, `baths_full`, `baths_half`, `sqft`, `lot_sqft`, `lot_acres`, `garage_spaces`, `stories`, `year_built`, `hoa_fee`, `hoa_frequency`, `has_office`, `has_game_room`, `has_media_room`, `has_loft`, `rooms`, `rooms_total`, `living_areas`, `pool`, `fireplace_count`, `cooling`, `heating`.

### Step 2 — Read buyer profile

Read `BUYER-PROFILE.md` from the current working directory if it exists. Extract:

- **Current home:** beds, baths_full, sqft, lot_sqft, garage_spaces, stories, hoa_fee, hoa_frequency
- **Hard requirements:** min_beds, min_baths_full, min_sqft, max_price, min_garage_spaces, must_have_office, max_hoa_monthly
- **Preferred features:** bullet list
- **Household:** adults, children ages, pets
- **Financial:** budget (for affordability check against list_price)

If no profile, skip the delta and hard-filter steps; set all `null`.

### Step 3 — Attribute delta

For each attribute in `attribute_delta`, compute:
```
delta = property_value - current_home_value
```

Normalize HOA to monthly:
- Monthly → value as-is
- Quarterly → divide by 3
- Annual → divide by 12

Flag notable deltas (magnitude >20% of current value) for the summary.

### Step 4 — Hard filter check

For each hard requirement in profile, compare to the property value from the canonical JSON:

| Requirement key | Property field | Pass condition |
|-----------------|---------------|----------------|
| min_beds | beds | property >= min |
| min_baths_full | baths_full | property >= min |
| min_sqft | sqft | property >= min |
| max_price | list_price | list_price <= max_price (or null if off-market) |
| min_garage_spaces | garage_spaces | property >= min |
| must_have_office | has_office | property == true |
| max_hoa_monthly | hoa (normalized to monthly) | property <= max (or 0 means no HOA) |

`hard_filters_passed = all passed`

### Step 5 — Preferred features check

Map each item in the profile's preferred features list to available canonical fields or room names:

| Common preference | Check |
|------------------|-------|
| game room | `has_game_room` |
| office / study | `has_office` |
| pool | `pool` |
| single story | `stories == 1` |
| large lot (>10k sqft) | `lot_sqft > 10000` |
| covered patio / outdoor | check `rooms` for "patio", "outdoor" types |
| loft | `has_loft` |
| fireplace | `fireplace_count > 0` |
| media room | `has_media_room` |

For preferences not mappable to canonical fields, note them in `preferred_features_absent` with "(verify at showing)".

### Step 6 — Condition and CapEx estimate

Compute `property_age_years = 2026 - year_built` (null if year_built null).

**Condition tier:**
| Age | Tier |
|-----|------|
| 0–5 yrs | New |
| 6–12 yrs | Modern |
| 13–20 yrs | Mid-Age |
| 21–30 yrs | Aging |
| 30+ yrs | Dated |

**5-year CapEx estimate (DFW market rates):**

| Age | Low | High | Primary drivers |
|-----|-----|------|----------------|
| 0–5 | $2,000 | $6,000 | Warranty items, minor repairs |
| 6–12 | $6,000 | $15,000 | Water heater, appliances |
| 13–20 | $15,000 | $35,000 | HVAC replacement, water heater, appliances |
| 21–30 | $30,000 | $55,000 | Roof + HVAC + exterior |
| 30+ | $50,000 | $90,000 | Multiple major systems |

Scale by sqft: if `sqft > 3,000`, add 15% to both bounds. If `sqft < 1,800`, subtract 10%.

**CapEx notes:** list specific systems at or near end of useful life based on age:
- Roof: 25–30 yr lifespan — flag if age ≥ 20
- HVAC: 15–20 yr lifespan — flag if age ≥ 13
- Water heater: 10–15 yr lifespan — flag if age ≥ 10
- Exterior paint: 7–10 yr — flag if age ≥ 8

Note: these are estimates from year built. Actual system ages depend on replacement history not visible in listing data. Flag for inspection.

### Step 7 — Homefit score (0–100)

**Hard requirement match (35 pts):**
- All pass → 35
- One failure → 20
- Two failures → 8
- Three+ failures → 0

**Attribute alignment vs current home (15 pts):**  
Start at 15. Deduct 3 pts per attribute that is *worse* than current home on a metric the profile ranks in its top 3 priorities (e.g. if "Home Size" is priority #2 and sqft delta is negative, deduct 3). Cap deductions at 12.

**Preferred features present (15 pts):**
```
pts = round(15 * (preferred_present / total_preferred))
```
If no preferred features listed, award full 15 pts.

**Layout suitability (10 pts):**
- Has dedicated office when profile has children or `must_have_office=true`: +4
- `living_areas >= 2` for households with children: +3
- Single story when profile adults include anyone 60+: +3 (or 0 if not applicable)
- Adjust based on household composition from profile

**Condition score (25 pts):**
| Condition tier | Pts |
|---------------|-----|
| New | 25 |
| Modern | 20 |
| Mid-Age | 14 |
| Aging | 7 |
| Dated | 2 |

`homefit_score = hard_match + attribute_alignment + preferred_features + layout + condition`

If `hard_filters_passed = false`, cap at 49.

### Step 8 — Present results

Emit the canonical JSON in a `json` block, then the card:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 HOMEFIT — [ADDRESS]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 HOMEFIT SCORE   XX/100
 Hard filters:   [All passed / X failed — list]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 ATTRIBUTE DELTA   (property vs your current home)

               Current   Property   Delta
 Beds            X         X         [+X / −X / =]
 Baths           X         X         [+X / −X / =]
 Sqft          X,XXX     X,XXX       [+XXX / −XXX]
 Lot sqft      X,XXX     X,XXX       [+XXX / −XXX]
 Garage          X         X         [+X / −X / =]
 Stories         X         X         [same / different]
 HOA/mo        $XXX      $XXX        [+$XX / −$XX / =]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 ROOMS & FEATURES
   Office [Yes/No]  Game Room [Yes/No]  Pool [Yes/No]
   Fireplace: X  ·  Living areas: X  ·  Total rooms: X

 Preferred present:  [list or "none"]
 Preferred absent:   [list or "none"]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 CONDITION   [Tier]  ·  Built [YEAR]  ([X] years old)
 5-yr CapEx estimate:  $XX,XXX – $XX,XXX
 Watch:  [list of systems nearing end-of-life, or "None flagged"]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
