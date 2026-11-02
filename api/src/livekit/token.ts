/**
 * LiveKit integration: access-token minting + room state.
 *
 * Both collaborators are interfaces so tests inject fakes (the suite must run
 * with no network and no LiveKit account). The default implementations only
 * talk to LiveKit when a route is actually hit in production.
 */
import { ParticipantInfo_State } from "@livekit/protocol";
import { AccessToken, RoomServiceClient } from "livekit-server-sdk";
import type { LiveKitConfig } from "../config";

export interface MintOptions {
  /** Participant identity — always the session user id (see voice.routes). */
  identity: string;
  /** Display name shown in the voice room UI. */
  name: string;
  /** LiveKit room name (derived from the channel id). */
  room: string;
  ttlSeconds?: number;
}

export interface TokenMinter {
  mint(options: MintOptions): Promise<string>;
}

export interface VoiceParticipant {
  identity: string;
  name: string;
  state: "JOINING" | "ACTIVE" | "DISCONNECTED" | string;
  joinedAt: string | null;
}

export interface VoiceRoomState {
  room: string;
  participants: VoiceParticipant[];
  /** ISO timestamp of when the first participant joined, if anyone has. */
  startedAt: string | null;
}

export interface VoiceStateProvider {
  getState(room: string): Promise<VoiceRoomState>;
}

/** Minimal structural view of LiveKit's ParticipantInfo (avoids tight coupling). */
export interface ParticipantLike {
  identity: string;
  name?: string;
  state?: number | string;
  /** LiveKit sends join time as int64 SECONDS; older shapes used Timestamp/ISO. */
  joinedAt?: bigint | { seconds?: bigint | number | string; nanos?: number } | Date | string | null;
}

/** The subset of RoomServiceClient we use (fakeable in tests). */
export interface RoomClient {
  listParticipants(room: string): Promise<ParticipantLike[]>;
}

export function createLiveKitTokenMinter(config: LiveKitConfig): TokenMinter {
  return {
    async mint({ identity, name, room, ttlSeconds = 600 }): Promise<string> {
      const token = new AccessToken(config.apiKey, config.apiSecret, {
        identity,
        name,
        ttl: ttlSeconds,
      });
      token.addGrant({
        room,
        roomJoin: true,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true,
      });
      return await token.toJwt();
    },
  };
}

/** Convert LiveKit join time (int64 seconds) / Timestamp / Date / ISO → ISO. */
export function joinedAtToIso(value: ParticipantLike["joinedAt"]): string | null {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "string") return value;
  if (typeof value === "bigint") {
    const ms = Number(value) * 1000;
    return Number.isFinite(ms) ? new Date(ms).toISOString() : null;
  }
  if (typeof value === "object" && "seconds" in value) {
    if (value.seconds === undefined) return null;
    const ms = Number(value.seconds) * 1000 + Math.floor((value.nanos ?? 0) / 1_000_000);
    if (!Number.isFinite(ms)) return null;
    return new Date(ms).toISOString();
  }
  return null;
}

export function mapParticipant(p: ParticipantLike): VoiceParticipant {
  let state: string;
  if (typeof p.state === "number") {
    state = ParticipantInfo_State[p.state] ?? String(p.state);
  } else {
    state = p.state ?? "ACTIVE";
  }
  return {
    identity: p.identity,
    name: p.name ?? p.identity,
    state,
    joinedAt: joinedAtToIso(p.joinedAt),
  };
}

export function createLiveKitVoiceStateProvider(
  config: LiveKitConfig,
  client?: RoomClient,
): VoiceStateProvider {
  const roomClient: RoomClient =
    client ?? new RoomServiceClient(config.url, config.apiKey, config.apiSecret);
  return {
    async getState(room: string): Promise<VoiceRoomState> {
      const participants = (await roomClient.listParticipants(room)).map(mapParticipant);
      const joinedTimes = participants
        .map((p) => p.joinedAt)
        .filter((t): t is string => t !== null)
        .sort();
      return {
        room,
        participants,
        startedAt: joinedTimes[0] ?? null,
      };
    },
  };
}
