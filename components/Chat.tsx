'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { KeyboardEvent as ReactKeyboardEvent } from 'react';
import Script from 'next/script';
import {
  ActionBarPrimitive,
  AssistantRuntimeProvider,
  AttachmentPrimitive,
  AuiIf,
  BranchPickerPrimitive,
  ComposerPrimitive,
  MessagePrimitive,
  ThreadListItemMorePrimitive,
  ThreadListItemPrimitive,
  ThreadListPrimitive,
  ThreadPrimitive,
  useAui,
  useAuiEvent,
  useAuiState,
} from '@assistant-ui/react';
import { useAISDKError, useChatRuntime } from '@assistant-ui/ai-sdk';
import { MarkdownText } from '@/components/MarkdownText';
import { TurnstileChatTransport } from '@/components/chatTransport';
import {
  createWorkerAttachmentAdapter,
  previewAttachmentText,
} from '@/components/chatAttachments';
import {
  COMPOSER_SHORTCUT_HINT,
  resolveComposerKey,
} from '@/components/chatKeyboard';
import { resolveMessageKind } from '@/components/chatMessages';
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

function attachmentErrorMessage(
  reason: string,
  message: string,
  contentType?: string,
): string {
  if (reason === 'not-accepted') {
    const label =
      contentType && contentType.length > 0 ? contentType : 'tipo desconhecido';
    return `Anexo recusado (${label}): o assistente so processa arquivos de texto.`;
  }
  return message.length > 0 ? message : 'Nao foi possivel anexar o arquivo.';
}

function AttachmentError() {
  const [message, setMessage] = useState('');
  useAuiEvent({ scope: '*', event: 'composer.attachmentAddError' }, payload => {
    setMessage(
      attachmentErrorMessage(
        payload.reason,
        payload.message,
        payload.contentType,
      ),
    );
  });
  useAuiEvent({ scope: '*', event: 'composer.attachmentAdd' }, () => {
    setMessage('');
  });
  useAuiEvent({ scope: '*', event: 'composer.send' }, () => {
    setMessage('');
  });
  if (message.length === 0) {
    return null;
  }
  return (
    <p className={styles.attachmentError} role="alert">
      {message}
    </p>
  );
}

function BranchPicker() {
  return (
    <BranchPickerPrimitive.Root
      hideWhenSingleBranch
      className={styles.branchPicker}
    >
      <BranchPickerPrimitive.Previous
        className={styles.branchButton}
        aria-label="Ramo anterior"
      >
        &lsaquo;
      </BranchPickerPrimitive.Previous>
      <span className={styles.branchPosition}>
        <BranchPickerPrimitive.Number /> de <BranchPickerPrimitive.Count />
      </span>
      <BranchPickerPrimitive.Next
        className={styles.branchButton}
        aria-label="Proximo ramo"
      >
        &rsaquo;
      </BranchPickerPrimitive.Next>
    </BranchPickerPrimitive.Root>
  );
}

function UserMessage() {
  return (
    <MessagePrimitive.Root className={`${styles.message} ${styles.user}`}>
      <MessagePrimitive.Parts />
      <div className={styles.messageFooter}>
        <ActionBarPrimitive.Root className={styles.actions} hideWhenRunning>
          <ActionBarPrimitive.Edit className={styles.action}>
            Editar
          </ActionBarPrimitive.Edit>
        </ActionBarPrimitive.Root>
        <BranchPicker />
      </div>
    </MessagePrimitive.Root>
  );
}

function AssistantMessage() {
  return (
    <MessagePrimitive.Root className={`${styles.message} ${styles.assistant}`}>
      <MessagePrimitive.Parts components={ASSISTANT_PARTS} />
      <div className={styles.messageFooter}>
        <ActionBarPrimitive.Root className={styles.actions} hideWhenRunning>
          <ActionBarPrimitive.Reload className={styles.action}>
            Regenerar
          </ActionBarPrimitive.Reload>
        </ActionBarPrimitive.Root>
        <BranchPicker />
      </div>
    </MessagePrimitive.Root>
  );
}

