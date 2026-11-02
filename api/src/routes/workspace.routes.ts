/**
 * Workspace routes: listing/creation, members, invites (create/join/accept).
 *
 * Access rules:
 *  - list/create/detail/members: any authenticated user (detail+members need
 *    membership via requireWorkspaceMember → 403 for outsiders)
 *  - invites: admin+ role
 *  - join/accept: no membership required BY DESIGN (a valid invite code/token
 *    is the credential) — still 401 without a session, 400/403/409 on bad
 *    credentials, 429 when rate-limited.
 */
import { randomBytes } from "node:crypto";
import { and, eq, isNull } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { requireAuth, requireWorkspaceMember } from "../auth/middleware";
import type { AppContext, AppEnv } from "../context";
import { isUniqueViolation } from "../db/client";
import { invites, users, workspaceMembers, workspaces } from "../db/schema";
import { fail, isUuid, ok, readJson } from "../http";

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I

function randomCode(length: number): string {
  const bytes = randomBytes(length);
  let out = "";
  for (let i = 0; i < length; i++) {
    out += CODE_ALPHABET[(bytes[i] ?? 0) % CODE_ALPHABET.length];
  }
  return out;
}

function randomToken(): string {
  return randomBytes(24).toString("base64url");
}

export function slugify(input: string): string {
  const slug = input
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+/, "")
    .replace(/-+$/, "")
    .slice(0, 48)
    .replace(/-+$/, "");
  return slug.length >= 2 ? slug : `workspace-${randomCode(4).toLowerCase()}`;
}

const createWorkspaceSchema = z.object({
  name: z.string().trim().min(1, "name is required").max(80, "name is too long"),
  slug: z
    .string()
    .trim()
    .min(2)
    .max(48)
    .regex(/^[a-z0-9][a-z0-9-]*$/, "slug must be lowercase letters, numbers and dashes")
    .optional(),
});

const createInviteSchema = z.object({
  email: z.string().trim().email("must be a valid email").max(254).optional(),
  expiresInHours: z.number().int().min(1).max(720).optional(),
});

const joinSchema = z.object({
  inviteCode: z.string().trim().min(4).max(32),
});

const acceptSchema = z.object({
  token: z.string().trim().min(16).max(128),
});

