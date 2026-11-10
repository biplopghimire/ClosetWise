-- Explicit Data API access (the project is created with "Automatically expose new tables" off).
-- Only signed-in users (including anonymous sign-ins) get table access; RLS policies still
-- limit every row to its owner. The `anon` role (no session) gets nothing.

grant usage on schema public to authenticated;

grant select, insert, update, delete on
  public.profiles,
  public.items,
  public.outfits,
  public.wear_events,
  public.purchase_checks,
  public.receipts,
  public.style_profiles,
  public.style_inspirations
to authenticated;

grant select on public.item_wear_counts, public.fit_wear_shares to authenticated;

revoke execute on function public.match_items(extensions.vector, public.item_category, int) from public, anon;
grant execute on function public.match_items(extensions.vector, public.item_category, int) to authenticated;

grant usage on schema extensions to authenticated;
