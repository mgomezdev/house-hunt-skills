---
name: property-comps
description: "Find comparable recent sales for a DFW property, apply adjustments, and estimate fair market value. Outputs comps table, FMV range, and comps score (0-100)."
trigger: /comps
---

# /comps

Find comparable recent sales, adjust for differences, and estimate fair market value for a DFW property.

## Usage

```
/comps <address>
/comps 1116 Bluestem Dr, Aubrey TX 76227
```

## Output Schema

```
{
  "address": string,
  "list_price": number|null,
  "sqft": number|null,
  "beds": number|null,
  "baths_full": number|null,
  "comps": [{
    "address": string,
    "sale_price": number,
    "sale_date": string,          // "MM/YYYY"
    "sqft": number|null,
    "beds": number|null,
    "baths": number|null,
    "lot_sqft": number|null,
    "year_built": number|null,
    "garage_spaces": number|null,
    "adjustments": {
      "sqft_adj": number,         // positive = comp adjusted up to match subject
      "bath_adj": number,
      "garage_adj": number,
      "lot_adj": number,
      "age_adj": number,
      "features_adj": number
    },
    "adjusted_price": number,
    "price_per_sqft": number|null
  }],
  "fmv_low": number|null,
  "fmv_mid": number|null,
  "fmv_high": number|null,
  "vs_list_pct": number|null,     // positive = list price above FMV (overpriced)
  "verdict": string,              // "Underpriced" | "Fair" | "Overpriced"
  "comps_score": number           // 0-100
}
```

## Steps

### Step 1 — Load tools

```
ToolSearch: select:WebSearch,WebFetch
```

### Step 2 — Get subject property data

If `/redfin` has already been run this session and the canonical JSON is available, use it directly. Otherwise call `/redfin <address>` now.

From the canonical JSON, extract: `list_price`, `sqft`, `beds`, `baths_full`, `lot_sqft`, `year_built`, `garage_spaces`, `has_office`, `pool`.

### Step 3 — Search for comparable sales

Run two `WebSearch` calls:

**Search A** — nearby sold homes matching size and bed count:
```
[city] TX [beds] bedroom sold 2024 2025 site:redfin.com [sqft-100] sqft
```

**Search B** — area comps via multiple sources:
```
[address neighborhood or subdivision] [city] TX comparable sales sold 2024 2025
```

Target: 4–6 comps sold within the last 12 months, within 1 mile, same beds ±1 and sqft ±20%. Accept up to 18 months or 2 miles if closer matches are sparse.

For each comp, extract from search results: address, sale price, sale date, beds, baths, sqft, lot sqft, year built, garage spaces. Leave fields null if not available in snippets.

If a result page has rich structured data (e.g. a Redfin property URL), use `WebFetch` on up to 2 URLs to get missing fields (lot, year built).

### Step 4 — Apply adjustments

Adjust each comp TO match the subject property. All rates are for DFW market:

| Factor | Rate | Direction |
|--------|------|-----------|
| Sqft difference | $75/sqft | Positive if subject is larger |
| Full bath difference | $8,000/bath | Positive if subject has more |
| Garage space difference | $12,000/space | Positive if subject has more |
| Lot sqft difference | $5/sqft (cap ±5,000 sqft) | Positive if subject lot is larger |
| Year built difference | $1,500/year | Positive if subject is newer |
| Office on subject, not comp | +$10,000 | Features adjustment |
| Pool on subject, not comp | +$20,000 | Features adjustment |

```
adjusted_price = sale_price + sqft_adj + bath_adj + garage_adj + lot_adj + age_adj + features_adj
price_per_sqft = adjusted_price / comp_sqft  (null if comp sqft unknown)
```

### Step 5 — Estimate FMV

Sort comps by adjusted_price. Drop the highest and lowest outlier if 5+ comps available. Use the remaining to compute:

```
fmv_low  = min(remaining adjusted prices)
fmv_mid  = mean(remaining adjusted prices), rounded to nearest $1,000
fmv_high = max(remaining adjusted prices)

vs_list_pct = round((list_price - fmv_mid) / fmv_mid * 100, 1)
verdict:
  vs_list_pct < -5%  → "Underpriced"
  vs_list_pct > +5%  → "Overpriced"
  otherwise          → "Fair"
```

### Step 6 — Comps score (0–100)

| Dimension | Max | Criteria |
|-----------|-----|---------|
| Data quality | 25 | 5+ comps=25, 4=20, 3=15, 2=8, 1=3 |
| Price alignment | 25 | Within 5%=25, 5–10%=18, 10–15%=10, >15%=3 |
| Comp proximity | 25 | All <0.5mi=25, most <1mi=18, some >1mi=10, all >1mi=5 |
| Market trend | 25 | Comps trending up=25, flat=18, declining=10 |

`comps_score = sum`

### Step 7 — Present results

Emit the canonical JSON in a `json` block, then the card:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 COMPS — [ADDRESS]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Subject     $XXX,XXX list  ·  X,XXX sqft  ·  $XXX/sqft
 FMV range   $XXX,XXX – $XXX,XXX  (mid $XXX,XXX)
 Verdict     X.X% [over/under] list  →  [Overpriced/Fair/Underpriced]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 COMPARABLE SALES  (X comps · last 12 months)

  Address                    Sold     Sale Price   Adj. Price   $/sqft
  [comp address]            MM/YY    $XXX,XXX     $XXX,XXX     $XXX
  [comp address]            MM/YY    $XXX,XXX     $XXX,XXX     $XXX
  ...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 COMPS SCORE   XX/100
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
