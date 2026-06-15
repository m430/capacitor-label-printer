import { describe, expect, it } from 'vitest';

import { LabelPrinterWeb } from './web';

describe('LabelPrinterWeb', () => {
  it('reports unsupported on web', async () => {
    const plugin = new LabelPrinterWeb();

    await expect(plugin.isSupported()).resolves.toEqual({ supported: false });
  });

  it('throws for native-only methods', async () => {
    const plugin = new LabelPrinterWeb();

    await expect(plugin.ensurePermissions()).rejects.toThrow('Label printing is not supported on web.');
  });
});
