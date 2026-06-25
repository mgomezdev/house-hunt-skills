---
name: redfin-lookup
description: "Navigate Redfin.com in local Chrome to extract structured property details. JS-based extraction returns canonical JSON directly — no model-side mapping. DFW/NTREIS only."
trigger: /redfin
---

# /redfin

Look up a DFW property on Redfin.com using local Chrome and return a canonical JSON object plus a human-readable comparison card.

## Usage

```
/redfin <address>
/redfin 1116 Bluestem Dr, Aubrey TX 76227
```

## Scope

**DFW (Dallas-Fort Worth) area only.** Room dimension extraction relies on NTREIS MLS "Room N Information" blocks. Other MLS systems (e.g. FL Stellar) don't publish per-room data — `rooms` will be `[]` outside DFW.

## Output Schema

Every run outputs one canonical JSON object (all fields always present) followed by a comparison card. Downstream agents must expect this exact shape.

```
{
  address, redfin_url,
  list_price, price_per_sqft,
  sqft, beds, baths_full, baths_half,       // baths_half default 0
  stories, year_built,
  lot_sqft, lot_acres,
  garage_spaces, garage_sqft, garage_attached,  // garage_spaces default 0
  rooms_total, living_areas, dining_areas,
  has_office, has_game_room, has_media_room, has_loft,
  rooms: [{name, level, dimensions, sqft_approx}],
  fireplace_count,                           // default 0
  pool, hoa_fee, hoa_frequency,
  cooling, heating,
  tax_history: [{year, amount, change_pct}], // up to 5 years desc; default []
  rooms_data_available
}
```

**Defaults:** `baths_half=0`, `garage_spaces=0`, `fireplace_count=0`, `rooms=[]`, `tax_history=[]`. Room flags (`has_*`) are `false` (not `null`) when `rooms_data_available=true` but type absent; `null` when `rooms_data_available=false`.

## Steps

### Step 1 — Load browser tools

Load all required tools in one call:

```
ToolSearch: select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__tabs_create_mcp,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__javascript_tool,mcp__claude-in-chrome__find
```

If the JS-based search fails and keyboard interaction is needed, load `mcp__claude-in-chrome__computer` in a second ToolSearch call at that point.

### Step 2 — Open a fresh tab

Call `tabs_context_mcp`, then `tabs_create_mcp`. Record the tab ID — use it for every subsequent call.

### Step 3 — Resolve property URL via autocomplete API

Navigate to `https://www.redfin.com`, then call `javascript_tool` to fetch the property URL directly (bypasses search form and results page entirely):

```javascript
(async function() {
  const q = encodeURIComponent('__ADDRESS__');
  const resp = await fetch('/stingray/do/location-autocomplete?location=' + q + '&v=2');
  const text = await resp.text();
  const data = JSON.parse(text.slice(text.indexOf('&&') + 2));
  const url = data.payload?.exactMatch?.url
    || data.payload?.sections?.[0]?.rows?.[0]?.url;
  if (url) { location.href = 'https://www.redfin.com' + url; return 'navigating: ' + url; }
  return 'not found — keys: ' + JSON.stringify(Object.keys(data.payload || {}));
})()
```

Replace `__ADDRESS__` with the actual address string.

**Fallback:** If autocomplete returns `not found`, use `find` to locate the search input, fill it using the React native setter, and submit the form.

### Step 4 — Confirm property page loaded

```javascript
document.readyState + ' | ' + document.title + ' | ' + location.href
```

Confirm URL contains `/home/`. If on a search results page, click the top result with `find` using selector `a[href*="/home/"]`.

### Step 5 — Scroll to bottom

```javascript
window.scrollTo(0, document.body.scrollHeight); 'scrolled'
```

This triggers lazy-loaded sections (tax history, etc.). The natural delay before the next tool call is sufficient for them to render.

### Step 6 — Extract and return canonical JSON

**Replace `__ADDRESS__` before calling.** This single JS call does all extraction and mapping, returning the complete canonical object. No further model-side mapping needed.

