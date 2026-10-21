import { describe, it, expect } from 'vitest';

describe('Test Environment', () => {
  it('should run tests', () => {
    expect(1 + 1).toBe(2);
  });

  it('should support BigInt', () => {
    expect(1n + 1n).toBe(2n);
  });

  it('should have access to viem types', async () => {
    const { isAddress } = await import('viem');
    expect(isAddress('0x0000000000000000000000000000000000000000')).toBe(true);
  });
});
