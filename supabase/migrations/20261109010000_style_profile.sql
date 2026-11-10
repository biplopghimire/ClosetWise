-- Fit types, outfit reactions, and the style profile Gemini reads.

-- Fit on every item -----------------------------------------------------------
create type public.fit_type as enum ('tight', 'fitted', 'regular', 'relaxed', 'loose', 'oversized');

alter table public.items
  alter column fit type public.fit_type using (
    case when fit in ('tight', 'fitted', 'regular', 'relaxed', 'loose', 'oversized') then fit::public.fit_type end
  ),
  alter column fit set default 'regular',
  add column silhouette text;   -- cut/shape: wide-leg, straight, cropped, A-line …

-- How an outfit felt, and whether it was worn or just suggested ---------------
create type public.outfit_reaction as enum ('loved', 'fine', 'not_me');

alter table public.outfits
  add column reaction public.outfit_reaction,
  add column source text not null default 'logged' check (source in ('logged', 'suggested')),
  add column worn boolean not null default true;   -- false = a suggestion the user rated without wearing

-- Style profile -----------------------------------------------------------------
create table public.style_profiles (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,
  preferences jsonb not null default '{}',   -- what they told us (vibes, fits, colours, words…)
  learned jsonb not null default '{}',       -- computed from logged outfits
  summary text,                              -- Gemini's written read
  tags text[] not null default '{}',
  fit_notes text,
  updated_at timestamptz not null default now()
);

create table public.style_inspirations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  image_path text not null,                  -- in storage bucket "inspiration"
  note text,
  created_at timestamptz not null default now()
);

alter table public.style_profiles enable row level security;
alter table public.style_inspirations enable row level security;

create policy "own style profile" on public.style_profiles for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own inspirations" on public.style_inspirations for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

insert into storage.buckets (id, name, public) values ('inspiration', 'inspiration', false);

create policy "own inspiration read" on storage.objects for select
  using (bucket_id = 'inspiration' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "own inspiration write" on storage.objects for insert
  with check (bucket_id = 'inspiration' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "own inspiration delete" on storage.objects for delete
  using (bucket_id = 'inspiration' and (storage.foldername(name))[1] = auth.uid()::text);

-- Fit mix per category from confirmed wears (feeds learned style server-side) --
create view public.fit_wear_shares with (security_invoker = on) as
  select i.category, i.fit, count(w.id) as wears
  from public.wear_events w
  join public.items i on i.id = w.item_id
  where w.confirmed
  group by i.category, i.fit;

-- match_items returned fit as text; recreate it for the enum and include silhouette.
drop function public.match_items(extensions.vector, public.item_category, int);
create function public.match_items(
  query_embedding extensions.vector(768),
  match_category public.item_category default null,
  match_count int default 10
) returns table (id uuid, name text, category public.item_category, color text, fit public.fit_type,
                 silhouette text, style text, similarity float)
language sql stable set search_path = public, extensions as $$
  select i.id, i.name, i.category, i.color, i.fit, i.silhouette, i.style,
         1 - (i.embedding <=> query_embedding) as similarity
  from public.items i
  where i.user_id = auth.uid()
    and not i.archived
    and i.embedding is not null
    and (match_category is null or i.category = match_category)
  order by i.embedding <=> query_embedding
  limit match_count;
$$;
