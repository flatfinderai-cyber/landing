-- FlatFinder listings table
-- Run this once in your Supabase SQL editor (or via supabase db push).

create table if not exists listings (
  id            text        primary key,          -- MD5-based stable ID
  source        text        not null,             -- Kijiji / Zumper / etc.
  title         text        not null,
  price         integer,                          -- monthly rent in CAD
  bedrooms      text,
  bathrooms     text,
  type          text,
  neighbourhood text,
  address       text,
  utilities     text,                             -- Yes / Partial / Check
  pets          text,                             -- Yes / No / ?
  ttc_access    text,                             -- Subway / Streetcar / Bus / ?
  available     text,
  url           text,
  description   text,
  date_scraped  date        not null default current_date,
  inserted_at   timestamptz not null default now()
);

-- Index for common filters
create index if not exists listings_source_idx       on listings (source);
create index if not exists listings_price_idx        on listings (price);
create index if not exists listings_bedrooms_idx     on listings (bedrooms);
create index if not exists listings_date_scraped_idx on listings (date_scraped);

-- Enable Row Level Security
alter table listings enable row level security;

-- Service-role key (used by the scraper) bypasses RLS automatically.
-- Allow anonymous / authenticated users to read listings.
create policy "public read"
  on listings for select
  using (true);
