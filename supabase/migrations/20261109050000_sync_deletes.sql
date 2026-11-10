-- Outfits and purchase checks deleted on one phone stay deleted on the others: rows are
-- marked rather than removed (like items.archived), so a phone that still has a copy
-- learns it was deleted instead of uploading it again.
alter table public.outfits
  add column deleted boolean not null default false;

alter table public.purchase_checks
  add column deleted boolean not null default false;
