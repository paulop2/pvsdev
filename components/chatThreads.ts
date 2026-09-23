export const THREAD_TITLE_FALLBACK = 'Nova conversa';

export function threadTitleFallback(title: string | undefined | null): string {
  const trimmed = title?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : THREAD_TITLE_FALLBACK;
}

export function normalizeThreadTitle(
  input: string,
  current: string | undefined | null,
): string | null {
  const next = input.trim();
  if (next.length === 0) {
    return null;
  }
  const previous = current?.trim() ?? '';
  return next === previous ? null : next;
}
