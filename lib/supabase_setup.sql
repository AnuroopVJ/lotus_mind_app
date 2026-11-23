-- supabase/migrations/20261005000000_init.sql
-- Applied once with:  npx supabase db push
-- Safe to re-run: uses IF NOT EXISTS / DROP POLICY IF EXISTS.

-- ---------------------------------------------------------------------------
-- profiles: one row per user (display name + saved custom prompt)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at   timestamptz not null default now()
);

alter table public.profiles
  add column if not exists custom_instructions text
    check (custom_instructions is null or char_length(custom_instructions) <= 600),
  add column if not exists default_mode text not null default 'normal'
    check (default_mode in ('normal', 'simpler', 'deeper'));

alter table public.profiles enable row level security;

drop policy if exists "read own profile" on public.profiles;
create policy "read own profile" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- Create the profile automatically at signup (name comes from signUp's data map).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, left(coalesce(new.raw_user_meta_data ->> 'display_name', ''), 60))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill: users who signed up before this migration get a profile row too.
insert into public.profiles (id, display_name)
select u.id, left(coalesce(u.raw_user_meta_data ->> 'display_name', ''), 60)
from auth.users u
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- chat_sessions + chat_messages: saved Study Assistant conversations
-- ---------------------------------------------------------------------------
create table if not exists public.chat_sessions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title      text check (title is null or char_length(title) <= 120),
  created_at timestamptz not null default now()
);

create table if not exists public.chat_messages (
  id         bigint generated always as identity primary key,
  session_id uuid not null references public.chat_sessions (id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  role       text not null check (role in ('user', 'assistant')),
  content    text not null check (char_length(content) <= 20000),
  model      text,
  is_crisis  boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists chat_sessions_user_idx
  on public.chat_sessions (user_id, created_at desc);
create index if not exists chat_messages_session_idx
  on public.chat_messages (session_id, id);

alter table public.chat_sessions enable row level security;
alter table public.chat_messages enable row level security;

drop policy if exists "own sessions" on public.chat_sessions;
create policy "own sessions" on public.chat_sessions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own messages" on public.chat_messages;
create policy "own messages" on public.chat_messages
  for all using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.chat_sessions s
      where s.id = session_id and s.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- reflections: mood + free-text journal entries (mood and text stay separate)
-- ---------------------------------------------------------------------------
create table if not exists public.reflections (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  mood       smallint not null check (mood between 1 and 5),
  title      text check (title is null or char_length(title) <= 120),
  body       text not null check (char_length(body) between 1 and 10000),
  created_at timestamptz not null default now()
);

create index if not exists reflections_user_idx
  on public.reflections (user_id, created_at desc);

alter table public.reflections enable row level security;

drop policy if exists "own reflections" on public.reflections;
create policy "own reflections" on public.reflections
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);