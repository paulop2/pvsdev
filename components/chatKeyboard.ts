export const COMPOSER_SHORTCUT_HINT =
  'Enter envia a mensagem, Shift+Enter adiciona uma nova linha e Escape interrompe a geracao.';

export type ComposerKeyAction = 'send' | 'newline' | 'stop' | 'none';

export interface ComposerKeyInput {
  key: string;
  shiftKey: boolean;
  isRunning: boolean;
  isComposing?: boolean;
}

/**
 * Decide o que fazer quando uma tecla e pressionada no composer do chat.
 *
 * O componente de input do assistant-ui fica com `submitMode="none"` para que
 * os atalhos fiquem explicitos e testaveis:
 *
 * - Enter (sem Shift) envia, exceto durante a geracao;
 * - Shift+Enter insere nova linha (tratada pelo proprio textarea);
 * - Escape interrompe a geracao em andamento;
 * - composicao de IME nunca dispara envio.
 */
export function resolveComposerKey(input: ComposerKeyInput): ComposerKeyAction {
  if (input.isComposing) {
    return 'none';
  }
  if (input.key === 'Escape') {
    return input.isRunning ? 'stop' : 'none';
  }
  if (input.key !== 'Enter') {
    return 'none';
  }
  if (input.shiftKey) {
    return 'newline';
  }
  return input.isRunning ? 'none' : 'send';
}
