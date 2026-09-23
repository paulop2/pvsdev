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
    const parsed = JSON.parse(payload) as {
      response?: unknown;
      choices?: Array<{ delta?: { content?: unknown }; finish_reason?: unknown }>;
    };
    if (typeof parsed.response === 'string' && parsed.response.length > 0) {
      return { kind: 'delta', text: parsed.response };
    }
    const choice = parsed.choices?.[0];
    const content = choice?.delta?.content;
    if (typeof content === 'string' && content.length > 0) {
      return { kind: 'delta', text: content };
    }
    if (typeof choice?.finish_reason === 'string' && choice.finish_reason.length > 0) {
      return { kind: 'done' };
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

export function toTextStream(options: ChatStreamOptions): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  return new ReadableStream<Uint8Array>({
    async start(controller) {
      const reader = options.upstream.getReader();
      const fail = (error: unknown): void => {
        options.onError?.(error);
        try {
          controller.error(error);
        } catch {
          // stream ja encerrado
        }
      };
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
              controller.enqueue(encoder.encode(parsed.text));
            } else if (parsed.kind === 'done') {
              sawDone = true;
            }
          }
        }
        if (buffer.length > 0) {
          const parsed = parseUpstreamFrame(buffer);
          if (parsed.kind === 'delta') {
            completion += parsed.text;
            controller.enqueue(encoder.encode(parsed.text));
          } else if (parsed.kind === 'done') {
            sawDone = true;
          }
        }
        if (!sawDone) {
          fail(new Error('stream truncated'));
          return;
        }
        const usage: Usage = {
          prompt: estimateTokens(options.promptChars),
          completion: estimateTokens(completion.length),
        };
        try {
          await options.onUsage(usage);
        } catch (error) {
          options.onError?.(error);
        }
        controller.close();
      } catch (error) {
        fail(error);
      }
    },
  });
}
