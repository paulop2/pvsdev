'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Script from 'next/script';
import {
  AssistantRuntimeProvider,
  AuiIf,
  ComposerPrimitive,
  MessagePrimitive,
  ThreadListItemMorePrimitive,
  ThreadListItemPrimitive,
  ThreadListPrimitive,
  ThreadPrimitive,
  useAui,
  useAuiState,
} from '@assistant-ui/react';
import { useAISDKError, useChatRuntime } from '@assistant-ui/ai-sdk';
import { MarkdownText } from '@/components/MarkdownText';
import { TurnstileChatTransport } from '@/components/chatTransport';
import {
  normalizeThreadTitle,
  THREAD_TITLE_FALLBACK,
  threadTitleFallback,
} from '@/components/chatThreads';
import styles from '@/styles/chat.module.css';

const ASSISTANT_PARTS = { Text: MarkdownText };

declare global {
  interface Window {
    turnstile?: {
      render: (
        container: HTMLElement,
        options: {
          sitekey: string;
          callback: (token: string) => void;
          'expired-callback'?: () => void;
        },
      ) => string;
      reset: (widgetId?: string) => void;
      remove: (widgetId?: string) => void;
    };
  }
}

const API_URL = process.env.NEXT_PUBLIC_CHAT_API_URL ?? '';
const SITE_KEY = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY ?? '';
const SUGGESTIONS = [
  'Quem e o Paulo?',
  'Quais projetos ele ja fez?',
  'Qual stack ele domina?',
];

function errorMessage(error: Error): string {
  const raw = error.message ?? '';
  let code = raw;
  try {
    const parsed = JSON.parse(raw) as { code?: unknown };
    if (typeof parsed.code === 'string') {
      code = parsed.code;
    }
  } catch {
    code = raw;
  }
  switch (code) {
    case 'turnstile_failed':
      return 'A verificacao de seguranca falhou. Recarregue a pagina e tente novamente.';
    case 'rate_limited':
      return 'Muitas mensagens em pouco tempo. Aguarde um minuto e tente novamente.';
    case 'daily_cap_exceeded':
      return 'Limite diario de mensagens atingido. Tente novamente mais tarde.';
    case 'upstream_error':
      return 'O assistente esta indisponivel no momento. Tente novamente.';
    case 'origin_not_allowed':
      return 'Origem nao autorizada a usar o assistente.';
    default:
      return raw.length > 0 ? raw : 'Falha ao enviar a mensagem.';
  }
}

function ChatError() {
  const error = useAISDKError();
  if (!error) {
    return null;
  }
  return (
    <p className={styles.error} role="alert">
      {errorMessage(error)}
    </p>
  );
}

function ThreadRenameForm({
  title,
  onDone,
}: {
  title: string;
  onDone: () => void;
}) {
  const aui = useAui();
  const [draft, setDraft] = useState(title);
  const inputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    inputRef.current?.focus();
    inputRef.current?.select();
  }, []);

  const commit = () => {
    const next = normalizeThreadTitle(draft, title);
    if (next !== null) {
      aui.threadListItem.rename(next);
    }
    onDone();
  };

  return (
    <form
      className={styles.renameForm}
      onSubmit={event => {
        event.preventDefault();
        commit();
      }}
    >
      <input
        ref={inputRef}
        className={styles.renameInput}
        value={draft}
        aria-label="Renomear conversa"
        onChange={event => setDraft(event.target.value)}
        onKeyDown={event => {
          if (event.key === 'Escape') {
            event.preventDefault();
            onDone();
          }
        }}
      />
      <button type="submit" className={styles.renameSave}>
        Salvar
      </button>
      <button type="button" className={styles.renameCancel} onClick={onDone}>
        Cancelar
      </button>
    </form>
  );
}

function ThreadListItem() {
  const [editing, setEditing] = useState(false);
  const aui = useAui();
  const title = useAuiState(state => state.threadListItem.title);
  const isMain = useAuiState(
    state => state.threads.mainThreadId === state.threadListItem.id,
  );

  if (editing) {
    return (
      <ThreadListItemPrimitive.Root className={styles.threadItem}>
        <ThreadRenameForm
          title={title ?? ''}
          onDone={() => setEditing(false)}
        />
      </ThreadListItemPrimitive.Root>
    );
  }

  return (
    <ThreadListItemPrimitive.Root className={styles.threadItem}>
      <ThreadListItemPrimitive.Trigger
        className={styles.threadTrigger}
        title={threadTitleFallback(title)}
        aria-current={isMain ? 'true' : undefined}
      >
        <ThreadListItemPrimitive.Title fallback={THREAD_TITLE_FALLBACK} />
      </ThreadListItemPrimitive.Trigger>
      <ThreadListItemMorePrimitive.Root sharedFocusGroup>
        <ThreadListItemMorePrimitive.Trigger
          className={styles.threadMore}
          aria-label="Opcoes da conversa"
        >
          &#8943;
        </ThreadListItemMorePrimitive.Trigger>
        <ThreadListItemMorePrimitive.Content className={styles.threadMenu}>
          <ThreadListItemMorePrimitive.Item
            className={styles.threadMenuItem}
            onSelect={() => setEditing(true)}
          >
            Renomear
          </ThreadListItemMorePrimitive.Item>
          <ThreadListItemMorePrimitive.Separator
            className={styles.threadMenuSeparator}
          />
          <ThreadListItemMorePrimitive.Item
            className={`${styles.threadMenuItem} ${styles.threadMenuItemDanger}`}
            onSelect={() => {
              aui.threadListItem.delete();
            }}
          >
            Excluir
          </ThreadListItemMorePrimitive.Item>
        </ThreadListItemMorePrimitive.Content>
      </ThreadListItemMorePrimitive.Root>
    </ThreadListItemPrimitive.Root>
  );
}