```javascript
(function(addr) {
  const f = {}, rooms = [], errors = [];
  let tax = [];
  const pq = s => document.querySelector(s)?.textContent?.trim();
  const pn = s => { if (!s) return null; const n = parseFloat(s.replace(/[^0-9.]/g,'')); return isNaN(n) ? null : n; };
  const pi = s => { if (!s) return null; const n = parseInt(s.replace(/[^0-9]/g,'')); return isNaN(n) ? null : n; };

  const price  = pq('[data-rf-test-id="abp-price"]');
  const sqftRaw = pq('[data-rf-test-id="abp-sqFt"]');
  const bedsRaw = pq('[data-rf-test-id="abp-beds"]');

  const anchor = ['Year Built','Garage','Lot Size','Bathrooms'];
  const cands = [...document.querySelectorAll('div,section')].filter(el =>
    anchor.every(a => el.textContent.includes(a)) && el.children.length > 3 && el.children.length < 150
  );
  const factsEl = cands.sort((a,b) => a.textContent.length - b.textContent.length)[0];

  if (factsEl) {
    const text = factsEl.innerText;
    for (const line of text.split('\n')) {
      const c = line.indexOf(':');
      if (c > 0 && c < line.length-1) {
        const k = line.substring(0,c).trim().toLowerCase();
        const v = line.substring(c+1).trim();
        if (k && v) f[k] = v;
      }
    }
    const rr = /Room (\d+) Information\nRoom Type: ([^\n]+)\nRoom Level: ([^\n]+)\n(?:[^\n]+\n)*?Room Dimensions: ([^\n]+)/g;
    let m;
    while ((m = rr.exec(text)) !== null) {
      const d = m[4].trim();
      const p = d.split('x').map(s => parseInt(s.trim()));
      rooms.push({ name: m[2].trim(), level: parseInt(m[3].trim()), dimensions: d,
        sqft_approx: p.length===2 && !isNaN(p[0]) && !isNaN(p[1]) ? p[0]*p[1] : null });
    }
  } else { errors.push('facts section not found'); }

  try {
    const allEls = [...document.querySelectorAll('div,section,table,tbody')];
    const taxEl = allEls.find(el =>
      (el.tagName==='TBODY'||el.tagName==='TABLE') &&
      el.closest('[class*="tax"],[class*="Tax"],[data-rf-test-id*="tax"]')
    ) || allEls.find(el => el.textContent.includes('Property Tax History') && el.children.length < 50);

    if (taxEl) {
      for (const row of taxEl.querySelectorAll('tr,[class*="row"],[class*="Row"]')) {
        const cells = [...row.querySelectorAll('td,[class*="cell"],[class*="Cell"]')].map(c => c.textContent.trim()).filter(Boolean);
        if (cells.length < 2) continue;
        const ym = cells[0].match(/^(20\d{2}|19\d{2})$/); if (!ym) continue;
        const aStr = cells.find(c => /\$[\d,]+/.test(c));
        const pStr = cells.find(c => /%/.test(c) && c !== cells[0]);
        tax.push({ year: parseInt(ym[1]),
          amount: aStr ? parseInt(aStr.replace(/[^0-9]/g,'')) : null,
          change_pct: pStr ? parseFloat(pStr.replace(/[^0-9.\-]/g,'')) * (pStr.includes('-') ? -1 : 1) : null });
      }
    }

    if (!tax.length) {
      const bt = document.body.innerText;
      const ts = bt.indexOf('Property Tax History');
      if (ts >= 0) {
        const chunk = bt.substring(ts, ts+1500);
        const lr = /\b(20\d{2}|19\d{2})\b[^\n]*\$([\d,]+)[^\n]*([+-]?[\d.]+%)?/g;
        let tm;
        while ((tm = lr.exec(chunk)) !== null) {
          const y = parseInt(tm[1]);
          if (!tax.find(t => t.year===y))
            tax.push({ year: y, amount: parseInt(tm[2].replace(/,/g,'')),
              change_pct: tm[3] ? parseFloat(tm[3].replace('%','')) * (tm[3].startsWith('-') ? -1 : 1) : null });
        }
      }
    }
    tax = tax.sort((a,b) => b.year - a.year).slice(0,5);
  } catch(e) { errors.push('tax:' + e.message); }

  let yb = null;
  try {
    for (const s of document.querySelectorAll('script[type="application/ld+json"]')) {
      const d = JSON.parse(s.textContent); if (d.yearBuilt) { yb = parseInt(d.yearBuilt); break; }
    }
  } catch(e) {}

  const lp = pi(price);
  const sq = pn(sqftRaw) || pn(f['living area']);
  const la = pn(f['lot size acres']);
  const ls = pn(f['lot size square feet']);
  const lotSqft = ls ? Math.round(ls) : (la ? Math.round(la*43560) : null);
  const gw = pn(f['garage width']), gl = pn(f['garage length']);
  const park = (f['parking features'] || '').toLowerCase();
  const hasRooms = rooms.length > 0;
  const freq = (f['association fee frequency'] || '').toLowerCase();
  const hf = freq.includes('month') ? 'Monthly' : freq.includes('quarter') ? 'Quarterly' :
    freq.includes('annual') || freq.includes('year') ? 'Annual' : (freq || null);
  const pf = (f['pool features'] || '').toLowerCase();
  const pool = pf ? (pf.includes('no pool') ? false : true) : null;
  const attached = f['has attached garage'] ? true :
    (park.includes('attached') && !park.includes('detached') ? true :
     park.includes('detached') ? false : null);

  return JSON.stringify({
    address: addr, redfin_url: location.href,
    list_price: lp, price_per_sqft: (lp && sq) ? Math.round(lp/sq) : null,
    sqft: sq ? Math.round(sq) : null, beds: pn(bedsRaw) ? Math.round(pn(bedsRaw)) : null,
    baths_full: pi(f['bathrooms full']), baths_half: pi(f['bathrooms half']) || 0,
    stories: pn(f['stories']) || pn(f['levels']) || null,
    year_built: pi(f['year built']) || yb,
    lot_sqft: lotSqft, lot_acres: la,
    garage_spaces: pi(f['garage spaces']) || 0,
    garage_sqft: (gw && gl) ? Math.round(gw*gl) : null,
    garage_attached: attached,
    rooms_total: pi(f['room count']),
    living_areas: pi(f['number of living areas']),
    dining_areas: pi(f['number of dining areas']),
    has_office:     hasRooms ? rooms.some(r => /office|study/i.test(r.name)) : null,
    has_game_room:  hasRooms ? rooms.some(r => /game/i.test(r.name))         : null,
    has_media_room: hasRooms ? rooms.some(r => /media/i.test(r.name))        : null,
    has_loft:       hasRooms ? rooms.some(r => /loft/i.test(r.name))         : null,
    rooms: rooms,
    fireplace_count: pi(f['fireplaces total']) || 0,
    pool: pool, hoa_fee: pn(f['association fee']), hoa_frequency: hf,
    cooling: f['cooling'] || null, heating: f['heating'] || null,
    tax_history: tax, rooms_data_available: hasRooms,
    _errors: errors.length ? errors : undefined
  });
})('__ADDRESS__')
```

