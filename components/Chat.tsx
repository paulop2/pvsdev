'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Script from 'next/script';
import {
  AssistantRuntimeProvider,
  AttachmentPrimitive,
  AuiIf,
  ComposerPrimitive,
  MessagePrimitive,
  ThreadPrimitive,
  useAuiEvent,
} from '@assistant-ui/react';
import { useAISDKError, useChatRuntime } from '@assistant-ui/ai-sdk';
import { TurnstileChatTransport } from '@/components/chatTransport';
import {
  createWorkerAttachmentAdapter,
  previewAttachmentText,
} from '@/components/chatAttachments';
import styles from '@/styles/chat.module.css';

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

function attachmentErrorMessage(reason: string, message: string, contentType?: string): string {
  if (reason === 'not-accepted') {
    const label = contentType && contentType.length > 0 ? contentType : 'tipo desconhecido';
    return `Anexo recusado (${label}): o assistente so processa arquivos de texto.`;
  }
  return message.length > 0 ? message : 'Nao foi possivel anexar o arquivo.';
}

function AttachmentError() {
  const [message, setMessage] = useState('');
  useAuiEvent({ scope: '*', event: 'composer.attachmentAddError' }, (payload) => {
    setMessage(attachmentErrorMessage(payload.reason, payload.message, payload.contentType));
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

export default function Chat() {
  const tokenRef = useRef('');
  const widgetRef = useRef<string | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);

  const renderWidget = useCallback(() => {
    if (widgetRef.current) {
      return;
    }
    if (!containerRef.current || !window.turnstile || SITE_KEY.length === 0) {
      return;
    }
    widgetRef.current = window.turnstile.render(containerRef.current, {
      sitekey: SITE_KEY,
      callback: (token) => {
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

  const transport = useMemo(
    () =>
      new TurnstileChatTransport({
        api: `${API_URL}/chat`,
        getToken: () => tokenRef.current,
        onRequestSettled: resetWidget,
      }),
    [resetWidget],
  );

  const attachmentAdapter = useMemo(() => createWorkerAttachmentAdapter(), []);

  const runtime = useChatRuntime({
    transport,
    adapters: { attachments: attachmentAdapter },
  });

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
                  <MessagePrimitive.Parts />
                </MessagePrimitive.Root>
              )}
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
                      <p className={styles.attachmentError}>{attachment.status.message}</p>
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
            <div className={styles.composerRow}>
              <ComposerPrimitive.AddAttachment
                className={styles.attach}
                aria-label="Anexar arquivo de texto"
              >
                Anexar
              </ComposerPrimitive.AddAttachment>
              <ComposerPrimitive.Input
                id="chat-input"
                className={styles.input}
                placeholder="Pergunte sobre o Paulo..."
              />
              <ComposerPrimitive.Send className={styles.send}>Enviar</ComposerPrimitive.Send>
            </div>
          </ComposerPrimitive.Root>
        </ThreadPrimitive.Root>
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