function EditComposer() {
  return (
    <MessagePrimitive.Root
      className={`${styles.message} ${styles.editMessage}`}
    >
      <ComposerPrimitive.Root className={styles.editForm}>
        <label className={styles.label} htmlFor="chat-edit-input">
          Editar mensagem
        </label>
        <ComposerPrimitive.Input
          id="chat-edit-input"
          className={styles.input}
          aria-label="Editar mensagem"
        />
        <div className={styles.editActions}>
          <ComposerPrimitive.Cancel className={styles.cancel}>
            Cancelar
          </ComposerPrimitive.Cancel>
          <ComposerPrimitive.Send className={styles.send}>
            Salvar
          </ComposerPrimitive.Send>
        </div>
      </ComposerPrimitive.Root>
    </MessagePrimitive.Root>
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

function ChatThread() {
  const aui = useAui();
  const composerInputRef = useRef<HTMLTextAreaElement | null>(null);
  const isRunning = useAuiState(state => state.thread.isRunning);

  const handleComposerKeyDown = (
    event: ReactKeyboardEvent<HTMLTextAreaElement>,
  ) => {
    const action = resolveComposerKey({
      key: event.key,
      shiftKey: event.shiftKey,
      isRunning: aui.thread.getState().isRunning,
      isComposing: event.nativeEvent.isComposing,
    });
    if (action === 'send') {
      if (!aui.composer.getState().canSend) {
        return;
      }
      event.preventDefault();
      aui.composer.send();
      return;
    }
    if (action === 'stop') {
      if (!aui.composer.getState().canCancel) {
        return;
      }
      event.preventDefault();
      aui.composer.cancel();
      composerInputRef.current?.focus();
    }
  };

  return (
    <div className={styles.main}>
      <ThreadPrimitive.Root className={styles.thread}>
        <ThreadPrimitive.Viewport
          className={styles.messages}
          role="log"
          aria-live="polite"
          aria-relevant="additions text"
          aria-busy={isRunning}
          aria-label="Mensagens da conversa"
        >
          <AuiIf condition={state => state.thread.isEmpty}>
            <div className={styles.suggestions}>
              {SUGGESTIONS.map(suggestion => (
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
            {({ message }) => {
              switch (resolveMessageKind(message)) {
                case 'edit':
                  return <EditComposer />;
                case 'user':
                  return <UserMessage />;
                default:
                  return <AssistantMessage />;
              }
            }}
          </ThreadPrimitive.Messages>
        </ThreadPrimitive.Viewport>
        <ChatError />
        <AttachmentError />
        <ComposerPrimitive.Root className={styles.form}>
          <div className={styles.attachments}>
            <ComposerPrimitive.Attachments>
              {({ attachment }) => (
                <AttachmentPrimitive.Root className={styles.attachment}>
                  <div className={styles.attachmentHeader}>
                    <span className={styles.attachmentName}>
                      <AttachmentPrimitive.Name />
                    </span>
                    <AttachmentPrimitive.Remove
                      className={styles.attachmentRemove}
                      aria-label={`Remover anexo ${attachment.name}`}
                    >
                      Remover
                    </AttachmentPrimitive.Remove>
                  </div>
                  {attachment.status.type === 'incomplete' ? (
                    <p className={styles.attachmentError}>
                      {attachment.status.message}
                    </p>
                  ) : (
                    <pre className={styles.attachmentPreview}>
                      {previewAttachmentText(attachment.content)}
                    </pre>
                  )}
                </AttachmentPrimitive.Root>
              )}
            </ComposerPrimitive.Attachments>
          </div>
          <label className={styles.label} htmlFor="chat-input">
            Mensagem
          </label>
          <p id="chat-shortcuts-hint" className={styles.srOnly}>
            {COMPOSER_SHORTCUT_HINT}
          </p>
          <div className={styles.composerRow}>
            <ComposerPrimitive.AddAttachment
              className={styles.attach}
              aria-label="Anexar arquivo de texto"
            >
              Anexar
            </ComposerPrimitive.AddAttachment>
            <ComposerPrimitive.Input
              id="chat-input"
              ref={composerInputRef}
              className={styles.input}
              placeholder="Pergunte sobre o Paulo..."
              submitMode="none"
              aria-describedby="chat-shortcuts-hint"
              onKeyDown={handleComposerKeyDown}
            />
            <AuiIf condition={state => state.thread.isRunning}>
              <ComposerPrimitive.Cancel
                className={styles.stop}
                aria-label="Parar geracao"
                onClick={() => composerInputRef.current?.focus()}
              >
                Parar
              </ComposerPrimitive.Cancel>
            </AuiIf>
            <AuiIf condition={state => !state.thread.isRunning}>
              <ComposerPrimitive.Send
                className={styles.send}
                aria-label="Enviar mensagem"
              >
                Enviar
              </ComposerPrimitive.Send>
            </AuiIf>
          </div>
        </ComposerPrimitive.Root>
      </ThreadPrimitive.Root>
    </div>
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

  const attachmentAdapter = useMemo(() => createWorkerAttachmentAdapter(), []);

  const runtime = useChatRuntime({
    transport,
    adapters: { attachments: attachmentAdapter },
  });

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
          <ChatThread />
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
