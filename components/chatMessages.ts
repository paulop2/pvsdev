export type ChatMessageKind = 'edit' | 'user' | 'assistant';

export interface ChatMessageKindInput {
  role: string;
  composer: { isEditing: boolean };
}

/**
 * Decide qual componente renderizar para uma mensagem da thread.
 *
 * A edicao tem precedencia sobre o papel: enquanto o composer da mensagem
 * esta em modo de edicao, ela e renderizada como composer de edicao,
 * independentemente do papel original. Mensagens de sistema sao tratadas
 * como do assistente.
 */
export function resolveMessageKind(message: ChatMessageKindInput): ChatMessageKind {
  if (message.composer.isEditing) {
    return 'edit';
  }
  return message.role === 'user' ? 'user' : 'assistant';
}
