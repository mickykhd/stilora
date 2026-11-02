/**
 * Upload signing: local no-op mode end-to-end, size/type validation, key
 * namespacing, and the SigV4 presigner (computed offline with a fixed clock).
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  createTestApp,
  data,
  failure,
  req,
  signIn,
  uniqueEmail,
  type SignedInUser,
  type TestApp,
} from "./helpers";
import {
  createLocalSigner,
  createS3Presigner,
  createUploadSigner,
} from "../src/storage/uploads";
import { safeFileName } from "../src/routes/upload.routes";

let t: TestApp;
let alice: SignedInUser;

beforeAll(async () => {
  t = await createTestApp(); // STORAGE_MODE=local by default
  alice = await signIn(t, uniqueEmail("alice"));
});
afterAll(async () => {
  await t?.close();
});

describe("POST /api/uploads/sign", () => {
  test("local mode returns a no-op URL namespaced under the caller", async () => {
    const res = await req(t, "/api/uploads/sign", {
      method: "POST",
      cookie: alice.cookie,
      body: { fileName: "diagram.png", contentType: "image/png", sizeBytes: 2048 },
    });
    expect(res.status).toBe(201);
    const d = await data<{
      upload: { uploadUrl: string; method: string; key: string; headers: Record<string, string>; expiresAt: string };
    }>(res);

    expect(d.upload.method).toBe("PUT");
    expect(d.upload.uploadUrl).toMatch(/^local:\/\//);
    expect(d.upload.key).toContain(`uploads/${alice.id}/`);
    expect(d.upload.key.endsWith("/diagram.png")).toBe(true);
    expect(d.upload.headers["content-type"]).toBe("image/png");
    expect(new Date(d.upload.expiresAt).getTime()).toBeGreaterThan(Date.now());
  });

  test("path traversal in fileName is neutralized", async () => {
    const res = await req(t, "/api/uploads/sign", {
      method: "POST",
      cookie: alice.cookie,
      body: { fileName: "../../../etc/passwd", contentType: "text/plain", sizeBytes: 10 },
    });
    expect(res.status).toBe(201);
    const d = await data<{ upload: { key: string } }>(res);
    expect(d.upload.key).not.toContain("..");
    expect(d.upload.key.endsWith("/passwd")).toBe(true);
    expect(safeFileName("..")).toBe("file");
  });

  test("file above MAX_UPLOAD_BYTES → 413", async () => {
    const res = await req(t, "/api/uploads/sign", {
      method: "POST",
      cookie: alice.cookie,
      body: { fileName: "huge.bin", contentType: "application/octet-stream", sizeBytes: 26_214_401 },
    });
    expect(res.status).toBe(413);
    expect((await failure(res)).error).toContain("byte upload limit");
  });

  test("invalid payloads → 400 (bad mime, zero/negative size, empty name)", async () => {
    const cases = [
      { fileName: "a.png", contentType: "not-a-mime", sizeBytes: 10 },
      { fileName: "a.png", contentType: "image/png", sizeBytes: 0 },
      { fileName: "a.png", contentType: "image/png", sizeBytes: -5 },
      { fileName: "", contentType: "image/png", sizeBytes: 10 },
    ];
    for (const body of cases) {
      const res = await req(t, "/api/uploads/sign", {
        method: "POST",
        cookie: alice.cookie,
        body,
      });
      expect(res.status).toBe(400);
    }
  });

  test("anonymous → 401", async () => {
    const res = await req(t, "/api/uploads/sign", {
      method: "POST",
      body: { fileName: "a.png", contentType: "image/png", sizeBytes: 5 },
    });
    expect(res.status).toBe(401);
  });
});

describe("S3 SigV4 presigner (pure computation, fixed clock)", () => {
  const storage = {
    mode: "s3" as const,
    endpoint: "https://acct.r2.cloudflarestorage.com",
    region: "auto",
    bucket: "hush-uploads",
    accessKeyId: "AKIDEXAMPLE",
    secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
    maxUploadBytes: 26_214_400,
  };
  const fixedNow = () => new Date("2026-06-15T12:34:56.789Z");

  test("produces a presigned PUT with the full SigV4 query", async () => {
    const signer = createS3Presigner(storage, { now: fixedNow });
    const signed = await signer.sign({
      key: "uploads/u1/2026/06/file name.png",
      contentType: "image/png",
      expiresInSec: 900,
    });

    const url = new URL(signed.uploadUrl);
    expect(url.origin).toBe("https://acct.r2.cloudflarestorage.com");
    expect(url.pathname).toBe("/hush-uploads/uploads/u1/2026/06/file%20name.png");

    const q = url.searchParams;
    expect(q.get("X-Amz-Algorithm")).toBe("AWS4-HMAC-SHA256");
    expect(q.get("X-Amz-Date")).toBe("20260615T123456Z");
    expect(q.get("X-Amz-Expires")).toBe("900");
    expect(q.get("X-Amz-SignedHeaders")).toBe("content-type;host");
    expect(q.get("X-Amz-Credential")).toBe(
      "AKIDEXAMPLE/20260615/auto/s3/aws4_request",
    );
    const signature = q.get("X-Amz-Signature");
    expect(signature).toMatch(/^[0-9a-f]{64}$/);

    expect(signed.method).toBe("PUT");
    expect(signed.headers["content-type"]).toBe("image/png");
    // expiresAt = fixed clock + ttl
    expect(signed.expiresAt).toBe(new Date(Date.parse("2026-06-15T12:34:56.789Z") + 900_000).toISOString());

    // signature must be deterministic for the same inputs/clock
    const again = await signer.sign({
      key: "uploads/u1/2026/06/file name.png",
      contentType: "image/png",
      expiresInSec: 900,
    });
    expect(again.uploadUrl).toBe(signed.uploadUrl);
  });

  test("signature is deterministic; RFC3986-reserved characters in keys are fully encoded", async () => {
    const signer = createS3Presigner(storage, { now: fixedNow });
    const tricky = await signer.sign({
      key: "uploads/u1/wei?rd #name!(x)*'.txt",
      contentType: "text/plain",
      expiresInSec: 900,
    });
    const url = new URL(tricky.uploadUrl);
    // !'()* and ?#/ are percent-encoded in the canonical path…
    expect(url.pathname).not.toContain("!");
    expect(url.pathname).not.toContain("'");
    expect(url.pathname).toContain("%21"); // "!"
    expect(url.searchParams.get("X-Amz-Signature")).toMatch(/^[0-9a-f]{64}$/);
  });

  test("missing credentials → constructor throws", () => {
    expect(() =>
      createS3Presigner({ ...storage, secretAccessKey: null }),
    ).toThrow("S3 signer requires");
  });
});

describe("signer mode dispatch", () => {
  test("local mode → local:// URL; s3 mode → presigned https URL", async () => {
    const local = await createLocalSigner().sign({ key: "k/f.txt", contentType: "text/plain" });
    expect(local.uploadUrl.startsWith("local://")).toBe(true);

    const viaFactory = createUploadSigner({
      mode: "local",
      endpoint: null,
      region: "auto",
      bucket: null,
      accessKeyId: null,
      secretAccessKey: null,
      maxUploadBytes: 100,
    });
    const local2 = await viaFactory.sign({ key: "k", contentType: "text/plain" });
    expect(local2.uploadUrl.startsWith("local://")).toBe(true);

    const s3 = createUploadSigner({
      mode: "s3",
      endpoint: "https://s3.example.com",
      region: "us-east-1",
      bucket: "b",
      accessKeyId: "AK",
      secretAccessKey: "SK",
      maxUploadBytes: 100,
    });
    const signed = await s3.sign({ key: "k", contentType: "text/plain" });
    expect(signed.uploadUrl.startsWith("https://s3.example.com/")).toBe(true);
  });
});
