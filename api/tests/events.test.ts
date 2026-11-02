/**
 * Event bus: MemoryBus (recording + subscriptions) and the Ably REST stub
 * (with injected fetch — never a real network call in tests).
 */
import { describe, expect, test } from "bun:test";
import { AblyBus, MemoryBus } from "../src/events/bus";
import { EVENTS, publishEvent, targets } from "../src/realtime/publish";

describe("MemoryBus", () => {
  test("records every publish and fans out to exact/prefix/star subscribers", async () => {
    const bus = new MemoryBus();
    const exact: string[] = [];
    const prefix: string[] = [];
    const star: string[] = [];

    const offExact = bus.subscribe("channel:c1", (m) => exact.push(m.event));
    const offPrefix = bus.subscribe("user:*", (m) => prefix.push(m.target));
    const offStar = bus.subscribe("*", () => star.push("hit"));

    await bus.publish("channel:c1", EVENTS.MESSAGE_CREATED, { id: "m1" });
    await bus.publish("user:u9", EVENTS.UNREAD_BUMPED, { userId: "u9" });

    expect(exact).toEqual([EVENTS.MESSAGE_CREATED]);
    expect(prefix).toEqual(["user:u9"]);
    expect(star).toHaveLength(2);
    expect(bus.published).toHaveLength(2);
    expect(bus.find(EVENTS.MESSAGE_CREATED)[0]?.data).toEqual({ id: "m1" });

    offExact();
    offPrefix();
    offStar();
    await bus.publish("channel:c1", EVENTS.MESSAGE_UPDATED, { id: "m1" });
    expect(exact).toHaveLength(1); // unchanged — the second event never reached it
    expect(star).toHaveLength(2); // unsubscribed before the second publish
    expect(bus.published).toHaveLength(3); // recording is independent of listeners

    bus.clear();
    expect(bus.published).toHaveLength(0);
  });

  test("target helpers keep channel naming consistent", () => {
    expect(targets.channel("abc")).toBe("channel:abc");
    expect(targets.workspace("w1")).toBe("workspace:w1");
    expect(targets.user("u1")).toBe("user:u1");
  });

  test("publishEvent passes typed payload through", async () => {
    const bus = new MemoryBus();
    await publishEvent(bus, targets.channel("c"), EVENTS.TYPING, {
      channelId: "c",
      userId: "u",
    });
    expect(bus.published[0]?.event).toBe("typing");
    expect(bus.published[0]?.data).toEqual({ channelId: "c", userId: "u" });
  });
});

describe("AblyBus (REST stub)", () => {
  test("no API key → no-op, fetch never called", async () => {
    let called = 0;
    const bus = new AblyBus(null, {
      fetchImpl: (async () => {
        called += 1;
        return new Response("{}", { status: 200 });
      }) as unknown as typeof fetch,
    });
    await bus.publish("channel:c1", EVENTS.MESSAGE_CREATED, { id: "x" });
    expect(called).toBe(0);
  });

  test("publishes to the Ably REST endpoint with basic auth and the event envelope", async () => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const bus = new AblyBus("appId.keyId:secret", {
      fetchImpl: (async (url: string | URL | Request, init?: RequestInit) => {
        calls.push({ url: String(url), init: init ?? {} });
        return new Response("{}", { status: 200 });
      }) as unknown as typeof fetch,
    });

    await bus.publish("channel:c1", EVENTS.MESSAGE_CREATED, { id: "m9" });

    expect(calls).toHaveLength(1);
    const call = calls[0]!;
    expect(call.url).toBe("https://rest.ably.io/channels/channel%3Ac1/events");
    const headers = call.init.headers as Record<string, string>;
    expect(headers.authorization).toBe(`Basic ${btoa("appId.keyId:secret")}`);
    expect(headers["content-type"]).toBe("application/json");
    expect(JSON.parse(String(call.init.body))).toEqual({
      name: EVENTS.MESSAGE_CREATED,
      data: { id: "m9" },
    });
  });

  test("broker failures are swallowed (realtime is best-effort)", async () => {
    const failing = new AblyBus("k", {
      fetchImpl: (async () => {
        throw new Error("network down");
      }) as unknown as typeof fetch,
    });
    await expect(failing.publish("channel:c", EVENTS.PRESENCE, {})).resolves.toBeUndefined();

    const badStatus = new AblyBus("k", {
      fetchImpl: (async () => new Response("nope", { status: 500 })) as unknown as typeof fetch,
    });
    await expect(badStatus.publish("channel:c", EVENTS.PRESENCE, {})).resolves.toBeUndefined();
  });
});
