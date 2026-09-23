import {
  TextStreamChatTransport,
  type ChatTransport,
  type HttpChatTransportInitOptions,
  type UIMessage,
  type UIMessageChunk,
} from 'ai';

export interface WorkerMessage {
  role: 'user' | 'assistant';
  content: string;
}

const MAX_MESSAGES = 12;

export function messageText(message: UIMessage): string {
  return message.parts.reduce((text, part) => (part.type === 'text' ? text + part.text : text), '');
}

export function toWorkerMessages(messages: readonly UIMessage[]): WorkerMessage[] {
  const converted: WorkerMessage[] = [];
  for (const message of messages) {
    if (message.role !== 'user' && message.role !== 'assistant') {
      continue;
    }
    const content = messageText(message).trim();
    if (content.length === 0) {
      continue;
    }
    converted.push({ role: message.role, content });
  }
  return converted.slice(-MAX_MESSAGES);
}

export interface TurnstileTransportOptions<UI_MESSAGE extends UIMessage>
  extends HttpChatTransportInitOptions<UI_MESSAGE> {
  getToken: () => string;
  onRequestSettled: () => void;
}

export class TurnstileChatTransport<
  UI_MESSAGE extends UIMessage = UIMessage,
> extends TextStreamChatTransport<UI_MESSAGE> {
  private readonly onRequestSettled: () => void;

  constructor({ getToken, onRequestSettled, ...options }: TurnstileTransportOptions<UI_MESSAGE>) {
    super({
      ...options,
      prepareSendMessagesRequest: ({ messages }) => ({
        body: {
          messages: toWorkerMessages(messages),
          turnstileToken: getToken(),
        },
      }),
    });
    this.onRequestSettled = onRequestSettled;
  }

  override async sendMessages(
    options: Parameters<ChatTransport<UI_MESSAGE>['sendMessages']>[0],
  ): Promise<ReadableStream<UIMessageChunk>> {
    try {
      return await super.sendMessages(options);
    } finally {
      this.onRequestSettled();
    }
  }
}
