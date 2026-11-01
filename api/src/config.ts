/**
 * Environment parsing with fail-fast validation.
 *
 * loadConfig() is called once at app construction (see src/app.ts). Missing or
 * invalid REQUIRED values throw immediately with a human-readable message so a
 * misconfigured deployment never serves traffic half-working.
 */
import { z } from "zod";

/** Code-level limits (not env-tunable to keep the surface small). */
export const LIMITS = {
  /** Max characters in a message / reply body. */
  messageChars: 12_000,
  /** Max characters in a search query. */
  searchChars: 100,
  /** Max attachments that may be linked to a single message. */
  attachmentsPerMessage: 10,
  /** Default page size for message pagination. */
  pageDefault: 50,
  /** Hard cap for ?limit= on list endpoints. */
  pageMax: 100,
  /** Session lifetime in seconds (7 days). */
  sessionTtl: 7 * 24 * 60 * 60,
  /** Magic-link token validity in seconds. */
  magicLinkTtl: 300,
  /** Invite validity in hours. */
  inviteDefaultTtlHours: 7 * 24,
} as const;

const emptyToUndefined = (v: unknown): string | undefined => {
  if (typeof v !== "string") return undefined;
  const t = v.trim();
  return t === "" ? undefined : t;
};

const optionalString = z.preprocess(emptyToUndefined, z.string().optional());

const envInt = (def: number, min: number, max: number) =>
  z.preprocess(emptyToUndefined, z.coerce.number().int().min(min).max(max).optional()).transform(
    (v) => v ?? def,
  );

const envBool = (def: boolean) =>
  z.preprocess(
    emptyToUndefined,
    z.enum(["true", "false"]).optional(),
  ).transform((v) => (v === undefined ? def : v === "true"));

const rawEnvSchema = z.object({
  NODE_ENV: z.preprocess(
    emptyToUndefined,
    z.enum(["development", "production", "test"]).optional(),
  ).transform((v) => v ?? "development"),
  DATABASE_URL: z.preprocess(emptyToUndefined, z.string().min(1).optional()),
  BETTER_AUTH_SECRET: z.preprocess(emptyToUndefined, z.string().optional()),
  BETTER_AUTH_URL: z.preprocess(emptyToUndefined, z.string().optional()),

  GOOGLE_CLIENT_ID: optionalString,
  GOOGLE_CLIENT_SECRET: optionalString,

  ABLY_API_KEY: optionalString,

  LIVEKIT_URL: optionalString,
  LIVEKIT_API_KEY: optionalString,
  LIVEKIT_API_SECRET: optionalString,

  STORAGE_MODE: z.preprocess(
    emptyToUndefined,
    z.enum(["local", "s3"]).optional(),
  ).transform((v) => v ?? "local"),
  S3_ENDPOINT: optionalString,
  S3_REGION: optionalString,
  S3_BUCKET: optionalString,
  S3_ACCESS_KEY_ID: optionalString,
  S3_SECRET_ACCESS_KEY: optionalString,
  MAX_UPLOAD_BYTES: envInt(26_214_400, 1, 10 * 1024 * 1024 * 1024),

  ALLOWED_ORIGINS: optionalString,

  RATE_LIMIT_AUTH_PER_MIN: envInt(30, 1, 100_000),
  RATE_LIMIT_ROUTE_PER_MIN: envInt(120, 1, 1_000_000),
  RATE_LIMIT_GLOBAL_PER_MIN: envInt(600, 1, 10_000_000),
  TRUST_PROXY: envBool(true),

  MAX_BODY_BYTES: envInt(1_048_576, 1_024, 100 * 1024 * 1024),
  SENTRY_DSN: optionalString,
  PORT: envInt(3000, 1, 65_535),
});

export interface GoogleConfig {
  clientId: string;
  clientSecret: string;
}

export interface LiveKitConfig {
  url: string;
  apiKey: string;
  apiSecret: string;
}

export interface StorageConfig {
  mode: "local" | "s3";
  endpoint: string | null;
  region: string;
  bucket: string | null;
  accessKeyId: string | null;
  secretAccessKey: string | null;
  maxUploadBytes: number;
}

export interface RateLimitConfig {
  authPerMin: number;
  routePerMin: number;
  globalPerMin: number;
  trustProxy: boolean;
}

export interface Config {
  nodeEnv: "development" | "production" | "test";
  databaseUrl: string;
  betterAuthSecret: string;
  betterAuthUrl: string;
  google: GoogleConfig | null;
  ablyApiKey: string | null;
  livekit: LiveKitConfig | null;
  storage: StorageConfig;
  /** Exact origins allowed by CORS. Never echoed for unknown origins. */
  corsOrigins: string[];
  rateLimit: RateLimitConfig;
  maxBodyBytes: number;
  sentryDsn: string | null;
  port: number;
}

function collectErrors(
  issues: z.ZodIssue[],
  prefix: string,
): string[] {
  return issues.map((i) => `${prefix}.${i.path.join(".") || "(root)"}: ${i.message}`);
}

/**
 * Parse and validate an environment map. Defaults the full process.env.
 * Throws AggregateError-style Error listing every problem at once.
 */
