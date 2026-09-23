import { describe, expect, it } from 'vitest';
import {
  CHAT_CONTRAST_PAIRS,
  contrastRatio,
  meetsWcagAA,
  parseHexColor,
  relativeLuminance,
} from './chatTheme';

describe('parseHexColor', () => {
  it('le cores de 6 e 3 digitos', () => {
    expect(parseHexColor('#15803d')).toEqual({ r: 0x15, g: 0x80, b: 0x3d });
    expect(parseHexColor('#fff')).toEqual({ r: 255, g: 255, b: 255 });
  });

  it('recusa cores invalidas', () => {
    expect(() => parseHexColor('#zzz')).toThrow(/invalida/i);
    expect(() => parseHexColor('15803d00')).toThrow();
  });
});

describe('contrastRatio', () => {
  it('maximiza o contraste entre preto e branco', () => {
    expect(contrastRatio('#000000', '#ffffff')).toBeCloseTo(21, 5);
  });

  it('retorna 1 para a mesma cor', () => {
    expect(contrastRatio('#4ade80', '#4ade80')).toBeCloseTo(1, 5);
  });

  it('e simetrico', () => {
    expect(contrastRatio('#f5f1ea', '#070d09')).toBeCloseTo(
      contrastRatio('#070d09', '#f5f1ea'),
      5,
    );
  });

  it('classifica luminancia relativa', () => {
    expect(relativeLuminance(parseHexColor('#ffffff'))).toBeCloseTo(1, 5);
    expect(relativeLuminance(parseHexColor('#000000'))).toBeCloseTo(0, 5);
  });
});

describe('meetsWcagAA', () => {
  it('exige 4.5 para texto normal e 3.0 para texto grande', () => {
    expect(meetsWcagAA(4.49)).toBe(false);
    expect(meetsWcagAA(4.5)).toBe(true);
    expect(meetsWcagAA(2.9, true)).toBe(false);
    expect(meetsWcagAA(3, true)).toBe(true);
  });
});

describe('paleta do chat', () => {
  it('mantem todos os pares de cor dentro do minimo WCAG AA', () => {
    for (const pair of CHAT_CONTRAST_PAIRS) {
      const ratio = contrastRatio(pair.foreground, pair.background);
      expect(
        meetsWcagAA(ratio, pair.largeText),
        `${pair.name}: ${ratio.toFixed(2)}:1 (${pair.foreground} sobre ${pair.background})`,
      ).toBe(true);
    }
  });
});
