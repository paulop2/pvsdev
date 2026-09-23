import remarkGfm from 'remark-gfm';
import rehypeHighlight from 'rehype-highlight';

/**
 * Configuracao compartilhada de renderizacao de markdown do chat.
 *
 * - `remarkGfm`: tabelas, listas de tarefas, strikethrough e autolinks (GFM).
 * - `rehypeHighlight`: realce de sintaxe nos blocos de codigo.
 *
 * HTML cru permanece desabilitado: nenhum plugin `rehype-raw` e registrado, de
 * modo que tags embutidas na resposta nao viram elementos do DOM.
 */
export const markdownRemarkPlugins = [remarkGfm];
export const markdownRehypePlugins = [rehypeHighlight];
