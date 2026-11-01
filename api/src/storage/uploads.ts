/**
 * Signed upload URLs for S3-compatible storage (AWS S3, Cloudflare R2, MinIO).
 *
 * - createLocalSigner: no-op mode for dev/tests — returns a `local://` URL, no
 *   cloud account needed.
 * - createS3Presigner: real SigV4 presigned PUT URL, implemented directly on
 *   WebCrypto (no AWS SDK, works offline; nothing here performs a network call
 *   — signing is pure computation).
 */
import type { StorageConfig } from "../config";

export interface SignUploadInput {
  /** Storage key (path) the message attachment will reference. */
  key: string;
  contentType: string;
  expiresInSec?: number;
}

export interface SignedUpload {
  uploadUrl: string;
  method: "PUT";
  key: string;
  /** Headers the client MUST send when uploading (content-type is signed). */
  headers: Record<string, string>;
  expiresAt: string;
}

export interface UploadSigner {
  sign(input: SignUploadInput): Promise<SignedUpload>;
}

const DEFAULT_TTL = 900;

export function createLocalSigner(): UploadSigner {
  return {
    async sign({ key, contentType, expiresInSec = DEFAULT_TTL }) {
      const expiresAt = new Date(Date.now() + expiresInSec * 1000);
      return {
        // `local://` is a documented no-op: nothing consumes it server-side.
        uploadUrl: `local://upload/${key}`,
        method: "PUT" as const,
        key,
        headers: { "content-type": contentType },
        expiresAt: expiresAt.toISOString(),
      };
    },
  };
}

// --- SigV4 helpers ----------------------------------------------------------

const encoder = new TextEncoder();

/** Always allocate a fresh ArrayBuffer-backed view (TS 5.7+ typed-array generics). */
function bytes(input: string | Uint8Array): Uint8Array<ArrayBuffer> {
  return input instanceof Uint8Array
    ? new Uint8Array(input)
    : new Uint8Array(encoder.encode(input));
}

async function hmac(
  key: Uint8Array | string,
  data: string,
): Promise<Uint8Array<ArrayBuffer>> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    bytes(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, encoder.encode(data));
  return new Uint8Array(sig);
}

const hex = (bytes: Uint8Array): string =>
  [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");

/** Encode every path segment RFC3986-strictly while preserving `/` separators. */
function encodePath(key: string): string {
  return key
    .split("/")
    .map((segment) => uriEncode(segment))
    .join("/");
}

/** RFC 3986 / AWS percent-encoding: encode everything except unreserved chars. */
function uriEncode(str: string): string {
  return encodeURIComponent(str).replace(
    /[!'()*]/g,
    (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

async function signingKey(
  secret: string,
  dateStamp: string,
  region: string,
  service: string,
): Promise<Uint8Array<ArrayBuffer>> {
  const kDate = await hmac(`AWS4${secret}`, dateStamp);
  const kRegion = await hmac(kDate, region);
  const kService = await hmac(kRegion, service);
  return await hmac(kService, "aws4_request");
}

export interface S3PresignerOptions {
  /** Injectable clock for deterministic tests. */
  now?: () => Date;
}

export function createS3Presigner(
  storage: StorageConfig,
  options: S3PresignerOptions = {},
): UploadSigner {
  const { bucket, accessKeyId, secretAccessKey } = storage;
  if (!bucket || !accessKeyId || !secretAccessKey) {
    throw new Error("S3 signer requires bucket, accessKeyId and secretAccessKey");
  }
  const now = options.now ?? (() => new Date());
  const endpoint =
    storage.endpoint ?? `https://s3.${storage.region === "auto" ? "us-east-1" : storage.region}.amazonaws.com`;

  return {
    async sign({ key, contentType, expiresInSec = DEFAULT_TTL }) {
      const url = new URL(endpoint);
      const date = now();
      const amzDate = date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
      const dateStamp = amzDate.slice(0, 8);
      const region = storage.region;
      const service = "s3";

      const canonicalUri = `/${bucket}/${encodePath(key.replace(/^\/+/, ""))}`;
      const credentialScope = `${dateStamp}/${region}/${service}/aws4_request`;

      const queryParams: Array<[string, string]> = [
        ["X-Amz-Algorithm", "AWS4-HMAC-SHA256"],
        ["X-Amz-Credential", `${accessKeyId}/${credentialScope}`],
        ["X-Amz-Date", amzDate],
        ["X-Amz-Expires", String(expiresInSec)],
        ["X-Amz-SignedHeaders", "content-type;host"],
      ];
      const canonicalQuery = queryParams
        .map(([k, v]) => `${uriEncode(k)}=${uriEncode(v)}`)
        .sort()
        .join("&");

      const host = url.host;
      const canonicalHeaders = `content-type:${contentType.trim()}\nhost:${host}\n`;
      const signedHeaders = "content-type;host";

      const canonicalRequest = [
        "PUT",
        canonicalUri,
        canonicalQuery,
        canonicalHeaders,
        signedHeaders,
        "UNSIGNED-PAYLOAD",
      ].join("\n");

      const cryptoDigest = new Uint8Array(
        await crypto.subtle.digest("SHA-256", encoder.encode(canonicalRequest)),
      );
      const stringToSign = [
        "AWS4-HMAC-SHA256",
        amzDate,
        credentialScope,
        hex(cryptoDigest),
      ].join("\n");

      const keyMaterial = await signingKey(secretAccessKey, dateStamp, region, service);
      const signature = hex(await hmac(keyMaterial, stringToSign));

      const finalQuery = `${canonicalQuery}&X-Amz-Signature=${signature}`;
      const uploadUrl = `${url.origin}${canonicalUri}?${finalQuery}`;

      return {
        uploadUrl,
        method: "PUT" as const,
        key,
        headers: { "content-type": contentType },
        expiresAt: new Date(date.getTime() + expiresInSec * 1000).toISOString(),
      };
    },
  };
}

export function createUploadSigner(storage: StorageConfig): UploadSigner {
  return storage.mode === "s3" ? createS3Presigner(storage) : createLocalSigner();
}
