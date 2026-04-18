# FlatFinder Implementation Plan

## Project Overview

FlatFinder is a real estate listing aggregation platform with:
1. **Root scraper** (`flatfinder_scraper.py`) - Browser-use AI agent for Toronto rentals (Kijiji, Zumper, etc.)
2. **Monorepo service** (`flatfinder-housing-revolutionized/packages/scraper/service/`) - FastAPI service for UK rentals (Rightmove, Zoopla, OpenRent)
3. **Supabase database** - PostgreSQL with RLS for listing storage
4. **Landing page** (`flatfinder-landing.html`) - Marketing site to display listings

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         GITHUB ACTIONS (daily_scrape.yml)               │
│                              Runs at 06:17 UTC daily                    │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      flatfinder_scraper.py                              │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│   │  Kijiji  │  │  Zumper  │  │ PadMapper│  │Craigslist│  │Rentals.ca│  │
│   └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  │
│        └─────────────┴─────────────┴─────────────┴─────────────┘        │
│                                    │                                     │
│                    Browser-Use Agent (Claude/GPT-4o)                    │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
              ▼                      ▼                      ▼
    ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
    │   XLSX Output   │   │   CSV Output    │   │    SUPABASE     │
    │  (Git commit)   │   │   (Git commit)  │   │   (upsert)      │
    └─────────────────┘   └─────────────────┘   └────────┬────────┘
                                                         │
                                                         ▼
                                              ┌─────────────────────┐
                                              │  flatfinder-landing │
                                              │       .html         │
                                              │  (JS fetch → grid)  │
                                              └─────────────────────┘
```

---

## Implementation Tasks

### Task 1: Connect FastAPI Scraper to Supabase

**File:** `flatfinder-housing-revolutionized/packages/scraper/service/main.py`

**Current State:** The `scrape_region` endpoint collects listings but only prints them with a `# TODO: write to Supabase` comment.

**Required Changes:**

```python
# Add at top of file
import os
from supabase import create_client

# Add Supabase client initialization
def get_supabase_client():
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_KEY")
    if not url or not key:
        return None
    return create_client(url, key)

# In scrape_region(), replace the TODO block with:
client = get_supabase_client()
if client:
    rows = []
    for listing in all_listings:
        d = listing.to_dict()
        rows.append({
            "id": f"{d['source']}_{d['external_id']}",
            "source": d["source"],
            "title": d["title"],
            "price": d["monthly_cost"],
            "bedrooms": str(d["bedrooms"]) + "-Bed" if d["bedrooms"] else None,
            "bathrooms": str(d["bathrooms"]) if d["bathrooms"] else None,
            "type": d["listing_type"],
            "neighbourhood": d["region"],
            "address": d["address"],
            "url": d["url"],
            "description": d["description"][:220] if d["description"] else None,
        })
    
    # Batch upsert with conflict on id
    for i in range(0, len(rows), 200):
        batch = rows[i:i+200]
        client.table("listings").upsert(batch, on_conflict="id").execute()
```

**Dependencies:** Add `supabase>=2.0.0` to `requirements.txt`

---

### Task 2: Update GitHub Actions Workflow

**File:** `.github/workflows/daily_scrape.yml`

**Current State:** Already configured correctly! The workflow:
- Runs daily at 06:17 UTC
- Installs Python dependencies
- Caches Playwright browsers
- Passes secrets via environment variables
- Commits XLSX/CSV outputs to Git

**Required Secrets (set in GitHub repo settings):**
| Secret Name | Description |
|-------------|-------------|
| `ANTHROPIC_API_KEY` | Claude API key (preferred) |
| `OPENAI_API_KEY` | OpenAI API key (fallback) |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | Supabase service role key |

**Verification:** Run `gh workflow run daily_scrape.yml` manually to test.

---

### Task 3: Wire Landing Page to Supabase

**File:** `flatfinder-landing.html`

**Current State:** Static marketing page with no dynamic listings.

**Required Changes:** Add a script before `</body>` to fetch and display listings:

```html
<!-- LISTINGS GRID (add after the .stats-bar section) -->
<section class="section" id="listings">
  <div class="section-label">Live From Toronto</div>
  <h2 class="section-title">Latest Affordable Listings</h2>
  <div id="listings-grid" class="listings-grid"></div>
</section>

<style>
  .listings-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: 24px;
    margin-top: 40px;
  }
  .listing-card {
    background: var(--bg2);
    border: 1px solid var(--border);
    padding: 24px;
    transition: transform 0.2s, border-color 0.2s;
  }
  .listing-card:hover {
    transform: translateY(-4px);
    border-color: var(--orange);
  }
  .listing-price {
    font-family: 'Bebas Neue', sans-serif;
    font-size: 2rem;
    color: var(--orange);
  }
  .listing-title {
    font-size: 1rem;
    font-weight: 500;
    margin: 8px 0;
    color: var(--white);
  }
  .listing-meta {
    font-family: 'Space Mono', monospace;
    font-size: 0.7rem;
    color: var(--grey);
    letter-spacing: 1px;
  }
  .listing-link {
    display: inline-block;
    margin-top: 16px;
    font-family: 'Space Mono', monospace;
    font-size: 0.7rem;
    color: var(--orange);
    text-decoration: none;
  }
  .listing-link:hover { text-decoration: underline; }
</style>

<script type="module">
  const SUPABASE_URL = 'YOUR_SUPABASE_URL';
  const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';

  async function loadListings() {
    const grid = document.getElementById('listings-grid');
    if (!grid) return;

    try {
      const response = await fetch(
        `${SUPABASE_URL}/rest/v1/listings?select=*&order=date_scraped.desc,price.asc&limit=12`,
        {
          headers: {
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
          }
        }
      );
      
      const listings = await response.json();
      
      grid.innerHTML = listings.map(l => `
        <div class="listing-card">
          <div class="listing-price">$${(l.price || 0).toLocaleString()}/mo</div>
          <div class="listing-title">${l.title || 'Untitled'}</div>
          <div class="listing-meta">
            ${l.bedrooms || '?'} · ${l.neighbourhood || 'Toronto'} · ${l.source || ''}
          </div>
          ${l.utilities === 'Yes' ? '<div class="listing-meta" style="color: var(--orange);">✓ Utilities Included</div>' : ''}
          ${l.url ? `<a href="${l.url}" target="_blank" class="listing-link">View Listing →</a>` : ''}
        </div>
      `).join('');
    } catch (err) {
      console.error('Failed to load listings:', err);
      grid.innerHTML = '<p style="color: var(--grey);">Unable to load listings. Please try again later.</p>';
    }
  }

  loadListings();
</script>
```

---

## Database Schema Reference

**Table:** `listings` (defined in `supabase/migrations/001_create_listings.sql`)

| Column | Type | Notes |
|--------|------|-------|
| `id` | text | Primary key, MD5-based stable ID |
| `source` | text | Kijiji, Zumper, Rightmove, etc. |
| `title` | text | Listing title |
| `price` | integer | Monthly rent in CAD/GBP |
| `bedrooms` | text | Bachelor/Studio, 1-Bed, 2-Bed, etc. |
| `bathrooms` | text | Number or "?" |
| `type` | text | Apartment, House, etc. |
| `neighbourhood` | text | Area/region name |
| `address` | text | Street address |
| `utilities` | text | Yes / Partial / Check |
| `pets` | text | Yes / No / ? |
| `ttc_access` | text | Subway / Streetcar / Bus / ? |
| `available` | text | Move-in date |
| `url` | text | Listing URL |
| `description` | text | Truncated to 220 chars |
| `date_scraped` | date | Current date |
| `inserted_at` | timestamptz | Auto-set on insert |

**RLS Policy:** Public read access enabled; service role key bypasses RLS for writes.

---

## Environment Variables

Create a `.env` file (DO NOT COMMIT):

```bash
# LLM Provider (at least one required)
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...

# Supabase
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_SERVICE_KEY=eyJhbGc...  # service_role key, NOT anon key
```

---

## Execution Order

1. **Apply database migration** - Run `001_create_listings.sql` in Supabase SQL Editor
2. **Set GitHub secrets** - Add all 4 secrets to repo settings
3. **Update main.py** - Add Supabase upsert logic (Task 1)
4. **Update landing page** - Add listings grid + JS fetch (Task 3)
5. **Test locally** - Run `python flatfinder_scraper.py` with env vars set
6. **Deploy** - Push changes, workflow runs automatically next day at 06:17 UTC

---

## Testing Checklist

- [ ] Database migration applied successfully
- [ ] `python flatfinder_scraper.py` runs without errors
- [ ] Listings appear in Supabase `listings` table
- [ ] Landing page displays listings from Supabase
- [ ] GitHub Action runs successfully (check Actions tab)
- [ ] XLSX/CSV files committed to repo after scrape

---

## Security Notes

- Service role key ONLY used server-side (GitHub Actions, local scripts)
- Anon key used in landing page (public, read-only via RLS)
- Never commit `.env` or secrets to Git
- RLS policy restricts writes to service role only
