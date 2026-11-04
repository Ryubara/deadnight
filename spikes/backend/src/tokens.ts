// Minimal HS256 signed tokens (JWT-shaped) on node:crypto. HS256 is chosen on purpose: the Godot game server can
// verify it with Crypto.hmac_digest, while Ed25519 would need a GDExtension.
import { createHmac, timingSafeEqual } from "node:crypto";

/** `guest` is the long-lived credential of a Guest account: it signs a guest back in, and is no session. */
export type TokenKind = "session" | "ticket" | "guest";

export interface TokenClaims {
  sub: string;
  kind: TokenKind;
  iat: number;
  exp: number;
  [extra: string]: unknown;
}

const b64 = (value: Buffer | string): string => Buffer.from(value).toString("base64url");
const HEADER = b64(JSON.stringify({ alg: "HS256", typ: "JWT" }));

function mac(secret: string, signingInput: string): Buffer {
  return createHmac("sha256", secret).update(signingInput).digest();
}

export function signToken(
  secret: string,
  kind: TokenKind,
  sub: string,
  ttlSeconds: number,
  extra: Record<string, unknown> = {},
  nowSeconds: number = Math.floor(Date.now() / 1000),
): string {
  const claims: TokenClaims = { ...extra, sub, kind, iat: nowSeconds, exp: nowSeconds + ttlSeconds };
  const signingInput = `${HEADER}.${b64(JSON.stringify(claims))}`;
  return `${signingInput}.${b64(mac(secret, signingInput))}`;
}

/** Returns the claims, or null when the token is malformed, forged, expired, lacks a numeric iat or exp, or is of another kind. */
export function verifyToken(
  secret: string,
  kind: TokenKind,
  token: string,
  nowSeconds: number = Math.floor(Date.now() / 1000),
): TokenClaims | null {
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] !== HEADER) return null;
  const [, payload, signature] = parts as [string, string, string];
  const expected = mac(secret, `${HEADER}.${payload}`);
  const given = Buffer.from(signature, "base64url");
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
  try {
    const claims = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as TokenClaims;
    // A correctly signed token without a numeric exp must not live forever (`undefined <= now` is false).
    if (claims === null || typeof claims !== "object") return null;
    if (!Number.isFinite(claims.iat) || typeof claims.iat !== "number") return null;
    if (!Number.isFinite(claims.exp) || typeof claims.exp !== "number" || claims.exp <= nowSeconds) return null;
    if (claims.kind !== kind || typeof claims.sub !== "string") return null;
    return claims;
  } catch {
    return null;
  }
}
