'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import Script from 'next/script';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { parseSseBuffer } from '@/components/chatStream';
import styles from '@/styles/chat.module.css';

interface Message {
  role: 'user' | 'assistant';
  content: string;
}

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

export default function Chat() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState('');
  const [status, setStatus] = useState<'idle' | 'streaming' | 'error' | 'capped'>('idle');
  const [error, setError] = useState<string | null>(null);
  const tokenRef = useRef<string>('');
  const widgetRef = useRef<string | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const bottomRef = useRef<HTMLDivElement | null>(null);

  const renderWidget = useCallback(() => {
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

  useEffect(() => {
    if (window.turnstile) {
      renderWidget();
    }
  }, [renderWidget]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  async function send(text: string): Promise<void> {
    const trimmed = text.trim();
    if (trimmed.length === 0 || status === 'streaming') {
      return;
    }
    setError(null);
    setStatus('streaming');
    const history: Message[] = [...messages, { role: 'user', content: trimmed }];
    setMessages([...history, { role: 'assistant', content: '' }]);
    setInput('');
    try {
      const response = await fetch(`${API_URL}/chat`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ messages: history.slice(-12), turnstileToken: tokenRef.current }),
      });
      if (!response.ok) {
        const payload = (await response.json().catch(() => ({}))) as { code?: string };
        setStatus(payload.code === 'daily_cap_exceeded' ? 'capped' : 'error');
        setError(payload.code ?? `HTTP ${response.status}`);
        setMessages(history);
        return;
      }
      if (!response.body) {
        throw new Error('missing body');
      }
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      let assistant = '';
      for (;;) {
        const { done, value } = await reader.read();
        if (done) {
          break;
        }
        buffer += decoder.decode(value, { stream: true });
        const parsed = parseSseBuffer(buffer);
        buffer = parsed.rest;
        for (const streamEvent of parsed.events) {
          if (streamEvent.event === 'token') {
            const data = JSON.parse(streamEvent.data) as { delta: string };
            assistant += data.delta;
            setMessages([...history, { role: 'assistant', content: assistant }]);
          } else if (streamEvent.event === 'error') {
            setStatus('error');
            setError('stream interrompido');
          }
        }
      }
      setStatus((current) => (current === 'streaming' ? 'idle' : current));
    } catch {
      setStatus('error');
      setError('falha de rede');
    } finally {
      tokenRef.current = '';
      if (widgetRef.current && window.turnstile) {
        window.turnstile.reset(widgetRef.current);
      }
    }
  }

  return (
    <div className={styles.chat}>
      <div className={styles.messages} aria-live="polite">
        {messages.length === 0 && (
          <div className={styles.suggestions}>
            {SUGGESTIONS.map((suggestion) => (
              <button
                key={suggestion}
                type="button"
                className={styles.suggestion}
                onClick={() => void send(suggestion)}
              >
                {suggestion}
              </button>
            ))}
          </div>
        )}
        {messages.map((message, index) => (
          <div
            key={index}
            className={message.role === 'user' ? styles.user : styles.assistant}
          >
            {message.role === 'assistant' ? (
              <ReactMarkdown remarkPlugins={[remarkGfm]}>
                {message.content.length > 0 ? message.content : '...'}
              </ReactMarkdown>
            ) : (
              <p>{message.content}</p>
            )}
          </div>
        ))}
        <div ref={bottomRef} />
      </div>
      {error && (
        <p className={styles.error} role="alert">
          {error}
        </p>
      )}
      <form
        className={styles.form}
        onSubmit={(event) => {
          event.preventDefault();
          void send(input);
        }}
      >
        <label className={styles.label} htmlFor="chat-input">
          Mensagem
        </label>
        <input
          id="chat-input"
          className={styles.input}
          value={input}
          onChange={(event) => setInput(event.target.value)}
          placeholder="Pergunte sobre o Paulo..."
          disabled={status === 'streaming'}
        />
        <button
          type="submit"
          className={styles.send}
          disabled={status === 'streaming' || input.trim().length === 0}
        >
          Enviar
        </button>
      </form>
      <div ref={containerRef} className={styles.turnstile} />
      <Script
        src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
        strategy="afterInteractive"
        onLoad={renderWidget}
      />
    </div>
  );
}
