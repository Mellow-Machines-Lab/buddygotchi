// Every cap and rate limit the server holds, in one place. The Mac's numbers
// can be faked, so the server never trusts more than these.

/** A buddy's XP in one day, the daily ring. */
export const XP_PER_DAY = 100;

/** The shortest time between two sends of a buddy's state. */
export const SEND_EVERY_MS = 30_000;

/** The most each count can grow in a minute; past it a send is clamped. */
export const ADDED_PER_MINUTE = {
  turns: 20,
  tests_passed: 50,
  ships: 5,
  lines_changed: 20_000,
} as const;

/** A send covers at most this many minutes since the last, for the caps above. */
export const ADDED_MAX_MINUTES = 60;

/** A buddy not seen for this long counts as asleep in the world. */
export const AWAKE_WITHIN_MS = 10 * 60_000;

/** The snapshot's sample of buddies, the awake first. */
export const SNAPSHOT_BUDDIES = 500;

/** How long Vercel's edge keeps the snapshot. */
export const SNAPSHOT_CACHE_SECONDS = 30;

/** Gestures one buddy sends: in an hour, and to the same buddy in an hour. */
export const GESTURES_SENT_PER_HOUR = 20;
export const GESTURES_TO_ONE_PER_HOUR = 3;

/** Gestures handed out by one GET. The rest wait for the next. */
export const GESTURES_PER_READ = 100;

/** Reports that hide a name. */
export const REPORTS_TO_HIDE = 3;

/** Expiry, run by the daily cron. */
export const BUDDY_EXPIRES_DAYS = 30;
export const DAYS_KEPT = 400;
export const GESTURE_DELIVERED_KEPT_DAYS = 1;
export const GESTURE_UNREAD_KEPT_DAYS = 2;

/** Bounds on what a buddy says about itself. */
export const LEVEL_MAX = 1_000_000;
export const REWARD_DAYS_MAX = 30;