export function loadConfig(env: Record<string, string | undefined> = process.env): Config {
  const parsed = rawEnvSchema.safeParse(env);
  if (!parsed.success) {
    throw new Error(
      `Invalid environment:\n  - ${collectErrors(parsed.error.issues, "env").join("\n  - ")}`,
    );
  }
  const e = parsed.data;
  const problems: string[] = [];

  if (!e.DATABASE_URL) {
    problems.push("env.DATABASE_URL: required (postgres://user:pass@host:5432/db)");
  }
  if (!e.BETTER_AUTH_SECRET) {
    problems.push("env.BETTER_AUTH_SECRET: required (generate with `openssl rand -base64 32`)");
  } else if (e.BETTER_AUTH_SECRET.length < 32) {
    problems.push(
      `env.BETTER_AUTH_SECRET: must be at least 32 characters (got ${e.BETTER_AUTH_SECRET.length})`,
    );
  }
  if (!e.BETTER_AUTH_URL) {
    problems.push("env.BETTER_AUTH_URL: required (e.g. http://localhost:3000)");
  } else {
    try {
      const u = new URL(e.BETTER_AUTH_URL);
      if (u.protocol !== "http:" && u.protocol !== "https:") {
        problems.push("env.BETTER_AUTH_URL: must be an http(s) URL");
      }
    } catch {
      problems.push(`env.BETTER_AUTH_URL: "${e.BETTER_AUTH_URL}" is not a valid URL`);
    }
  }

  // Google OAuth: both or neither.
  if (Boolean(e.GOOGLE_CLIENT_ID) !== Boolean(e.GOOGLE_CLIENT_SECRET)) {
    problems.push(
      "env.GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET: provide both to enable Google sign-in, or neither",
    );
  }

  // LiveKit: all three or none.
  const livekitParts = [e.LIVEKIT_URL, e.LIVEKIT_API_KEY, e.LIVEKIT_API_SECRET];
  const livekitCount = livekitParts.filter(Boolean).length;
  if (livekitCount > 0 && livekitCount < 3) {
    problems.push(
      "env.LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET: provide all three to enable voice rooms, or none",
    );
  }

  // Storage: s3 mode needs credentials.
  if (e.STORAGE_MODE === "s3") {
    if (!e.S3_BUCKET) problems.push("env.S3_BUCKET: required when STORAGE_MODE=s3");
    if (!e.S3_ACCESS_KEY_ID) problems.push("env.S3_ACCESS_KEY_ID: required when STORAGE_MODE=s3");
    if (!e.S3_SECRET_ACCESS_KEY)
      problems.push("env.S3_SECRET_ACCESS_KEY: required when STORAGE_MODE=s3");
  }

  // CORS origins: explicit allow-list, each must be a valid origin.
  const corsOrigins = new Set<string>();
  if (e.ALLOWED_ORIGINS) {
    for (const raw of e.ALLOWED_ORIGINS.split(",")) {
      const origin = raw.trim();
      if (origin === "") continue;
      try {
        const u = new URL(origin);
        corsOrigins.add(u.origin);
      } catch {
        problems.push(
          `env.ALLOWED_ORIGINS: "${origin}" is not a valid origin (expected e.g. https://app.example.com)`,
        );
      }
    }
  }
  if (e.BETTER_AUTH_URL) {
    try {
      corsOrigins.add(new URL(e.BETTER_AUTH_URL).origin);
    } catch {
      /* already reported above */
    }
  }

  if (problems.length > 0) {
    throw new Error(`Invalid environment:\n  - ${problems.join("\n  - ")}`);
  }

  return {
    nodeEnv: e.NODE_ENV,
    databaseUrl: e.DATABASE_URL as string,
    betterAuthSecret: e.BETTER_AUTH_SECRET as string,
    betterAuthUrl: (e.BETTER_AUTH_URL as string).replace(/\/+$/, ""),
    google:
      e.GOOGLE_CLIENT_ID && e.GOOGLE_CLIENT_SECRET
        ? { clientId: e.GOOGLE_CLIENT_ID, clientSecret: e.GOOGLE_CLIENT_SECRET }
        : null,
    ablyApiKey: e.ABLY_API_KEY ?? null,
    livekit:
      e.LIVEKIT_URL && e.LIVEKIT_API_KEY && e.LIVEKIT_API_SECRET
        ? {
            url: (e.LIVEKIT_URL as string).replace(/\/+$/, ""),
            apiKey: e.LIVEKIT_API_KEY,
            apiSecret: e.LIVEKIT_API_SECRET,
          }
        : null,
    storage: {
      mode: e.STORAGE_MODE,
      endpoint: e.S3_ENDPOINT ?? null,
      region: e.S3_REGION ?? "auto",
      bucket: e.S3_BUCKET ?? null,
      accessKeyId: e.S3_ACCESS_KEY_ID ?? null,
      secretAccessKey: e.S3_SECRET_ACCESS_KEY ?? null,
      maxUploadBytes: e.MAX_UPLOAD_BYTES,
    },
    corsOrigins: [...corsOrigins],
    rateLimit: {
      authPerMin: e.RATE_LIMIT_AUTH_PER_MIN,
      routePerMin: e.RATE_LIMIT_ROUTE_PER_MIN,
      globalPerMin: e.RATE_LIMIT_GLOBAL_PER_MIN,
      trustProxy: e.TRUST_PROXY,
    },
    maxBodyBytes: e.MAX_BODY_BYTES,
    sentryDsn: e.SENTRY_DSN ?? null,
    port: e.PORT,
  };
}
