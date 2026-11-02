/**
 * The dependency bundle every route handler and middleware receives.
 * Constructed once in src/app.ts (tests inject fakes for every external).
 */
import type { AuthLike, SessionInfo } from "./auth/auth";
import type { Config } from "./config";
import type { DB } from "./db/client";
import type { Channel, Message, WorkspaceMember } from "./db/schema";
import type { EventBus } from "./events/bus";
import type { TokenMinter, VoiceStateProvider } from "./livekit/token";
import type { TokenBucketLimiter } from "./ratelimit/limiter";
import type { UploadSigner } from "./storage/uploads";

export interface AppContext {
  config: Config;
  db: DB;
  auth: AuthLike;
  bus: EventBus;
  /** null when LiveKit env vars are absent → /api/voice/* answers 503. */
  tokens: TokenMinter | null;
  voice: VoiceStateProvider | null;
  uploads: UploadSigner;
  limiter: TokenBucketLimiter;
}

/**
 * Hono context variables. Set by the middleware pipeline in src/app.ts and
 * src/auth/middleware.ts — read by handlers via c.get(...).
 */
export type AppVariables = {
  ctx: AppContext;
  requestId: string;
  session: SessionInfo;
  userId: string;
  workspaceId: string;
  membership: WorkspaceMember;
  channel: Channel;
  message: Message;
};

export type AppEnv = { Variables: AppVariables };
