import type {
  AttachmentAdapter,
  CompleteAttachment,
  PendingAttachment,
  ThreadUserMessagePart,
} from '@assistant-ui/react';

/**
 * O Worker do chat v1 so aceita texto no contrato `{ role, content: string }`
 * (ver `ai/src/validation.ts`): nao existe backend de vision/multimodal.
 * Anexos so podem ser incorporados como texto. Qualquer outro formato e
 * recusado com mensagem explicita, nunca enviado nem ignorado em silencio.
 */

const SUPPORTED_MIME_TYPES = [
  'text/*',
  'application/json',
  'application/xml',
  'application/javascript',
  'application/typescript',
  'application/x-yaml',
] as const;

const SUPPORTED_EXTENSIONS = [
  '.txt',
  '.text',
  '.md',
  '.markdown',
  '.csv',
  '.tsv',
  '.json',
  '.jsonl',
  '.xml',
  '.yml',
  '.yaml',
  '.toml',
  '.ini',
  '.log',
  '.html',
  '.htm',
  '.css',
  '.js',
  '.jsx',
  '.mjs',
  '.cjs',
  '.ts',
  '.tsx',
  '.py',
  '.rb',
  '.go',
  '.rs',
  '.java',
  '.kt',
  '.c',
  '.h',
  '.cpp',
  '.hpp',
  '.cs',
  '.sh',
  '.bash',
  '.ps1',
  '.sql',
  '.graphql',
] as const;

export const SUPPORTED_ATTACHMENT_ACCEPT = [...SUPPORTED_MIME_TYPES, ...SUPPORTED_EXTENSIONS].join(
  ',',
);

/** Alinhado ao `maxCharsPerMessage` do Worker (4000), com folga para o texto digitado. */
export const MAX_ATTACHMENT_CHARS = 3000;

export const UNSUPPORTED_ATTACHMENT_MESSAGE =
  'Anexo recusado: o assistente so processa arquivos de texto. Imagens e binarios nao sao suportados.';

export const OVERSIZED_ATTACHMENT_MESSAGE = `Anexo recusado: o arquivo excede ${MAX_ATTACHMENT_CHARS} caracteres. Anexe um trecho menor.`;

export function isSupportedAttachment(file: { name: string; type: string }): boolean {
  const mime = file.type.split(';', 1)[0].trim().toLowerCase();
  const name = file.name.toLowerCase();
  const mimeSupported = SUPPORTED_MIME_TYPES.some((allowed) =>
    allowed.endsWith('/*') ? mime.startsWith(`${allowed.slice(0, -1)}`) : mime === allowed,
  );
  return mimeSupported || SUPPORTED_EXTENSIONS.some((extension) => name.endsWith(extension));
}

/** Um arquivo com extensao de texto pode ainda ser binario (ex.: video `.ts`). */
export function looksBinary(text: string): boolean {
  if (text.includes('\u0000')) {
    return true;
  }
  let replacement = 0;
  for (const char of text) {
    if (char === '\uFFFD') {
      replacement += 1;
    }
  }
  return text.length > 0 && replacement / text.length > 0.1;
}

export function extractAttachmentText(
  content: readonly ThreadUserMessagePart[] | undefined,
): string {
  if (!content) {
    return '';
  }
  return content
    .filter((part): part is Extract<ThreadUserMessagePart, { type: 'text' }> => part.type === 'text')
    .map((part) => part.text)
    .join('');
}

export function formatAttachmentText(name: string, text: string): string {
  return `\n[Anexo: ${name}]\n${text}`;
}

export function previewAttachmentText(
  content: readonly ThreadUserMessagePart[] | undefined,
  maxLength = 160,
): string {
  const text = extractAttachmentText(content).trim();
  if (text.length <= maxLength) {
    return text;
  }
  return `${text.slice(0, maxLength)}...`;
}

async function readFileText(file: File): Promise<string> {
  if (typeof file.text === 'function') {
    return file.text();
  }
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result ?? ''));
    reader.onerror = () => reject(reader.error ?? new Error('Falha ao ler o arquivo.'));
    reader.readAsText(file);
  });
}

function generateAttachmentId(): string {
  const cryptoObj = globalThis.crypto;
  if (cryptoObj && typeof cryptoObj.randomUUID === 'function') {
    return cryptoObj.randomUUID();
  }
  return `attachment-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

export function createWorkerAttachmentAdapter(): AttachmentAdapter {
  return {
    accept: SUPPORTED_ATTACHMENT_ACCEPT,
    async add({ file }): Promise<PendingAttachment> {
      if (!isSupportedAttachment(file)) {
        throw new Error(UNSUPPORTED_ATTACHMENT_MESSAGE);
      }
      const text = await readFileText(file);
      if (looksBinary(text)) {
        throw new Error(UNSUPPORTED_ATTACHMENT_MESSAGE);
      }
      if (text.length > MAX_ATTACHMENT_CHARS) {
        throw new Error(OVERSIZED_ATTACHMENT_MESSAGE);
      }
      return {
        id: generateAttachmentId(),
        type: 'document',
        name: file.name,
        contentType: file.type || 'text/plain',
        file,
        content: [{ type: 'text', text }],
        status: { type: 'requires-action', reason: 'composer-send' },
      };
    },
    async send(attachment): Promise<CompleteAttachment> {
      const stored = extractAttachmentText(attachment.content);
      const text = stored.length > 0 ? stored : await readFileText(attachment.file);
      return {
        ...attachment,
        status: { type: 'complete' },
        content: [{ type: 'text', text: formatAttachmentText(attachment.name, text) }],
      };
    },
    async remove() {},
  };
}
