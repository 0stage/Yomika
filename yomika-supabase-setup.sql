-- Yomika cloud schema. EPUB files and covers remain local in the user's browser.
-- Existing kotoba_* table names are kept to preserve compatibility with existing deck data.

create table if not exists public.kotoba_reading_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id text not null,
  progress jsonb not null default '{"ch":0,"fr":0,"v":0}'::jsonb check (jsonb_typeof(progress) = 'object'),
  updated_at timestamptz not null default now(),
  primary key (user_id, book_id)
);

create table if not exists public.kotoba_decks (
  user_id uuid not null references auth.users(id) on delete cascade,
  deck_id text not null,
  name text not null,
  words jsonb not null default '[]'::jsonb check (jsonb_typeof(words) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, deck_id)
);

create unique index if not exists kotoba_decks_user_name_unique
  on public.kotoba_decks (user_id, lower(name));

alter table public.kotoba_reading_progress enable row level security;
alter table public.kotoba_decks enable row level security;

revoke all on table public.kotoba_reading_progress from anon, authenticated;
revoke all on table public.kotoba_decks from anon, authenticated;
grant select, insert, update, delete on table public.kotoba_reading_progress to authenticated;
grant select, insert, update, delete on table public.kotoba_decks to authenticated;

drop policy if exists "Yomika users manage reading progress" on public.kotoba_reading_progress;
create policy "Yomika users manage reading progress"
  on public.kotoba_reading_progress for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Yomika users manage decks" on public.kotoba_decks;
create policy "Yomika users manage decks"
  on public.kotoba_decks for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);