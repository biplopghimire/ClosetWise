-- Fields the iOS app keeps on each item, so a synced closet round-trips without loss.
alter table public.items
  add column kind text,                          -- drawn garment shape: tee, knit, trousers, shoes …
  add column hex text,                           -- exact colour, e.g. '1D1D1F'
  add column store text,
  add column wear_count int not null default 0,  -- includes wears from before the app; wear_events adds to it going forward
  add column last_worn date;

-- Purchase checks keep a short summary for the history list.
alter table public.purchase_checks
  add column verdict text,
  add column style_score int;
