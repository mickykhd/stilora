/**
 * Config validation: fail-fast messages for every required/partial variable,
 * defaults, origin parsing and feature toggles.
 */
import { describe, expect, test } from "bun:test";
import { loadConfig } from "../src/config";

const BASE = {
  DATABASE_URL: "postgres://user:pass@localhost:5432/db",
  BETTER_AUTH_SECRET: "a-perfectly-valid-32-character-secret!",
  BETTER_AUTH_URL: "https://api.example.com",
};

function expectThrows(env: Record<string, string | undefined>, needle: string): void {
  let message = "";
  try {
    loadConfig(env);
  } catch (err) {
    message = err instanceof Error ? err.message : String(err);
  }
  expect(message).toContain(needle);
}

describe("loadConfig", () => {
  test("valid env parses with sensible defaults", () => {
    const config = loadConfig(BASE);
    expect(config.nodeEnv).toBe("development");
    expect(config.ablyApiKey).toBeNull();
    expect(config.livekit).toBeNull();
    expect(config.storage.mode).toBe("local");
    expect(config.storage.maxUploadBytes).toBe(26_214_400);
    expect(config.rateLimit).toEqual({
      authPerMin: 30,
      routePerMin: 120,
      globalPerMin: 600,
      trustProxy: true,
    });
    expect(config.maxBodyBytes).toBe(1_048_576);
    expect(config.port).toBe(3000);
    expect(config.sentryDsn).toBeNull();
    expect(config.betterAuthUrl).toBe("https://api.example.com");
    // BETTER_AUTH_URL's origin is always CORS-allowed
    expect(config.corsOrigins).toContain("https://api.example.com");
  });

  test("missing required variables are ALL reported at once", () => {
    expectThrows({}, "DATABASE_URL");
    expectThrows({ DATABASE_URL: "x" }, "BETTER_AUTH_SECRET");
    expectThrows({ DATABASE_URL: "x", BETTER_AUTH_SECRET: "y".repeat(40) }, "BETTER_AUTH_URL");
  });

  test("short secret → explicit guidance", () => {
    expectThrows({ ...BASE, BETTER_AUTH_SECRET: "too-short" }, "at least 32 characters");
  });

  test("invalid BETTER_AUTH_URL → reported", () => {
    expectThrows({ ...BASE, BETTER_AUTH_URL: "not a url" }, "not a valid URL");
  });

  test("non-http(s) BETTER_AUTH_URL → rejected with protocol guidance", () => {
    expectThrows({ ...BASE, BETTER_AUTH_URL: "ftp://api.example.com" }, "http(s) URL");
  });

  test("empty strings are treated as unset (optional toggles stay off)", () => {
    const config = loadConfig({ ...BASE, ABLY_API_KEY: "", LIVEKIT_URL: "" });
    expect(config.ablyApiKey).toBeNull();
    expect(config.livekit).toBeNull();
  });

  test("partial LiveKit config → fail fast", () => {
    expectThrows({ ...BASE, LIVEKIT_URL: "https://x.livekit.cloud" }, "provide all three");
  });

  test("s3 storage without credentials → fail fast", () => {
    expectThrows({ ...BASE, STORAGE_MODE: "s3" }, "S3_BUCKET");
    const full = loadConfig({
      ...BASE,
      STORAGE_MODE: "s3",
      S3_BUCKET: "b",
      S3_ACCESS_KEY_ID: "k",
      S3_SECRET_ACCESS_KEY: "s",
      S3_ENDPOINT: "https://s3.example.com",
      S3_REGION: "us-east-1",
    });
    expect(full.storage.mode).toBe("s3");
    expect(full.storage.bucket).toBe("b");
  });

  test("ALLOWED_ORIGINS parsing: comma list, trimmed, de-duped against auth origin", () => {
    const config = loadConfig({
      ...BASE,
      ALLOWED_ORIGINS: "https://app.example.com, http://localhost:5173 , https://app.example.com",
    });
    expect(config.corsOrigins).toEqual(
      expect.arrayContaining(["https://app.example.com", "http://localhost:5173", "https://api.example.com"]),
    );
    expect(new Set(config.corsOrigins).size).toBe(config.corsOrigins.length);
  });

  test("invalid origin entry → fail fast naming the value", () => {
    expectThrows({ ...BASE, ALLOWED_ORIGINS: "https://ok.example.com, bananas" }, "bananas");
  });

  test("numeric and boolean coercion with range checks", () => {
    const config = loadConfig({
      ...BASE,
      RATE_LIMIT_AUTH_PER_MIN: "5",
      TRUST_PROXY: "false",
      MAX_BODY_BYTES: "2048",
      PORT: "8080",
      NODE_ENV: "production",
    });
    expect(config.rateLimit.authPerMin).toBe(5);
    expect(config.rateLimit.trustProxy).toBe(false);
    expect(config.maxBodyBytes).toBe(2048);
    expect(config.port).toBe(8080);
    expect(config.nodeEnv).toBe("production");

    expectThrows({ ...BASE, RATE_LIMIT_AUTH_PER_MIN: "0" }, "env.RATE_LIMIT_AUTH_PER_MIN");
    expectThrows({ ...BASE, TRUST_PROXY: "maybe" }, "env.TRUST_PROXY");
    expectThrows({ ...BASE, NODE_ENV: "staging" }, "env.NODE_ENV");
  });

  test("livekit fully configured → parsed with trailing slash trimmed", () => {
    const config = loadConfig({
      ...BASE,
      LIVEKIT_URL: "https://proj.livekit.cloud/",
      LIVEKIT_API_KEY: "key",
      LIVEKIT_API_SECRET: "secret",
    });
    expect(config.livekit).toEqual({
      url: "https://proj.livekit.cloud",
      apiKey: "key",
      apiSecret: "secret",
    });
  });
});
