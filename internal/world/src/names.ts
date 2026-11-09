// The name filter. Names are public on the map, so a name that fails is kept
// but shown as "a buddy", and the Mac is told why.

import { REPORTS_TO_HIDE } from "./limits.js";

export const HIDDEN_NAME = "a buddy";
export const NAME_MAX = 16;
/** What's stored of a name, refused or not. */
const STORED_MAX = 32;

export type NameReason = "empty" | "length" | "characters" | "link" | "number" | "word";

export interface NameCheck {
  /** The name as stored: trimmed, spaces collapsed, cut to 32 characters. */
  name: string;
  ok: boolean;
  reason?: NameReason;
}

/** Letters, marks, digits, spaces and a few marks of punctuation. */
const ALLOWED = /^[\p{L}\p{M}\p{N} '’.\-_!?&]+$/u;
/** Anything that reads as a web address. */
const LINK = /(https?|www\.|\.(com|net|org|io|gg|ly|co|me|xyz|app|dev|ai|tv|link|site|online|ru|cn|uk|de)\b|\bdot\s?com\b)/i;
/** Five digits or more reads as a phone number or a code. */
const DIGITS_MAX = 4;

/** Refused wherever they appear, after the name is folded (below). */
const BANNED_ANYWHERE = [
  "fuck", "shit", "cunt", "nigg", "fagg", "retard", "whore", "slut", "rapist", "nazi", "hitler",
  "porn", "pussy", "bitch", "twat", "bollock", "kike", "tranny", "dildo", "penis", "vagina",
  "asshole", "jizz", "molest",
];
/** Refused only as a whole word, since they hide inside ordinary names. */
const BANNED_WORDS = [
  "ass", "arse", "cum", "fag", "tit", "tits", "sex", "dick", "kkk", "rape", "anal", "nsfw",
  "cock", "boob", "boobs", "wank", "spic", "chink", "pedo",
];

const LEET: Record<string, string> = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "$": "s", "@": "a", "!": "i" };

/** Lower case, accents dropped, look-alike digits read as letters. */
function fold(text: string): string {
  return text
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[0-9$@!]/g, (c) => LEET[c] ?? c);
}

export function checkName(input: unknown): NameCheck {
  const name = [...(typeof input === "string" ? input : "").normalize("NFC").trim().replace(/\s+/g, " ")]
    .slice(0, STORED_MAX)
    .join("");
  const refuse = (reason: NameReason): NameCheck => ({ name, ok: false, reason });
  if (!name) return refuse("empty");
  if ([...name].length > NAME_MAX) return refuse("length");
  if (LINK.test(name)) return refuse("link");
  if (!ALLOWED.test(name)) return refuse("characters");
  if ((name.match(/\p{Nd}/gu) ?? []).length > DIGITS_MAX) return refuse("number");
  const folded = fold(name);
  const squashed = folded.replace(/[^a-z]/g, "");
  if (BANNED_ANYWHERE.some((w) => squashed.includes(w))) return refuse("word");
  const words = folded.split(/[^a-z]+/).filter(Boolean);
  if (words.some((w) => BANNED_WORDS.includes(w))) return refuse("word");
  return { name, ok: true };
}

/** The name the world shows: hidden when it failed the filter or has 3 reports. */
export function shownName(row: { name: string; name_ok: boolean; reports: number }): string {
  return row.name_ok && row.reports < REPORTS_TO_HIDE ? row.name : HIDDEN_NAME;
}
