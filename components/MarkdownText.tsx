'use client';

import { useCallback, useState } from 'react';
import {
  MarkdownTextPrimitive,
  type CodeHeaderProps,
  type MarkdownTextPrimitiveProps,
} from '@assistant-ui/react-markdown';
import {
  markdownRehypePlugins,
  markdownRemarkPlugins,
} from '@/components/markdown';
import styles from '@/styles/chat.module.css';

type MarkdownComponents = NonNullable<MarkdownTextPrimitiveProps['components']>;

function CodeHeader({ language, code }: CodeHeaderProps) {
  const [copied, setCopied] = useState(false);

  const copy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard indisponivel (contexto inseguro ou permissao negada).
    }
  }, [code]);

  return (
    <div className={styles.codeHeader}>
      <span className={styles.codeLanguage}>
        {language && language.length > 0 ? language : 'texto'}
      </span>
      <button
        type="button"
        className={styles.codeCopy}
        onClick={() => void copy()}
        aria-label={copied ? 'Codigo copiado' : 'Copiar codigo'}
      >
        {copied ? 'Copiado' : 'Copiar'}
      </button>
    </div>
  );
}

const markdownComponents: MarkdownComponents = {
  CodeHeader,
  a: ({ node: _node, ...props }) => (
    <a {...props} target="_blank" rel="noreferrer noopener" />
  ),
};

/**
 * Renderer de markdown usado nas mensagens do assistente dentro do
 * `MessagePrimitive.Parts`. Consome o texto progressivo do part atual e
 * delega a renderizacao de GFM/codigo para os plugins compartilhados.
 */
export function MarkdownText() {
  return (
    <MarkdownTextPrimitive
      className={styles.markdown}
      remarkPlugins={markdownRemarkPlugins}
      rehypePlugins={markdownRehypePlugins}
      components={markdownComponents}
    />
  );
}
