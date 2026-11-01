/**
 * Realtime event bus.
 *
 * The app publishes domain events through this thin interface:
 *  - MemoryBus: in-process implementation used by tests and single-node dev.
 *  - AblyBus:   thin REST stub driven by ABLY_API_KEY — no Ably SDK, no live
 *               account needed. If the key is missing it is a no-op.
 *
 * Realtime is best-effort: publish failures are logged, never surfaced to the
 * HTTP path (the write already succeeded).
 */
export interface BusMessage {
  /** Channel/room target, e.g. `channel:abc`, `workspace:xyz`, `user:u1`. */
  target: string;
  /** Event name (see src/realtime/publish.ts). */
  event: string;
  data: unknown;
  at: number;
}

export interface EventBus {
  publish(target: string, event: string, data: unknown): Promise<void>;
}

type Listener = (message: BusMessage) => void;

/** In-memory bus: records everything and supports pattern subscriptions. */
export class MemoryBus implements EventBus {
  readonly published: BusMessage[] = [];
  private readonly listeners = new Map<string, Set<Listener>>();

  async publish(target: string, event: string, data: unknown): Promise<void> {
    const message: BusMessage = { target, event, data, at: Date.now() };
    this.published.push(message);
    for (const [pattern, set] of this.listeners) {
      const matches =
        pattern === "*" ||
        pattern === target ||
        (pattern.endsWith("*") && target.startsWith(pattern.slice(0, -1)));
      if (matches) for (const listener of set) listener(message);
    }
  }

  /** Subscribe to an exact target or a `prefix*` pattern. Returns unsubscribe. */
  subscribe(pattern: string, listener: Listener): () => void {
    const set = this.listeners.get(pattern) ?? new Set<Listener>();
    set.add(listener);
    this.listeners.set(pattern, set);
    return () => {
      set.delete(listener);
      if (set.size === 0) this.listeners.delete(pattern);
    };
  }

  /** Convenience for assertions in tests. */
  find(event: string): BusMessage[] {
    return this.published.filter((m) => m.event === event);
  }

  clear(): void {
    this.published.length = 0;
  }
}

export interface AblyBusOptions {
  /** Injected for tests so no real network call is ever made in the suite. */
  fetchImpl?: typeof fetch;
}

/**
 * Ably REST publisher. Publishes to `https://rest.ably.io/channels/{ch}/events`
 * with the key as HTTP basic auth — deliberately dependency-free.
 */
export class AblyBus implements EventBus {
  private readonly fetchImpl: typeof fetch;

  constructor(
    private readonly apiKey: string | null,
    options: AblyBusOptions = {},
  ) {
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async publish(target: string, event: string, data: unknown): Promise<void> {
    if (!this.apiKey) return; // not configured → no-op
    const channel = encodeURIComponent(target);
    try {
      const res = await this.fetchImpl(`https://rest.ably.io/channels/${channel}/events`, {
        method: "POST",
        headers: {
          authorization: `Basic ${btoa(this.apiKey)}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ name: event, data }),
      });
      if (!res.ok) {
        console.warn(`[events] ably publish failed (${res.status}) for ${event}@${target}`);
      }
    } catch (err) {
      // Realtime is best-effort; a broker hiccup must not fail the API call.
      console.warn(`[events] ably publish error for ${event}@${target}:`, err);
    }
  }
}
