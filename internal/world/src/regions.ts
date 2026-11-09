// The world's regions, from a buddy's UTC offset: the one place their
// boundaries are kept. A buddy sends only its offset, in minutes, never a
// country or a time zone name.

/** The offsets in use: UTC−12:00 to UTC+14:00, each a multiple of 15 minutes. */
export const UTC_OFFSET_MIN = -12 * 60;
export const UTC_OFFSET_MAX = 14 * 60;

export function validOffset(v: unknown): v is number {
  return Number.isSafeInteger(v) && (v as number) >= UTC_OFFSET_MIN && (v as number) <= UTC_OFFSET_MAX && (v as number) % 15 === 0;
}

/**
 * Each region and the offsets in it, in minutes, both ends included. They
 * cover UTC_OFFSET_MIN to UTC_OFFSET_MAX with no gap: the Americas run to
 * −2h (Nuuk, Fernando de Noronha), Europe and Africa from −1h (the Azores)
 * to +3h (Moscow, Nairobi), and Asia and Oceania from +3h30 (Tehran).
 */
export const REGIONS = [
  { region: "americas", from: UTC_OFFSET_MIN, to: -120 },
  { region: "europe_africa", from: -105, to: 180 },
  { region: "asia_oceania", from: 195, to: UTC_OFFSET_MAX },
] as const;
export type Region = (typeof REGIONS)[number]["region"];

export function regionOf(offset: number | null | undefined): Region | null {
  if (offset === null || offset === undefined) return null;
  return REGIONS.find((r) => offset >= r.from && offset <= r.to)?.region ?? null;
}

/** The region of a column holding an offset, in SQL: null when the offset is. */
export function regionSql(col: string): string {
  return `case ${REGIONS.map((r) => `when ${col} between ${r.from} and ${r.to} then '${r.region}'`).join(" ")} end`;
}
