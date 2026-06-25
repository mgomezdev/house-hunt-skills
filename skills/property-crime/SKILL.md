---
name: property-crime
description: "Look up crime statistics and safety rating for a DFW property's neighborhood. Searches local PD data and crime indices. Outputs crime breakdown and crime score (0-100, higher = safer)."
trigger: /crime
---

# /crime

Look up neighborhood crime statistics and safety rating for a DFW property address.

## Usage

```
/crime <address>
/crime 1116 Bluestem Dr, Aubrey TX 76227
```

## Output Schema

```
{
  "address": string,
  "city": string,
  "zip": string,
  "overall_grade": string,              // "A" | "B" | "C" | "D" | "F"
  "violent_crime_rate": number|null,    // incidents per 1,000 residents/year
  "property_crime_rate": number|null,   // incidents per 1,000 residents/year
  "vs_national_violent": string|null,   // e.g. "42% below national avg"
  "vs_national_property": string|null,
  "vs_city_avg": string|null,           // e.g. "15% below city avg"
  "trend": string|null,                 // "Improving" | "Stable" | "Worsening"
  "top_concerns": string[],             // specific crime types that are elevated, if any
  "data_source": string,                // primary source used
  "crime_score": number                 // 0-100, higher = safer
}
```

**National averages for reference (FBI UCR):**
- Violent crime: ~4.0 per 1,000 residents
- Property crime: ~19.6 per 1,000 residents

## Steps

### Step 1 — Load tools

```
ToolSearch: select:WebSearch,WebFetch
```

### Step 2 — Parse location from address

Extract city name, ZIP code, and any identifiable subdivision/neighborhood from the address.

### Step 3 — Search for crime data

Run three `WebSearch` calls, in priority order. Use the best data found across all three.

**Search A** — City/local PD statistics (most authoritative):
```
[city] TX police department crime statistics 2023 2024 annual report
```

**Search B** — Neighborhood-level crime index:
```
[city] TX [ZIP code] crime rate safety statistics neighborhood
```

**Search C** — Aggregator sites for normalized data:
```
[address or city ZIP] crime grade safety score site:crimegrade.org OR site:neighborhoodscout.com OR site:areavibes.com
```

If a CrimeGrade.org or NeighborhoodScout page is returned in results, `WebFetch` it to get structured crime rates.

### Step 4 — Extract and normalize

From search results and any fetched pages, extract:

- Violent crime rate (per 1,000 residents): includes assault, robbery, homicide, rape
- Property crime rate (per 1,000 residents): includes burglary, theft, auto theft
- Any noted elevated crime categories (e.g. "auto theft 30% above state avg")
- Year-over-year or multi-year trend
- Primary data source (city PD report, FBI UCR, CrimeGrade, etc.)

Compute comparisons vs national averages:
```
vs_national_violent  = round((violent_rate - 4.0) / 4.0 * 100, 0)%
vs_national_property = round((property_rate - 19.6) / 19.6 * 100, 0)%
format as "X% below" or "X% above"
```

If only an overall crime grade (A–F) is available and no rates, skip rate fields (null) and use grade directly.

### Step 5 — Crime score (0–100, higher = safer)

Score is built from violent and property crime rates relative to national average:

**Violent crime (0–55 pts):**
- ≥60% below national avg → 55
- 30–59% below → 45
- 10–29% below → 38
- At national avg (±10%) → 28
- 10–29% above → 18
- 30–59% above → 8
- ≥60% above → 0

**Property crime (0–45 pts):**
- ≥50% below national avg → 45
- 25–49% below → 37
- 10–24% below → 30
- At national avg (±10%) → 22
- 10–24% above → 14
- 25–49% above → 6
- ≥50% above → 0

`crime_score = violent_pts + property_pts`

**If only a letter grade is available (no rates):**
A=90, B=75, C=55, D=35, F=15

**Overall grade from score:**
90–100=A, 75–89=B, 55–74=C, 35–54=D, 0–34=F

### Step 6 — Present results

Emit the canonical JSON in a `json` block, then the card:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 CRIME & SAFETY — [ADDRESS]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Overall grade    [A/B/C/D/F]   Trend: [Improving/Stable/Worsening/—]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    Rate/1,000   vs National    vs City
 Violent crime       X.X          XX% below/above   XX% below/above
 Property crime      XX.X         XX% below/above   XX% below/above
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Elevated concerns:  [none / specific types if flagged]
 Source:             [data source]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 CRIME SCORE   XX/100  (higher = safer)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Use `—` for null fields.
