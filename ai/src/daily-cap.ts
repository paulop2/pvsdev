export interface CapStore {
  get(key: string): Promise<string | null>;
  put(key: string, value: string): Promise<void>;
}

export function capKey(now: Date): string {
  return `cap:${now.toISOString().slice(0, 10)}`;
}

export async function getUsedTokens(store: CapStore, key: string): Promise<number> {
  const raw = await store.get(key);
  if (raw === null) {
    return 0;
  }
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

export async function addTokens(store: CapStore, key: string, tokens: number): Promise<void> {
  const used = await getUsedTokens(store, key);
  const delta = Number.isFinite(tokens) && tokens > 0 ? Math.floor(tokens) : 0;
  await store.put(key, String(used + delta));
}
