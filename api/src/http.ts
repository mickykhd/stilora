/**
 * Small HTTP helpers that keep every response shaped consistently:
 *   success → { data: ... }
 *   failure → { error: "...", status: <same as HTTP status> }
 */
import type { Context } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import type { z } from "zod";
import type { AppEnv } from "./context";

export function ok<T>(c: Context, data: T, status: ContentfulStatusCode = 200): Response {
  return c.json({ data } as never, status);
}

export function fail(c: Context, status: ContentfulStatusCode, error: string): Response {
  return c.json({ error, status }, status);
}

/**
 * Parse+validate a JSON body; on any failure return a 400 Response.
 * Enforces the byte-size limit even when the client sent no Content-Length
 * (chunked bodies), so oversized payloads are 413 — never parsed.
 */
export function readJson<S extends z.ZodTypeAny>(
  c: Context<AppEnv>,
  schema: S,
): Promise<{ value: z.infer<S>; error: null } | { value: null; error: Response }> {
  return (async () => {
    let text: string;
    try {
      // shares Hono's body cache with any earlier c.req.json() call
      text = await c.req.text();
    } catch {
      return { value: null, error: fail(c, 400, "invalid JSON body") };
    }

    const maxBytes = c.get("ctx")?.config.maxBodyBytes ?? 1_048_576;
    if (Buffer.byteLength(text, "utf8") > maxBytes) {
      return {
        value: null,
        error: fail(c, 413, `payload too large (limit ${maxBytes} bytes)`),
      };
    }

    let raw: unknown;
    try {
      raw = JSON.parse(text);
    } catch {
      return { value: null, error: fail(c, 400, "invalid JSON body") };
    }
    const parsed = schema.safeParse(raw);
    if (!parsed.success) {
      const details = parsed.error.issues
        .map((i) => `${i.path.join(".") || "body"}: ${i.message}`)
        .slice(0, 5)
        .join("; ");
      return { value: null, error: fail(c, 400, `validation failed: ${details}`) };
    }
    return { value: parsed.data, error: null };
  })();
}

/** UUIDv4-ish check (any RFC 4122 variant) — malformed ids fail fast with 400. */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: string): boolean {
  return UUID_RE.test(value);
}

/**
 * Better Auth generates url-safe random user ids (e.g. `fhSVhzOra4RVg…`),
 * NOT uuids — user-id inputs are validated against this looser shape.
 */
const SAFE_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;

export function isSafeId(value: string): boolean {
  return SAFE_ID_RE.test(value);
}

/** Opaque pagination cursor: base64url(JSON {t: ISO time, i: row id}). */
export interface Cursor {
  t: string;
  i: string;
}

export function encodeCursor(createdAt: Date, id: string): string {
  const payload: Cursor = { t: createdAt.toISOString(), i: id };
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
}

export function decodeCursor(raw: string): Cursor | null {
  try {
    const parsed: unknown = JSON.parse(Buffer.from(raw, "base64url").toString("utf8"));
    if (
      typeof parsed === "object" &&
      parsed !== null &&
      typeof (parsed as Cursor).t === "string" &&
      typeof (parsed as Cursor).i === "string" &&
      !Number.isNaN(Date.parse((parsed as Cursor).t))
    ) {
      return parsed as Cursor;
    }
    return null;
  } catch {
    return null;
  }
}
