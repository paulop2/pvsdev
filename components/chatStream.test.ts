import { describe, expect, it } from 'vitest';
import { parseSseBuffer } from './chatStream';

describe('parseSseBuffer', () => {
  it('extrai eventos completos e devolve o resto', () => {
    const { events, rest } = parseSseBuffer(
      'event: token\ndata: {"delta":"ola"}\n\nevent: token\ndata: {"delta":"x"',
    );
    expect(events).toEqual([{ event: 'token', data: '{"delta":"ola"}' }]);
    expect(rest).toBe('event: token\ndata: {"delta":"x"');
  });

  it('assume evento message quando nao ha linha event', () => {
    const { events } = parseSseBuffer('data: {"a":1}\n\n');
    expect(events).toEqual([{ event: 'message', data: '{"a":1}' }]);
  });

  it('junta multiplas linhas data', () => {
    const { events } = parseSseBuffer('event: x\ndata: a\ndata: b\n\n');
    expect(events).toEqual([{ event: 'x', data: 'a\nb' }]);
  });

  it('normaliza CRLF', () => {
    const { events, rest } = parseSseBuffer('event: token\r\ndata: {"delta":"a"}\r\n\r\n');
    expect(events).toEqual([{ event: 'token', data: '{"delta":"a"}' }]);
    expect(rest).toBe('');
  });

  it('nao emite evento sem data', () => {
    const { events } = parseSseBuffer('event: token\n\n');
    expect(events).toEqual([]);
  });
});
