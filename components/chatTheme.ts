export interface Rgb {
  r: number;
  g: number;
  b: number;
}

export interface ContrastPair {
  name: string;
  foreground: string;
  background: string;
  largeText?: boolean;
}

export function parseHexColor(value: string): Rgb {
  const hex = value.trim().replace(/^#/, '');
  const expanded =
    hex.length === 3
      ? hex
          .split('')
          .map(part => part + part)
          .join('')
      : hex;
  if (!/^[0-9a-fA-F]{6}$/.test(expanded)) {
    throw new Error(`Cor hexadecimal invalida: ${value}`);
  }
  return {
    r: Number.parseInt(expanded.slice(0, 2), 16),
    g: Number.parseInt(expanded.slice(2, 4), 16),
    b: Number.parseInt(expanded.slice(4, 6), 16),
  };
}

export function relativeLuminance(color: Rgb): number {
  const channel = (value: number): number => {
    const ratio = value / 255;
    return ratio <= 0.03928 ? ratio / 12.92 : ((ratio + 0.055) / 1.055) ** 2.4;
  };
  return (
    0.2126 * channel(color.r) +
    0.7152 * channel(color.g) +
    0.0722 * channel(color.b)
  );
}

export function contrastRatio(foreground: string, background: string): number {
  const fg = relativeLuminance(parseHexColor(foreground));
  const bg = relativeLuminance(parseHexColor(background));
  const lighter = Math.max(fg, bg);
  const darker = Math.min(fg, bg);
  return (lighter + 0.05) / (darker + 0.05);
}

export function meetsWcagAA(ratio: number, largeText = false): boolean {
  return ratio >= (largeText ? 3 : 4.5);
}

/**
 * Pares de cor efetivamente usados em `styles/chat.module.css`.
 *
 * Mantenha esta lista em sincronia com a folha de estilos: o teste de contraste
 * (`chatTheme.test.ts`) usa esses valores como contrato minimo de WCAG AA.
 *
 * `#070d09` e o resultado de `--bg-2` (rgba(134, 239, 172, 0.055)) composto
 * sobre o fundo preto da pagina.
 */
export const CHAT_CONTRAST_PAIRS: ContrastPair[] = [
  {
    name: 'texto base sobre o fundo da pagina',
    foreground: '#f5f1ea',
    background: '#000000',
  },
  {
    name: 'texto do assistente sobre o balao',
    foreground: '#f5f1ea',
    background: '#070d09',
  },
  {
    name: 'texto do usuario sobre o balao',
    foreground: '#ffffff',
    background: '#15803d',
  },
  {
    name: 'thread ativa sobre a lista',
    foreground: '#ffffff',
    background: '#15803d',
  },
  {
    name: 'links do markdown sobre o balao',
    foreground: '#4ade80',
    background: '#070d09',
  },
  {
    name: 'mensagens de erro sobre a pagina',
    foreground: '#fca5a5',
    background: '#000000',
  },
  {
    name: 'comentarios de codigo sobre o bloco',
    foreground: '#9bb09e',
    background: '#0b0f0c',
  },
];
