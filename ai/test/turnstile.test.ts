import { describe, expect, it, vi } from 'vitest';
import { verifyTurnstile } from '../src/turnstile';

const okFetch = () =>
  vi.fn(
    async (_input: string, _init?: RequestInit) =>
      new Response(JSON.stringify({ success: true }), { status: 200 }),
  );

describe('verifyTurnstile', () => {
  it('aprova quando siteverify retorna success', async () => {
    const fetchImpl = okFetch();
    const result = await verifyTurnstile({ secret: 's', token: 't', ip: '1.2.3.4', fetchImpl });
    expect(result).toBe(true);
    const [url, init] = fetchImpl.mock.calls[0] as [string, RequestInit];
    expect(url).toContain('/siteverify');
    expect((init.body as URLSearchParams).get('remoteip')).toBe('1.2.3.4');
  });

  it('rejeita quando success e false', async () => {
    const fetchImpl = vi.fn(async () =>
      new Response(JSON.stringify({ success: false }), { status: 200 }),
    );
    expect(await verifyTurnstile({ secret: 's', token: 't', ip: null, fetchImpl })).toBe(false);
  });

  it('rejeita sem secret', async () => {
    const fetchImpl = okFetch();
    expect(await verifyTurnstile({ secret: '  ', token: 't', ip: null, fetchImpl })).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('rejeita secret indefinido sem lancar e sem chamar fetch', async () => {
    const fetchImpl = okFetch();
    const result = await verifyTurnstile({
      secret: undefined as unknown as string,
      token: 't',
      ip: null,
      fetchImpl,
    });
    expect(result).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('rejeita token indefinido sem lancar e sem chamar fetch', async () => {
    const fetchImpl = okFetch();
    const result = await verifyTurnstile({
      secret: 's',
      token: undefined as unknown as string,
      ip: null,
      fetchImpl,
    });
    expect(result).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('rejeita sem token', async () => {
    const fetchImpl = okFetch();
    expect(await verifyTurnstile({ secret: 's', token: '', ip: null, fetchImpl })).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('rejeita fail-closed em erro de rede', async () => {
    const fetchImpl = vi.fn(async () => {
      throw new Error('network');
    });
    expect(await verifyTurnstile({ secret: 's', token: 't', ip: null, fetchImpl })).toBe(false);
  });

  it('rejeita fail-closed em status nao-2xx', async () => {
    const fetchImpl = vi.fn(async () => new Response('nope', { status: 500 }));
    expect(await verifyTurnstile({ secret: 's', token: 't', ip: null, fetchImpl })).toBe(false);
  });
});
