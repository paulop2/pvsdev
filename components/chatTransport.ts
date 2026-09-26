import {
  TextStreamChatTransport,
  type HttpChatTransportInitOptions,
  type UIMessage,
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

export interface WorkerTransportOptions<UI_MESSAGE extends UIMessage>
  extends HttpChatTransportInitOptions<UI_MESSAGE> {
  /**
   * Registra a thread dona da requisicao antes de enviar o historico. O AI SDK
   * informa o id da thread em `chatId`; o assistant-ui promove a thread em
   * memoria de "new" para a lista assim que ela e inicializada.
   */
  initializeThread?: (threadId: string) => Promise<void> | void;
}

export class WorkerChatTransport<
  UI_MESSAGE extends UIMessage = UIMessage,
> extends TextStreamChatTransport<UI_MESSAGE> {
  constructor({ initializeThread, ...options }: WorkerTransportOptions<UI_MESSAGE>) {
    super({
      ...options,
      prepareSendMessagesRequest: async ({ messages, id }) => {
        await initializeThread?.(id);
        return {
          body: {
            messages: toWorkerMessages(messages),
          },
        };
      },
    });
  }
}
