import type { Config } from './config';

export type Role = 'user' | 'assistant';

export interface ChatMessage {
  role: Role;
  content: string;
}

export interface ChatRequest {
  messages: ChatMessage[];
  turnstileToken: string;
}

export type ValidationResult =
  | { ok: true; value: ChatRequest }
  | { ok: false; error: string };

export function validateChatRequest(body: unknown, config: Config): ValidationResult {
  if (typeof body !== 'object' || body === null) {
    return { ok: false, error: 'body must be an object' };
  }
  const record = body as Record<string, unknown>;
  const token = record.turnstileToken;
  if (typeof token !== 'string' || token.trim().length === 0) {
    return { ok: false, error: 'turnstileToken is required' };
  }
  const messages = record.messages;
  if (!Array.isArray(messages) || messages.length === 0) {
    return { ok: false, error: 'messages must be a non-empty array' };
  }
  if (messages.length > config.maxMessages) {
    return { ok: false, error: `messages must have at most ${config.maxMessages} items` };
  }
  const parsed: ChatMessage[] = [];
  let total = 0;
  for (const item of messages) {
    if (typeof item !== 'object' || item === null) {
      return { ok: false, error: 'each message must be an object' };
    }
    const message = item as Record<string, unknown>;
    if (message.role !== 'user' && message.role !== 'assistant') {
      return { ok: false, error: 'role must be user or assistant' };
    }
    if (typeof message.content !== 'string' || message.content.length === 0) {
      return { ok: false, error: 'content must be a non-empty string' };
    }
    if (message.content.length > config.maxCharsPerMessage) {
      return {
        ok: false,
        error: `content must have at most ${config.maxCharsPerMessage} chars`,
      };
    }
    total += message.content.length;
    parsed.push({ role: message.role, content: message.content });
  }
  if (total > config.maxTotalChars) {
    return { ok: false, error: `total content must have at most ${config.maxTotalChars} chars` };
  }
  if (parsed[parsed.length - 1].role !== 'user') {
    return { ok: false, error: 'last message must be from user' };
  }
  return { ok: true, value: { messages: parsed, turnstileToken: token } };
}
