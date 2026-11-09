-- The world: buddies, what they added each day, the goal and gestures.
-- No person and no account: a buddy is a random id and the hash of its key.

-- One row per buddy in the world.
create table buddies (
  id          uuid primary key,
  key_hash    bytea not null unique,      -- sha256 of the buddy's secret key
  name        text not null,              -- as sent; shown only when name_ok and under 3 reports
  name_ok     boolean not null,
  level       int not null default 1,
  country     text,                       -- ISO 3166 alpha-2, from the Mac's region
  tz          text,                       -- IANA time zone
  activity    text not null default 'idle', -- coding | testing | shipping | waiting | idle | asleep
  stage       text,                       -- hatchling | sprout | buddy | chonk
  seen_at     timestamptz not null,
  created_at  timestamptz not null,
  reports     int not null default 0,
  -- What makes a send count once: the last seq and when it came.
  last_seq    bigint not null default 0,
  sent_at     timestamptz,
  -- The Mac's day and its XP so far, so each send adds only what's new.
  xp_day      date,
  xp_today    int not null default 0
);
create index buddies_seen_at on buddies (seen_at desc);

-- What each buddy added each day (UTC): the world's totals and goals.
create table buddy_days (
  buddy         uuid not null references buddies on delete cascade,
  day           date not null,
  xp            int not null default 0,   -- capped at 100 by the server
  turns         int not null default 0,
  tests_passed  int not null default 0,
  ships         int not null default 0,
  lines_changed int not null default 0,
  primary key (buddy, day)
);
create index buddy_days_day on buddy_days (day);

-- The days older than 400, summed over every buddy, so the totals stay.
create table totals_by_day (
  day           date primary key,
  xp            bigint not null default 0,
  turns         bigint not null default 0,
  tests_passed  bigint not null default 0,
  ships         bigint not null default 0,
  lines_changed bigint not null default 0
);

-- The world goal: the newest row is the current one.
create table goals (
  id          serial primary key,
  title       text not null,
  metric      text not null,              -- tests_passed | ships | turns | lines_changed | xp
  target      bigint not null,
  starts      date not null,
  ends        date not null,
  reward_tag  text not null,              -- a tag every board wears once it's reached
  reward_days int not null default 3,
  reached_at  timestamptz,
  created_at  timestamptz not null default now()
);

-- Boops, waves, hearts and cheers waiting for a buddy.
create table gestures (
  id           bigserial primary key,
  to_buddy     uuid not null references buddies on delete cascade,
  from_buddy   uuid references buddies on delete set null,
  kind         text not null,             -- boop | wave | heart | cheer
  from_country text,
  created_at   timestamptz not null default now(),
  delivered_at timestamptz
);
create index gestures_waiting on gestures (to_buddy, id) where delivered_at is null;
create index gestures_sent on gestures (from_buddy, created_at);
create index gestures_created_at on gestures (created_at);

-- Who reported whose name, so each buddy counts once.
create table name_reports (
  buddy    uuid not null references buddies on delete cascade,
  reporter uuid not null references buddies on delete cascade,
  primary key (buddy, reporter)
);
