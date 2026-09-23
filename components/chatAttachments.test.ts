import { describe, expect, it } from 'vitest';
import type { AttachmentAdapter, PendingAttachment, ThreadUserMessagePart } from '@assistant-ui/react';
import type { UIMessage } from 'ai';
import {
  createWorkerAttachmentAdapter,
  extractAttachmentText,
  formatAttachmentText,
  isSupportedAttachment,
  looksBinary,
  MAX_ATTACHMENT_CHARS,
  OVERSIZED_ATTACHMENT_MESSAGE,
  previewAttachmentText,
  SUPPORTED_ATTACHMENT_ACCEPT,
  UNSUPPORTED_ATTACHMENT_MESSAGE,
} from './chatAttachments';
import { toWorkerMessages } from './chatTransport';

function file(name: string, type: string, content = 'conteudo'): File {
  return new File([content], name, { type });
}

async function addPending(adapter: AttachmentAdapter, input: File): Promise<PendingAttachment> {
  const result = await adapter.add({ file: input });
  if (!('status' in result)) {
    throw new Error('adapter.add retornou um generator inesperado');
  }
  return result;
}

describe('isSupportedAttachment', () => {
  it('aceita arquivos de texto por MIME', () => {
    expect(isSupportedAttachment({ name: 'notas.txt', type: 'text/plain' })).toBe(true);
    expect(isSupportedAttachment({ name: 'dados.json', type: 'application/json' })).toBe(true);
  });

  it('aceita arquivos de texto por extensao quando o MIME vem vazio', () => {
    expect(isSupportedAttachment({ name: 'README.md', type: '' })).toBe(true);
    expect(isSupportedAttachment({ name: 'script.py', type: '' })).toBe(true);
  });

  it('recusa imagens e binarios', () => {
    expect(isSupportedAttachment({ name: 'foto.png', type: 'image/png' })).toBe(false);
    expect(isSupportedAttachment({ name: 'doc.pdf', type: 'application/pdf' })).toBe(false);
    expect(isSupportedAttachment({ name: 'bin', type: 'application/octet-stream' })).toBe(false);
  });

  it('expoe um accept restrito para o seletor de arquivos', () => {
    expect(SUPPORTED_ATTACHMENT_ACCEPT).toContain('text/*');
    expect(SUPPORTED_ATTACHMENT_ACCEPT).not.toContain('image/*');
  });
});

describe('looksBinary', () => {
  it('detecta NUL e excesso de caracteres de substituicao', () => {
    expect(looksBinary('texto normal')).toBe(false);
    expect(looksBinary('bin\u0000ario')).toBe(true);
    expect(looksBinary('\uFFFD\uFFFD\uFFFD\uFFFD')).toBe(true);
  });
});

describe('extractAttachmentText', () => {
  it('concatena apenas os parts de texto', () => {
    const content: ThreadUserMessagePart[] = [
      { type: 'text', text: 'ola ' },
      { type: 'file', filename: 'a.bin', data: 'zzz', mimeType: 'application/octet-stream' },
      { type: 'text', text: 'mundo' },
    ];
    expect(extractAttachmentText(content)).toBe('ola mundo');
  });

  it('retorna vazio sem conteudo', () => {
    expect(extractAttachmentText(undefined)).toBe('');
  });
});

describe('formatAttachmentText', () => {
  it('identifica a origem do trecho anexado', () => {
    expect(formatAttachmentText('notas.txt', 'linha')).toBe('\n[Anexo: notas.txt]\nlinha');
  });
});

describe('previewAttachmentText', () => {
  it('resume o conteudo longo', () => {
    const content: ThreadUserMessagePart[] = [{ type: 'text', text: 'a'.repeat(200) }];
    const preview = previewAttachmentText(content, 10);
    expect(preview).toBe('aaaaaaaaaa...');
  });

  it('mantem o conteudo curto intacto', () => {
    const content: ThreadUserMessagePart[] = [{ type: 'text', text: '  curto  ' }];
    expect(previewAttachmentText(content)).toBe('curto');
  });
});

describe('createWorkerAttachmentAdapter', () => {
  it('aceita texto, guarda o conteudo para preview e incorpora como texto no envio', async () => {
    const adapter = createWorkerAttachmentAdapter();
    const pending = await addPending(adapter, file('notas.txt', 'text/plain', 'conteudo'));

    expect(pending.status).toEqual({ type: 'requires-action', reason: 'composer-send' });
    expect(pending.content).toEqual([{ type: 'text', text: 'conteudo' }]);

    const complete = await adapter.send(pending);
    expect(complete.status).toEqual({ type: 'complete' });
    expect(complete.content).toEqual([{ type: 'text', text: '\n[Anexo: notas.txt]\nconteudo' }]);
    expect(complete.content.every((part) => part.type === 'text')).toBe(true);
  });

  it('recusa anexos nao suportados com mensagem explicita', async () => {
    const adapter = createWorkerAttachmentAdapter();
    await expect(adapter.add({ file: file('foto.png', 'image/png') })).rejects.toThrow(
      UNSUPPORTED_ATTACHMENT_MESSAGE,
    );
  });

  it('recusa arquivos acima do limite do Worker', async () => {
    const adapter = createWorkerAttachmentAdapter();
    const oversized = file('grande.txt', 'text/plain', 'a'.repeat(MAX_ATTACHMENT_CHARS + 1));
    await expect(adapter.add({ file: oversized })).rejects.toThrow(OVERSIZED_ATTACHMENT_MESSAGE);
  });

  it('recusa binario disfarcado de texto', async () => {
    const adapter = createWorkerAttachmentAdapter();
    const binary = file('video.ts', 'video/mp2t', 'bin\u0000ario');
    await expect(adapter.add({ file: binary })).rejects.toThrow(UNSUPPORTED_ATTACHMENT_MESSAGE);
  });

  it('nunca produz parts que nao sejam texto', async () => {
    const adapter = createWorkerAttachmentAdapter();
    const pending = await addPending(adapter, file('dados.csv', 'text/csv', 'a,b\n1,2'));
    const complete = await adapter.send(pending);
    expect(complete.content.map((part) => part.type)).toEqual(['text']);
  });

  it('entrega o texto do anexo ao contrato do Worker, separado da mensagem digitada', async () => {
    const adapter = createWorkerAttachmentAdapter();
    const pending = await addPending(adapter, file('notas.txt', 'text/plain', 'segredo'));
    const complete = await adapter.send(pending);
    const userMessage = {
      id: 'u1',
      role: 'user',
      parts: [{ type: 'text', text: 'resuma' }, ...complete.content],
    } as UIMessage;

    expect(toWorkerMessages([userMessage])).toEqual([
      { role: 'user', content: 'resuma\n[Anexo: notas.txt]\nsegredo' },
    ]);
  });
});
