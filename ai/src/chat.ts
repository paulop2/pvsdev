export interface ModelMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface Usage {
  prompt: number;
  completion: number;
}

export type UpstreamFrame =
  | { kind: 'delta'; text: string }
  | { kind: 'done' }
  | { kind: 'ignore' };

export function parseUpstreamFrame(line: string): UpstreamFrame {
  const trimmed = line.trim();
  if (!trimmed.startsWith('data:')) {
    return { kind: 'ignore' };
  }
  const payload = trimmed.slice(5).trim();
  if (payload.length === 0) {
    return { kind: 'ignore' };
  }
  if (payload === '[DONE]') {
    return { kind: 'done' };
  }
  try {
    const parsed = JSON.parse(payload) as { response?: unknown };
    if (typeof parsed.response === 'string' && parsed.response.length > 0) {
      return { kind: 'delta', text: parsed.response };
    }
    return { kind: 'ignore' };
  } catch {
    return { kind: 'ignore' };
  }
}

export function estimateTokens(chars: number): number {
  if (!Number.isFinite(chars) || chars <= 0) {
    return 0;
  }
  return Math.ceil(chars / 4);
}

export interface ChatStreamOptions {
  upstream: ReadableStream<Uint8Array>;
  promptChars: number;
  onUsage: (usage: Usage) => void | Promise<void>;
  onError?: (error: unknown) => void;
}

export function toSseStream(options: ChatStreamOptions): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const frame = (event: string, data: unknown): Uint8Array =>
    encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);

  return new ReadableStream<Uint8Array>({
    async start(controller) {
      const reader = options.upstream.getReader();
      let buffer = '';
      let completion = '';
      let sawDone = false;
      try {
        for (;;) {
          const { done, value } = await reader.read();
          if (done) {
            break;
          }
          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split('\n');
          buffer = lines.pop() ?? '';
          for (const line of lines) {
            const parsed = parseUpstreamFrame(line);
            if (parsed.kind === 'delta') {
              completion += parsed.text;
              controller.enqueue(frame('token', { delta: parsed.text }));
            } else if (parsed.kind === 'done') {
              sawDone = true;
            }
          }
        }
        if (buffer.length > 0) {
          const parsed = parseUpstreamFrame(buffer);
          if (parsed.kind === 'delta') {
            completion += parsed.text;
            controller.enqueue(frame('token', { delta: parsed.text }));
          } else if (parsed.kind === 'done') {
            sawDone = true;
          }
        }
        if (!sawDone) {
          controller.enqueue(frame('error', { code: 'stream_error', message: 'stream truncated' }));
          options.onError?.(new Error('stream truncated'));
          return;
        }
        const usage: Usage = {
          prompt: estimateTokens(options.promptChars),
          completion: estimateTokens(completion.length),
        };
        controller.enqueue(frame('done', { usage }));
        try {
          await options.onUsage(usage);
        } catch (error) {
          options.onError?.(error);
        }
      } catch (error) {
        controller.enqueue(frame('error', { code: 'stream_error', message: 'stream failed' }));
        options.onError?.(error);
      } finally {
        controller.close();
      }
    },
  });
}
