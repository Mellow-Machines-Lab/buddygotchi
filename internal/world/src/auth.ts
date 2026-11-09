// Buddy keys: 32 random bytes, base64url, shown to the Mac once. The server
// keeps only their sha256, so a leaked database gives no keys. Never log one.

import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import type { Db } from "./db.js";

export function newKey(): string {
  return randomBytes(32).toString("base64url");
}

/** The key's sha256, in hex, for `decode($1, 'hex')`. */
export function keyHash(key: string): string {
  return createHash("sha256").update(key).digest("hex");
}

/** The bearer token of an Authorization header, or undefined. */
export function bearer(header: string | undefined): string | undefined {
  const match = /^Bearer\s+(\S+)$/i.exec(header ?? "");
  return match?.[1];
}

/** The id of the buddy whose key this is, or undefined. */
export async function buddyFor(db: Db, key: string | undefined): Promise<string | undefined> {
  if (!key || key.length > 128) return undefined;
  const rows = await db.query<{ id: string }>("select id from buddies where key_hash = decode($1, 'hex')", [
    keyHash(key),
  ]);
  return rows[0]?.id;
}

/** Whether a token matches a secret from the environment. An unset secret matches nothing. */
export function matchesSecret(token: string | undefined, secret: string | undefined): boolean {
  if (!token || !secret) return false;
  const a = createHash("sha256").update(token).digest();
  const b = createHash("sha256").update(secret).digest();
  return timingSafeEqual(a, b);
}

/** Used when IP_SALT is unset: random, so each instance counts joins on its own. */
const instanceSalt = randomBytes(32).toString("base64url");

/**
 * An IP address's keyed hash, in hex, for the limit on joining: HMAC-SHA256
 * with the server's salt, so a leaked table gives no addresses.
 */
export function ipHash(ip: string, salt: string | undefined): string {
  return createHmac("sha256", salt || instanceSalt).update(ip).digest("hex");
}

/**
 * The caller's address. Vercel sets x-real-ip and x-forwarded-for itself;
 * with neither (a local run), every caller shares one address.
 */
export function clientIp(header: (name: string) => string | undefined): string {
  const ip = header("x-real-ip") ?? header("x-forwarded-for")?.split(",")[0];
  return ip?.trim().slice(0, 64) || "unknown";
}
