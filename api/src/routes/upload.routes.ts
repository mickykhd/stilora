/**
 * Upload signing: POST /api/uploads/sign returns a signed PUT URL.
 *
 * STORAGE_MODE=local (default/dev/tests) → no-op `local://` URL.
 * STORAGE_MODE=s3 → real SigV4 presigned URL (S3 / R2 / MinIO).
 * The storage key is namespaced under the caller's user id so a signed URL can
 * only ever write into the uploader's own folder — message creation re-checks
 * the same prefix.
 */
import { randomUUID } from "node:crypto";
import { Hono } from "hono";
import { z } from "zod";
import { requireAuth } from "../auth/middleware";
import type { AppContext, AppEnv } from "../context";
import { fail, ok, readJson } from "../http";

const signSchema = z.object({
  fileName: z.string().min(1).max(255),
  contentType: z
    .string()
    .regex(/^[\w.+-]+\/[\w.+-]+$/, "contentType must be a mime type like image/png")
    .max(100),
  sizeBytes: z.number().int().min(1),
});

/** Strip any client-provided path; keep a filesystem-safe base name. */
export function safeFileName(fileName: string): string {
  const base = fileName.split(/[/\\]/).pop() ?? "file";
  const cleaned = base.replace(/[^\w.\-+ ]/g, "_").trim();
  return cleaned === "" || cleaned === "." || cleaned === ".." ? "file" : cleaned.slice(0, 255);
}

export function uploadRoutes(ctx: AppContext): Hono<AppEnv> {
  const { config, uploads } = ctx;
  const app = new Hono<AppEnv>();

  app.post("/api/uploads/sign", requireAuth, async (c) => {
    const body = await readJson(c, signSchema);
    if (body.error) return body.error;
    const userId = c.get("userId");
    const { fileName, contentType, sizeBytes } = body.value;

    if (sizeBytes > config.storage.maxUploadBytes) {
      return fail(
        c,
        413,
        `file exceeds the ${config.storage.maxUploadBytes} byte upload limit`,
      );
    }

    const now = new Date();
    const key =
      `uploads/${userId}/${now.getUTCFullYear()}/${String(now.getUTCMonth() + 1).padStart(2, "0")}/` +
      `${randomUUID()}/${safeFileName(fileName)}`;

    const signed = await uploads.sign({ key, contentType });

    return ok(
      c,
      {
        upload: {
          uploadUrl: signed.uploadUrl,
          method: signed.method,
          key: signed.key,
          headers: signed.headers,
          expiresAt: signed.expiresAt,
        },
      },
      201,
    );
  });

  return app;
}