export function workspaceRoutes(ctx: AppContext): Hono<AppEnv> {
  const { db } = ctx;
  const app = new Hono<AppEnv>();

  // --- list -----------------------------------------------------------------
  app.get("/api/workspaces", requireAuth, async (c) => {
    const userId = c.get("userId");
    const rows = await db
      .select({
        id: workspaces.id,
        name: workspaces.name,
        slug: workspaces.slug,
        inviteCode: workspaces.inviteCode,
        createdAt: workspaces.createdAt,
        role: workspaceMembers.role,
        joinedAt: workspaceMembers.createdAt,
      })
      .from(workspaceMembers)
      .innerJoin(workspaces, eq(workspaces.id, workspaceMembers.workspaceId))
      .where(eq(workspaceMembers.userId, userId))
      .orderBy(workspaces.createdAt);

    return ok(c, {
      workspaces: rows.map((r) => ({
        id: r.id,
        name: r.name,
        slug: r.slug,
        role: r.role,
        createdAt: r.createdAt.toISOString(),
        joinedAt: r.joinedAt.toISOString(),
        // invite codes are shareable secrets: only admin+ see them
        ...(r.role !== "member" ? { inviteCode: r.inviteCode } : {}),
      })),
    });
  });

  // --- create ---------------------------------------------------------------
  app.post("/api/workspaces", requireAuth, async (c) => {
    const body = await readJson(c, createWorkspaceSchema);
    if (body.error) return body.error;
    const userId = c.get("userId");

    const baseSlug = slugify(body.value.slug ?? body.value.name);
    const explicitSlug = body.value.slug !== undefined;
    const maxAttempts = explicitSlug ? 1 : 5;

    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      const slug =
        attempt === 0 ? baseSlug : `${baseSlug.slice(0, 40)}-${randomCode(4).toLowerCase()}`;
      try {
        const workspace = await db.transaction(async (tx) => {
          const inserted = await tx
            .insert(workspaces)
            .values({
              name: body.value.name,
              slug,
              inviteCode: randomCode(8),
            })
            .returning();
          const row = inserted[0];
          if (!row) throw new Error("workspace insert returned no row");
          await tx.insert(workspaceMembers).values({
            workspaceId: row.id,
            userId,
            role: "owner",
          });
          return row;
        });
        return ok(
          c,
          {
            workspace: {
              id: workspace.id,
              name: workspace.name,
              slug: workspace.slug,
              inviteCode: workspace.inviteCode,
              role: "owner" as const,
              createdAt: workspace.createdAt.toISOString(),
            },
          },
          201,
        );
      } catch (err) {
        if (isUniqueViolation(err) && attempt < maxAttempts - 1) continue;
        if (isUniqueViolation(err)) return fail(c, 409, "workspace slug already exists");
        throw err;
      }
    }
    // unreachable: the loop either returns or throws
    return fail(c, 500, "internal server error");
  });

  // --- detail ---------------------------------------------------------------
  app.get("/api/workspaces/:workspaceId", requireAuth, requireWorkspaceMember(), async (c) => {
    const workspaceId = c.get("workspaceId");
    const role = c.get("membership").role;
    const rows = await db.select().from(workspaces).where(eq(workspaces.id, workspaceId)).limit(1);
    const workspace = rows[0];
    if (!workspace) return fail(c, 403, "forbidden");
    return ok(c, {
      workspace: {
        id: workspace.id,
        name: workspace.name,
        slug: workspace.slug,
        role,
        createdAt: workspace.createdAt.toISOString(),
        ...(role !== "member" ? { inviteCode: workspace.inviteCode } : {}),
      },
    });
  });

  // --- members --------------------------------------------------------------
  app.get(
    "/api/workspaces/:workspaceId/members",
    requireAuth,
    requireWorkspaceMember(),
    async (c) => {
      const workspaceId = c.get("workspaceId");
      const rows = await db
        .select({
          userId: workspaceMembers.userId,
          role: workspaceMembers.role,
          joinedAt: workspaceMembers.createdAt,
          name: users.name,
          email: users.email,
          image: users.image,
        })
        .from(workspaceMembers)
        .innerJoin(users, eq(users.id, workspaceMembers.userId))
        .where(eq(workspaceMembers.workspaceId, workspaceId))
        .orderBy(workspaceMembers.createdAt);

      return ok(c, {
        members: rows.map((r) => ({
          userId: r.userId,
          role: r.role,
          name: r.name,
          email: r.email,
          image: r.image,
          joinedAt: r.joinedAt.toISOString(),
        })),
      });
    },
  );

  // --- create invite (admin+) ----------------------------------------------
  app.post(
    "/api/workspaces/:workspaceId/invites",
    requireAuth,
    requireWorkspaceMember("workspaceId", "admin"),
    async (c) => {
      const body = await readJson(c, createInviteSchema);
      if (body.error) return body.error;
      const workspaceId = c.get("workspaceId");
      const session = c.get("session");
      const hours = body.value.expiresInHours ?? 7 * 24;

      const [invite] = await db
        .insert(invites)
        .values({
          workspaceId,
          email: body.value.email ?? null,
          token: randomToken(),
          expiresAt: new Date(Date.now() + hours * 3600_000),
          invitedBy: session.user.id,
        })
        .returning();
      if (!invite) return fail(c, 500, "internal server error");

      const acceptUrl = `${new URL(ctx.config.betterAuthUrl).origin}/invite/${invite.token}`;
      return ok(
        c,
        {
          invite: {
            id: invite.id,
            workspaceId,
            email: invite.email,
            token: invite.token,
            expiresAt: invite.expiresAt.toISOString(),
            acceptedAt: null,
            acceptUrl,
          },
        },
        201,
      );
    },
  );

  // --- join by workspace invite code ---------------------------------------
  app.post("/api/workspaces/:workspaceId/join", requireAuth, async (c) => {
    const workspaceId = c.req.param("workspaceId");
    if (!workspaceId || !isUuid(workspaceId)) return fail(c, 400, "invalid workspace id");
    const body = await readJson(c, joinSchema);
    if (body.error) return body.error;
    const userId = c.get("userId");

    const rows = await db
      .select({ id: workspaces.id })
      .from(workspaces)
      .where(
        and(eq(workspaces.id, workspaceId), eq(workspaces.inviteCode, body.value.inviteCode.toUpperCase())),
      )
      .limit(1);
    // bad code and unknown workspace are the same answer: the code IS the
    // credential, so responses must not distinguish them.
    if (!rows[0]) return fail(c, 400, "invalid invite code");

    const inserted = await db
      .insert(workspaceMembers)
      .values({ workspaceId, userId, role: "member" })
      .onConflictDoNothing()
      .returning();
    const membership =
      inserted[0] ??
      (
        await db
          .select()
          .from(workspaceMembers)
          .where(
            and(
              eq(workspaceMembers.workspaceId, workspaceId),
              eq(workspaceMembers.userId, userId),
            ),
          )
          .limit(1)
      )[0];
    if (!membership) return fail(c, 500, "internal server error");

    return ok(c, {
      workspaceId,
      membership: { role: membership.role, joinedAt: membership.createdAt.toISOString() },
      alreadyMember: inserted.length === 0,
    });
  });

  // --- accept an email invite by token --------------------------------------
  app.post("/api/invites/accept", requireAuth, async (c) => {
    const body = await readJson(c, acceptSchema);
    if (body.error) return body.error;
    const userId = c.get("userId");
    const userEmail = c.get("session").user.email.toLowerCase();
    const now = new Date();

    const rows = await db
      .select()
      .from(invites)
      .where(eq(invites.token, body.value.token))
      .limit(1);
    const invite = rows[0];
    if (!invite) return fail(c, 400, "invalid invite");
    if (invite.acceptedAt) return fail(c, 409, "invite already used");
    if (invite.expiresAt.getTime() <= now.getTime()) return fail(c, 400, "invite expired");
    if (invite.email && invite.email.toLowerCase() !== userEmail) {
      return fail(c, 403, "invite was issued to a different email");
    }

    // Atomic claim: only one concurrent accept can win.
    const claimed = await db
      .update(invites)
      .set({ acceptedAt: now })
      .where(and(eq(invites.id, invite.id), isNull(invites.acceptedAt)))
      .returning({ id: invites.id });
    if (!claimed[0]) return fail(c, 409, "invite already used");

    const inserted = await db
      .insert(workspaceMembers)
      .values({ workspaceId: invite.workspaceId, userId, role: "member" })
      .onConflictDoNothing()
      .returning();
    const membership =
      inserted[0] ??
      (
        await db
          .select()
          .from(workspaceMembers)
          .where(
            and(
              eq(workspaceMembers.workspaceId, invite.workspaceId),
              eq(workspaceMembers.userId, userId),
            ),
          )
          .limit(1)
      )[0];
    if (!membership) return fail(c, 500, "internal server error");

    return ok(c, {
      workspaceId: invite.workspaceId,
      membership: { role: membership.role, joinedAt: membership.createdAt.toISOString() },
      alreadyMember: inserted.length === 0,
    });
  });

  return app;
}
