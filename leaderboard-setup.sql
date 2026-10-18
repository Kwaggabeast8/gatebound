-- Gatebound global leaderboard. Paste all of this into Supabase > SQL Editor and press Run.

create table if not exists public.hunters (
  user_id     uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 18),
  xp          integer not null default 0 check (xp between 0 and 5000000),
  level       integer not null default 1 check (level between 1 and 999),
  best_streak integer not null default 0 check (best_streak between 0 and 5000),
  slain       integer not null default 0 check (slain between 0 and 5000),
  title       text check (char_length(title) <= 40),
  updated_at  timestamptz not null default now()
);

alter table public.hunters enable row level security;

-- Everyone can see the board; each phone can only create and edit its own hunter.
create policy "board is public"   on public.hunters for select using (true);
create policy "insert own hunter" on public.hunters for insert to authenticated with check (auth.uid() = user_id);
create policy "update own hunter" on public.hunters for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Anti-cheat: block impossible jumps in XP, streak and kills.
create or replace function public.hunters_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.xp > 20000 or new.best_streak > 60 or new.slain > 60 then
      raise exception 'new hunters start small';
    end if;
  else
    if new.xp > old.xp + 3000 then raise exception 'xp jump too large'; end if;
    if new.best_streak > old.best_streak + 2 then raise exception 'streak jump too large'; end if;
    if new.slain > old.slain + 2 then raise exception 'kill jump too large'; end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists hunters_guard on public.hunters;
create trigger hunters_guard before insert or update on public.hunters
for each row execute function public.hunters_guard();
