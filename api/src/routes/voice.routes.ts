/**
 * Voice rooms (LiveKit).
 *
 *  - POST /api/voice/token  {channelId} → room access token
 *  - GET  /api/voice/state  ?channelId=  → current participants
 *
 * A voice room is 1:1 with a channel (room name = `hush-channel-<id>`), so the
 * channel ACL (requireChannelMember) governs access. The participant identity
 * is ALWAYS the session user id — clients cannot mint tokens for someone else.
 *
 * When LiveKit env vars are absent both routes answer 503 (feature off).
 */
import { Hono } from "hono";
import { z } from "zod";
import { requireAuth, requireChannelMember } from "../auth/middleware";
import type { AppContext, AppEnv } from "../context";
import { fail, ok, readJson } from "../http";

const tokenSchema = z.object({
  channelId: z.string().min(1).max(64),
});

/** LiveKit room name for a channel. Shared by both endpoints. */
export function roomForChannel(channelId: string): string {
  return `hush-channel-${channelId}`;
}

const TOKEN_TTL_SECONDS = 600;

export function voiceRoutes(ctx: AppContext): Hono<AppEnv> {
  const app = new Hono<AppEnv>();

  app.post("/api/voice/token", requireAuth, requireChannelMember(), async (c) => {
    // validate the (already access-checked) payload shape for clean 400s
    const body = await readJson(c, tokenSchema);
    if (body.error) return body.error;
    const channel = c.get("channel");
    const session = c.get("session");
    const tokens = ctx.tokens;
    if (!tokens) return fail(c, 503, "voice service is not configured");

    const token = await tokens.mint({
      identity: session.user.id,
      name: session.user.name,
      room: roomForChannel(channel.id),
      ttlSeconds: TOKEN_TTL_SECONDS,
    });

    return ok(c, {
      token,
      room: roomForChannel(channel.id),
      identity: session.user.id,
      url: ctx.config.livekit?.url ?? null,
      expiresIn: TOKEN_TTL_SECONDS,
    });
  });

  app.get("/api/voice/state", requireAuth, requireChannelMember(), async (c) => {
    const channel = c.get("channel");
    const voice = ctx.voice;
    if (!voice) return fail(c, 503, "voice service is not configured");

    const state = await voice.getState(roomForChannel(channel.id));
    return ok(c, {
      room: state.room,
      channelId: channel.id,
      participants: state.participants,
      startedAt: state.startedAt,
    });
  });

  return app;
}
