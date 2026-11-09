-- No country and no time zone name: a buddy sends only its UTC offset, in
-- minutes, and the world groups buddies by region from it (src/regions.ts).

alter table buddies drop column country;
alter table buddies drop column tz;
-- UTC-12:00 to UTC+14:00, the offsets in use, in quarter hours.
alter table buddies add column utc_offset int
  check (utc_offset between -720 and 840 and utc_offset % 15 = 0);

-- A gesture says the region it came from, worked out when it was sent.
alter table gestures drop column from_country;
alter table gestures add column from_region text;