function ThreadList() {
  return (
    <nav className={styles.threadList} aria-label="Conversas">
      <ThreadListPrimitive.Root className={styles.threadListInner}>
        <ThreadListPrimitive.New className={styles.newThread}>
          Nova conversa
        </ThreadListPrimitive.New>
        <ThreadListPrimitive.Items>
          {() => <ThreadListItem />}
        </ThreadListPrimitive.Items>
      </ThreadListPrimitive.Root>
    </nav>
  );
}

export default function Chat() {
  const tokenRef = useRef('');
  const widgetRef = useRef<string | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const runtimeRef = useRef<ReturnType<typeof useChatRuntime> | null>(null);

  const renderWidget = useCallback(() => {
    if (widgetRef.current) {
      return;
    }
    if (!containerRef.current || !window.turnstile || SITE_KEY.length === 0) {
      return;
    }
    widgetRef.current = window.turnstile.render(containerRef.current, {
      sitekey: SITE_KEY,
      callback: token => {
        tokenRef.current = token;
      },
      'expired-callback': () => {
        tokenRef.current = '';
      },
    });
  }, []);

  const resetWidget = useCallback(() => {
    tokenRef.current = '';
    if (widgetRef.current && window.turnstile) {
      window.turnstile.reset(widgetRef.current);
    }
  }, []);

  const initializeThread = useCallback(async (threadId: string) => {
    const item = runtimeRef.current?.threads.getItemById(threadId);
    if (!item) {
      return;
    }
    try {
      await item.initialize();
    } catch {
      // Thread bookkeeping must not block the chat request.
    }
  }, []);

  const transport = useMemo(
    () =>
      new TurnstileChatTransport({
        api: `${API_URL}/chat`,
        getToken: () => tokenRef.current,
        onRequestSettled: resetWidget,
        initializeThread,
      }),
    [resetWidget, initializeThread],
  );

  const runtime = useChatRuntime({ transport });

  useEffect(() => {
    runtimeRef.current = runtime;
  }, [runtime]);

  useEffect(() => {
    if (window.turnstile) {
      renderWidget();
    }
    return () => {
      if (widgetRef.current) {
        window.turnstile?.remove(widgetRef.current);
        widgetRef.current = null;
      }
    };
  }, [renderWidget]);

  return (
    <div className={styles.chat}>
      <AssistantRuntimeProvider runtime={runtime}>
        <div className={styles.layout}>
          <ThreadList />
          <div className={styles.main}>
            <ThreadPrimitive.Root className={styles.thread}>
              <ThreadPrimitive.Viewport className={styles.messages}>
                <AuiIf condition={(state) => state.thread.isEmpty}>
                  <div className={styles.suggestions}>
                    {SUGGESTIONS.map((suggestion) => (
                      <ThreadPrimitive.Suggestion
                        key={suggestion}
                        prompt={suggestion}
                        send
                        className={styles.suggestion}
                      >
                        {suggestion}
                      </ThreadPrimitive.Suggestion>
                    ))}
                  </div>
                </AuiIf>
                <ThreadPrimitive.Messages>
                  {({ message }) => (
                    <MessagePrimitive.Root
                      className={
                        message.role === 'user'
                          ? `${styles.message} ${styles.user}`
                          : `${styles.message} ${styles.assistant}`
                      }
                    >
                      {message.role === 'assistant' ? (
                        <MessagePrimitive.Parts components={ASSISTANT_PARTS} />
                      ) : (
                        <MessagePrimitive.Parts />
                      )}
                    </MessagePrimitive.Root>
                  )}
                </ThreadPrimitive.Messages>
              </ThreadPrimitive.Viewport>
              <ChatError />
              <ComposerPrimitive.Root className={styles.form}>
                <label className={styles.label} htmlFor="chat-input">
                  Mensagem
                </label>
                <ComposerPrimitive.Input
                  id="chat-input"
                  className={styles.input}
                  placeholder="Pergunte sobre o Paulo..."
                />
                <ComposerPrimitive.Send className={styles.send}>Enviar</ComposerPrimitive.Send>
              </ComposerPrimitive.Root>
            </ThreadPrimitive.Root>
          </div>
        </div>
      </AssistantRuntimeProvider>
      <div ref={containerRef} className={styles.turnstile} />
      <Script
        src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
        strategy="afterInteractive"
        onLoad={renderWidget}
      />
    </div>
  );
}
