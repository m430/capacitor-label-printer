import { registerPlugin } from '@capacitor/core';

import type { LabelPrinterPlugin } from './definitions';

const LabelPrinter = registerPlugin<LabelPrinterPlugin>('LabelPrinter', {
  web: () => import('./web').then(m => new m.LabelPrinterWeb())
});

export * from './definitions';
export * from './errors';
export * from './types';
export * from './cpcl/builder';
export * from './tspl/builder';
export * from './tspl/helpers';
export { LabelPrinter };
