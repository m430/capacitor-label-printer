import { describe, expect, it } from 'vitest';

import { CpclBuilder } from './builder';

describe('CpclBuilder', () => {
  it('builds a printable cpcl label payload', () => {
    const payload = new CpclBuilder()
      .page(640, 1)
      .pageWidth(576)
      .text(4, 0, 40, 40, 'QR-365 TEST')
      .barcode128(40, 100, 80, 'YTO123456')
      .form()
      .print()
      .build();

    expect(payload).toBe(
      [
        '! 0 200 200 640 1',
        'PAGE-WIDTH 576',
        'TEXT 4 0 40 40 QR-365 TEST',
        'BARCODE 128 1 1 80 40 100 YTO123456',
        'FORM',
        'PRINT',
        '',
      ].join('\n'),
    );
  });
});
