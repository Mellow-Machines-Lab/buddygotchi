-- Who joined lately, for the limit on joining: an address's keyed hash, never
-- the address, and kept an hour.
create table joins (
  ip_hash bytea not null,                 -- HMAC-SHA256 of the address, with IP_SALT
  at      timestamptz not null default now()
);
create index joins_ip_hash on joins (ip_hash, at);
create index joins_at on joins (at);
