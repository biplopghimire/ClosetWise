-- Two-way sync: each row carries when it last changed, so a phone pulling changes can tell
-- whether its own copy or the account's copy is newer. The app sets the value on every change
-- it makes (it knows when the user edited something, which may be before it was online).
alter table public.items
  add column updated_at timestamptz not null default now();

alter table public.outfits
  add column updated_at timestamptz not null default now();

alter table public.purchase_checks
  add column updated_at timestamptz not null default now();

-- Pulls fetch "everything changed since my last pull".
create index items_user_updated on public.items (user_id, updated_at);
create index outfits_user_updated on public.outfits (user_id, updated_at);
create index purchase_checks_user_updated on public.purchase_checks (user_id, updated_at);
