-- The weekly league (plan/xp-league.md §6): what a buddy now says about
-- itself, made-up buddies to seed a small world, and each closed week's
-- places and medals.

alter table buddies add column color int not null default 0 check (color between 0 and 7);
alter table buddies add column days_in_a_row int not null default 0;
-- A made-up buddy: no Mac, no key it uses. Its XP and activity come from the
-- time alone (src/seeds.ts), and it never expires.
alter table buddies add column seed boolean not null default false;
alter table buddies add column seed_strength int check (seed_strength between 100 and 700);

-- One row a buddy with XP a closed week: its place, for the Monday line,
-- "best week" and "you beat them".
create table league_results (
  week   date not null,          -- the week's Monday, UTC
  league int  not null default 1,
  buddy  uuid not null references buddies on delete cascade,
  place  int  not null,
  xp     int  not null,
  primary key (week, league, buddy)
);
create index league_results_buddy on league_results (buddy, week);

-- Medals stay when old results go.
create table medals (
  buddy uuid not null references buddies on delete cascade,
  week  date not null,
  place int  not null check (place between 1 and 3),
  primary key (buddy, week)
);

-- A week closed once: its row is written in the same transaction as its results.
create table league_weeks (week date primary key, closed_at timestamptz not null default now());
