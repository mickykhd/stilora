/**
 * LiveKit: token minting through the injected minter (no network), the real
 * livekit-server-sdk minter running OFFLINE (pure JWT signing), voice state
 * mapping, and 503 when LiveKit isn't configured.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { ParticipantInfo_State } from "@livekit/protocol";
import {
  createTestApp,
  data,
  failure,
  makeChannel,
  makeWorkspace,
  req,
  signIn,
  uniqueEmail,
  type SignedInUser,
  type TestApp,
} from "./helpers";
import {
  createLiveKitTokenMinter,
  createLiveKitVoiceStateProvider,
  joinedAtToIso,
  mapParticipant,
} from "../src/livekit/token";
import { roomForChannel } from "../src/routes/voice.routes";

let t: TestApp;
let unconfigured: TestApp;
let alice: SignedInUser;
let wsId: string;
let channel: { id: string };

beforeAll(async () => {
  t = await createTestApp(); // voice fakes injected by helpers
  unconfigured = await createTestApp({}, { voice: false }); // tokens/voice = null
  alice = await signIn(t, uniqueEmail("alice"));
  const ws = await makeWorkspace(t, alice.cookie, "Voice WS");
  wsId = ws.id;
  channel = await makeChannel(t, alice.cookie, wsId, "huddle-room");
});
afterAll(async () => {
  await t?.close();
  await unconfigured?.close();
});

describe("POST /api/voice/token", () => {
  test("mints a token for the channel room with the session identity", async () => {
    const res = await req(t, "/api/voice/token", {
      method: "POST",
      cookie: alice.cookie,
      body: { channelId: channel.id },
    });
    expect(res.status).toBe(200);
    const d = await data<{ token: string; room: string; identity: string; expiresIn: number }>(res);
    expect(d.room).toBe(roomForChannel(channel.id));
    expect(d.identity).toBe(alice.id);
    expect(d.expiresIn).toBe(600);
    // fake minter output: test-token|<room>|<identity>|<name>|<ttl>
    expect(d.token.split("|")[0]).toBe("test-token");
    expect(d.token).toContain(alice.id);
    expect(d.token).toContain(roomForChannel(channel.id));
  });

  test("unconfigured LiveKit → 503 with a clear error", async () => {
    // sessions are per-app (separate databases) — sign in on THIS app
    const user = await signIn(unconfigured, uniqueEmail("novoice"));
    const ws = await makeWorkspace(unconfigured, user.cookie, "No Voice WS");
    const ch = await makeChannel(unconfigured, user.cookie, ws.id, "quiet-room");
    const res = await req(unconfigured, "/api/voice/token", {
      method: "POST",
      cookie: user.cookie,
      body: { channelId: ch.id },
    });
    expect(res.status).toBe(503);
    expect((await failure(res)).error).toContain("not configured");
  });

  test("missing channelId → 400", async () => {
    const res = await req(t, "/api/voice/token", {
      method: "POST",
      cookie: alice.cookie,
      body: {},
    });
    expect(res.status).toBe(400);
  });

  test("malformed JSON body → 400 (resolveId must not crash)", async () => {
    const res = await req(t, "/api/voice/token", {
      method: "POST",
      cookie: alice.cookie,
      rawBody: "{this is not json",
    });
    expect(res.status).toBe(400);
    expect((await failure(res)).error).toContain("invalid channel id");
  });
});

describe("real LiveKit clients built from env (no injection, still offline)", () => {
  test("mints a genuine JWT through livekit-server-sdk", async () => {
    const envApp = await createTestApp(
      {
        LIVEKIT_URL: "https://example.livekit.cloud",
        LIVEKIT_API_KEY: "envkey",
        LIVEKIT_API_SECRET: "env-secret-value-at-least-32-chars-long",
      },
      { voice: "env" },
    );
    try {
      const user = await signIn(envApp, uniqueEmail("envvoice"));
      const ws = await makeWorkspace(envApp, user.cookie, "Env Voice WS");
      const ch = await makeChannel(envApp, user.cookie, ws.id, "env-room");

      const res = await req(envApp, "/api/voice/token", {
        method: "POST",
        cookie: user.cookie,
        body: { channelId: ch.id },
      });
      expect(res.status).toBe(200);
      const d = await data<{ token: string; url: string | null }>(res);
      expect(d.token.split(".")).toHaveLength(3); // real JWT, signed offline
      expect(d.url).toBe("https://example.livekit.cloud");
      // NOTE: /api/voice/state with the real provider would dial LiveKit —
      // never exercised here (the suite must stay network-free). Construction
      // of both clients already happened at createApp above.
    } finally {
      await envApp.close();
    }
  });
});

describe("GET /api/voice/state", () => {
  test("returns room state from the injected provider", async () => {
    const res = await req(t, `/api/voice/state?channelId=${channel.id}`, { cookie: alice.cookie });
    expect(res.status).toBe(200);
    const d = await data<{
      room: string;
      channelId: string;
      participants: Array<{ identity: string; state: string }>;
      startedAt: string | null;
    }>(res);
    expect(d.room).toBe(roomForChannel(channel.id));
    expect(d.channelId).toBe(channel.id);
    expect(d.participants).toHaveLength(1);
    expect(d.participants[0]?.state).toBe("ACTIVE");
    expect(d.startedAt).toBe("2026-01-01T00:00:00.000Z");
  });

  test("unconfigured → 503; missing channelId → 400", async () => {
    const user = await signIn(unconfigured, uniqueEmail("novoice2"));
    const ws = await makeWorkspace(unconfigured, user.cookie, "No Voice WS 2");
    const ch = await makeChannel(unconfigured, user.cookie, ws.id, "quiet-room-2");

    const off = await req(unconfigured, `/api/voice/state?channelId=${ch.id}`, {
      cookie: user.cookie,
    });
    expect(off.status).toBe(503);

    const missing = await req(t, "/api/voice/state", { cookie: alice.cookie });
    expect(missing.status).toBe(400);
  });
});

describe("real livekit-server-sdk minter (offline — pure JWT signing)", () => {
  test("produces a valid 3-segment JWT carrying the room grant", async () => {
    const minter = createLiveKitTokenMinter({
      url: "https://example.livekit.cloud",
      apiKey: "devkey",
      apiSecret: "this-is-a-32-char-test-api-secret!",
    });

    const token = await minter.mint({
      identity: "user-abc",
      name: "Ada Lovelace",
      room: "hush-channel-123",
      ttlSeconds: 300,
    });

    const parts = token.split(".");
    expect(parts).toHaveLength(3);

    const payload = JSON.parse(Buffer.from(parts[1] as string, "base64url").toString("utf8")) as {
      sub: string;
      name: string;
      video?: { room: string; roomJoin: boolean; canPublish: boolean; canSubscribe: boolean };
      exp: number;
      iss: string;
    };
    expect(payload.sub).toBe("user-abc");
    expect(payload.name).toBe("Ada Lovelace");
    expect(payload.video?.room).toBe("hush-channel-123");
    expect(payload.video?.roomJoin).toBe(true);
    expect(payload.video?.canPublish).toBe(true);
    expect(payload.video?.canSubscribe).toBe(true);
    expect(payload.iss).toBe("devkey");
    expect(payload.exp).toBeGreaterThan(Math.floor(Date.now() / 1000));
    expect(payload.exp - Math.floor(Date.now() / 1000)).toBeLessThanOrEqual(300);
  });
});

describe("participant mapping helpers", () => {
  test("joinedAtToIso handles bigint seconds, Timestamp objects, Date and ISO strings", () => {
    expect(joinedAtToIso(1_767_225_600n)).toBe("2026-01-01T00:00:00.000Z");
    expect(joinedAtToIso({ seconds: 1_767_225_600, nanos: 0 })).toBe("2026-01-01T00:00:00.000Z");
    expect(joinedAtToIso({ seconds: 1_767_225_600, nanos: 500_000_000 })).toBe(
      "2026-01-01T00:00:00.500Z",
    );
    expect(joinedAtToIso({ seconds: undefined })).toBeNull();
    expect(joinedAtToIso(new Date("2026-01-01T00:00:00.000Z"))).toBe("2026-01-01T00:00:00.000Z");
    expect(joinedAtToIso("2026-01-01T00:00:00.000Z")).toBe("2026-01-01T00:00:00.000Z");
    expect(joinedAtToIso(null)).toBeNull();
    expect(joinedAtToIso(undefined)).toBeNull();
  });

  test("mapParticipant converts state enums and falls back to identity as name", () => {
    const mapped = mapParticipant({
      identity: "u1",
      state: ParticipantInfo_State.ACTIVE,
      joinedAt: 1_767_225_600n,
    });
    expect(mapped.state).toBe("ACTIVE");
    expect(mapped.name).toBe("u1");
    expect(mapped.joinedAt).toBe("2026-01-01T00:00:00.000Z");

    const joining = mapParticipant({ identity: "u2", name: "Bob", state: "JOINING" });
    expect(joining.state).toBe("JOINING");
    expect(joining.name).toBe("Bob");
  });

  test("voice state provider (fake RoomClient) picks earliest join as startedAt", async () => {
    const provider = createLiveKitVoiceStateProvider(
      { url: "https://x", apiKey: "k", apiSecret: "s" },
      {
        listParticipants: async () => [
          { identity: "late", state: ParticipantInfo_State.ACTIVE, joinedAt: 1_767_312_000n },
          { identity: "early", name: "Early Bird", state: ParticipantInfo_State.ACTIVE, joinedAt: 1_767_225_600n },
        ],
      },
    );

    const state = await provider.getState("hush-channel-abc");
    expect(state.room).toBe("hush-channel-abc");
    expect(state.participants).toHaveLength(2);
    expect(state.startedAt).toBe("2026-01-01T00:00:00.000Z"); // earliest join
    expect(state.participants.find((p) => p.identity === "early")?.name).toBe("Early Bird");
  });
});
