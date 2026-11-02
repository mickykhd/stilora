/**
 * In-process token-bucket rate limiter.
 *
 * Buckets are keyed by (class, client IP[, route]):
 *  - auth:   30 req/min  per IP across all /api/auth/* traffic
 *  - route:  120 req/min per IP per route path
 *  - global: 600 req/min per IP safety net
 *
 * Limits are tunable via env (RATE_LIMIT_*_PER_MIN). When a bucket is empty the
 * request is rejected with 429 + Retry-After (seconds until one token refills).
 *
 * Everything lives in process memory: perfect for a single instance / dev /
 * tests. For multi-instance deployments put a shared limiter (e.g. Upstash
 * Redis) behind the same interface — see README "Self-hosting".
 */
export type RateLimitClass = "auth" | "route" | "global";

export interface RateLimitDecision {
  allowed: boolean;
  /** Seconds the client should wait before retrying (meaningful when !allowed). */
  retryAfterSeconds: number;
  /** Whole tokens left in the bucket after this check. */
  remaining: number;
}

export interface LimiterOptions {
  authPerMin: number;
  routePerMin: number;
  globalPerMin: number;
  /** Clock injection for deterministic tests. */
  now?: () => number;
  /** Safety valve: prune idle buckets beyond this many entries. */
  maxBuckets?: number;
}

interface Bucket {
  tokens: number;
  updatedAt: number;
}

const DEFAULT_MAX_BUCKETS = 10_000;
const IDLE_MS = 10 * 60 * 1000;

export class TokenBucketLimiter {
  private readonly buckets = new Map<string, Bucket>();
  private readonly now: () => number;
  private readonly maxBuckets: number;
  readonly limits: Record<RateLimitClass, number>;

  constructor(options: LimiterOptions) {
    this.now = options.now ?? Date.now;
    this.maxBuckets = options.maxBuckets ?? DEFAULT_MAX_BUCKETS;
    this.limits = {
      auth: options.authPerMin,
      route: options.routePerMin,
      global: options.globalPerMin,
    };
  }

  /** Consume one token from `key`'s bucket, refilling based on elapsed time. */
  check(key: string, rateClass: RateLimitClass): RateLimitDecision {
    const limit = this.limits[rateClass];
    const refillPerMs = limit / 60_000;
    const now = this.now();

    let bucket = this.buckets.get(key);
    if (!bucket) {
      this.pruneIfNeeded(now);
      bucket = { tokens: limit, updatedAt: now };
      this.buckets.set(key, bucket);
    } else {
      const elapsed = now - bucket.updatedAt;
      if (elapsed > 0) {
        bucket.tokens = Math.min(limit, bucket.tokens + elapsed * refillPerMs);
        bucket.updatedAt = now;
      }
    }

    if (bucket.tokens >= 1) {
      bucket.tokens -= 1;
      return { allowed: true, retryAfterSeconds: 0, remaining: Math.floor(bucket.tokens) };
    }

    const deficit = 1 - bucket.tokens;
    const retryAfterSeconds = Math.max(1, Math.ceil(deficit / refillPerMs / 1000));
    return { allowed: false, retryAfterSeconds, remaining: 0 };
  }

  /** Reset — used by tests. */
  clear(): void {
    this.buckets.clear();
  }

  private pruneIfNeeded(now: number): void {
    if (this.buckets.size < this.maxBuckets) return;
    for (const [key, bucket] of this.buckets) {
      if (now - bucket.updatedAt > IDLE_MS) this.buckets.delete(key);
    }
    // Still too big after pruning idle entries: drop everything rather than
    // grow unboundedly (fail open — availability beats strict limiting).
    if (this.buckets.size >= this.maxBuckets) this.buckets.clear();
  }
}
