-- ClosetWise initial schema
create extension if not exists vector with schema extensions;

-- Profiles -------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text,
  style_tags text[] not null default '{}',
  created_at timestamptz not null default now()
);

-- Items (owned wardrobe pieces) ------------------------------------------------
create type public.item_category as enum ('top', 'bottom', 'outerwear', 'dress', 'shoes', 'accessory');
create type public.item_source as enum ('photo', 'receipt', 'check');

create table public.items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  image_path text,             -- cut-out in storage bucket "items"
  original_path text,          -- original photo
  category public.item_category not null,
  subcategory text,
  color text,
  pattern text,
  material text,
  fit text,
  style text,
  formality smallint check (formality between 1 and 5),
  seasons text[] not null default '{}',
  price numeric(10, 2),
  purchased_at date,
  source public.item_source not null default 'photo',
  embedding extensions.vector(768),
  archived boolean not null default false,
  created_at timestamptz not null default now()
);
create index items_user_idx on public.items (user_id, category) where not archived;
create index items_embedding_idx on public.items using hnsw (embedding extensions.vector_cosine_ops);

-- Outfits & wear events ------------------------------------------------------
create table public.outfits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  worn_on date not null default current_date,
  photo_path text,
  created_at timestamptz not null default now()
);

create table public.wear_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  outfit_id uuid references public.outfits on delete cascade,
  item_id uuid not null references public.items on delete cascade,
  worn_on date not null default current_date,
  confirmed boolean not null default true,
  unique (outfit_id, item_id)
);
create index wear_events_item_idx on public.wear_events (item_id, worn_on);

-- Purchase checks ------------------------------------------------------------
create type public.check_decision as enum ('bought', 'skipped', 'returned');

create table public.purchase_checks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  source_url text,
  product jsonb not null default '{}',     -- name, brand, price, image_url, material
  attributes jsonb not null default '{}',  -- same shape as item attributes
  image_path text,
  embedding extensions.vector(768),
  result jsonb,                            -- duplicates, matches, outfit_count, cost_per_wear, verdict, explanation
  decision public.check_decision,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);

-- Receipts -------------------------------------------------------------------
create table public.receipts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  image_path text,
  parsed jsonb,
  item_ids uuid[] not null default '{}',
  created_at timestamptz not null default now()
);

-- Row level security ---------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.items enable row level security;
alter table public.outfits enable row level security;
alter table public.wear_events enable row level security;
alter table public.purchase_checks enable row level security;
alter table public.receipts enable row level security;

create policy "own profile" on public.profiles for all
  using (id = auth.uid()) with check (id = auth.uid());
create policy "own items" on public.items for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own outfits" on public.outfits for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own wear events" on public.wear_events for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own checks" on public.purchase_checks for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own receipts" on public.receipts for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Create a profile on sign-up
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Similarity search (runs as the caller, so RLS applies) ---------------------
create function public.match_items(
  query_embedding extensions.vector(768),
  match_category public.item_category default null,
  match_count int default 10
) returns table (id uuid, name text, category public.item_category, color text, fit text, style text, similarity float)
language sql stable set search_path = public, extensions as $$
  select i.id, i.name, i.category, i.color, i.fit, i.style,
         1 - (i.embedding <=> query_embedding) as similarity
  from public.items i
  where i.user_id = auth.uid()
    and not i.archived
    and i.embedding is not null
    and (match_category is null or i.category = match_category)
  order by i.embedding <=> query_embedding
  limit match_count;
$$;

-- Wear counts per item
create view public.item_wear_counts with (security_invoker = on) as
  select i.id as item_id, count(w.id) as wear_count, max(w.worn_on) as last_worn
  from public.items i
  left join public.wear_events w on w.item_id = i.id and w.confirmed
  group by i.id;

-- Storage buckets (private; files stored under <user_id>/...) ----------------
insert into storage.buckets (id, name, public) values
  ('items', 'items', false), ('outfits', 'outfits', false),
  ('receipts', 'receipts', false), ('checks', 'checks', false);

create policy "own files read" on storage.objects for select
  using (bucket_id in ('items', 'outfits', 'receipts', 'checks') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "own files write" on storage.objects for insert
  with check (bucket_id in ('items', 'outfits', 'receipts', 'checks') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "own files update" on storage.objects for update
  using (bucket_id in ('items', 'outfits', 'receipts', 'checks') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "own files delete" on storage.objects for delete
  using (bucket_id in ('items', 'outfits', 'receipts', 'checks') and (storage.foldername(name))[1] = auth.uid()::text);
