import { describe, expect, it } from 'vitest';

import { LabelPrinterWeb } from './web';

describe('LabelPrinterWeb', () => {
  it('returns unsupported on the web placeholder implementation', async () => {
    const plugin = new LabelPrinterWeb();

    await expect(plugin.isSupported()).resolves.toEqual({ supported: false });
  });
});