The return value is the complete canonical JSON. Parse and emit it directly.

**If `_errors` includes `'facts section not found'`:** run a fallback to get raw MLS text:

```javascript
const txt = document.body.innerText;
const s = txt.indexOf('Year Built');
s >= 0 ? txt.substring(Math.max(0,s-500), s+3000) : 'Year Built not on page'
```

Then manually parse key-value pairs from the returned text and reconstruct the canonical object.

**If CAPTCHA / bot block:** inform the user, ask them to navigate to the property in Chrome manually, then re-invoke the skill against the already-loaded tab.

Do NOT take screenshots unless navigation completely fails.

### Step 7 — Present results

Emit the canonical JSON in a `json` fenced code block, then immediately render the comparison card:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [ADDRESS]
 [REDFIN_URL]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 PRICE          $X,XXX,XXX   ($X,XXX/sqft)

 TAX HISTORY
   XXXX   $XX,XXX   (+X.X%)
   XXXX   $XX,XXX   (+X.X%)
   (Not available)               ← when tax_history is []
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 SIZE           X,XXX sqft  ·  X stories  ·  Built XXXX
 BEDS/BATHS     X bed  ·  X full bath  ·  X half bath
 LOT            X,XXX sqft  (X.XX acres)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GARAGE         X spaces  ·  XXX sqft  ·  [Attached/Detached/—]
 FIREPLACE      X  |  POOL  Yes/No/—  |  HOA  $X/[freq] or None
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 ROOMS (X total · X living · X dining)
   Office Yes/No/—   Game Room Yes/No/—   Media Yes/No/—   Loft Yes/No/—

   [Room Name]   Lvl X   XX × XX   (~XXX sqft)
   ...
   (Room dimensions not available for this listing)   ← when rooms[] is empty
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 SYSTEMS
   Cooling:  [value or —]
   Heating:  [value or —]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Use `—` for any `null` field. Then ask: "Want me to close the Redfin tab, or leave it open?"
