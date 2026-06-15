import { WebPlugin } from '@capacitor/core';

import type { LabelPrinterPlugin } from './definitions';

export class LabelPrinterWeb extends WebPlugin implements LabelPrinterPlugin {
  async isSupported(): Promise<{ supported: boolean }> {
    return { supported: false };
  }
}
