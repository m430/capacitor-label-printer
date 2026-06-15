import { describe, expect, it } from 'vitest';

import { TsplBuilder } from './builder';
import { mmToDots } from './helpers';

describe('TSPL helpers', () => {
  it('converts millimeters to 203dpi dots', () => {
    expect(mmToDots(25.4)).toBe(203);
  });

  it('builds a complete TSPL label', () => {
    const payload = new TsplBuilder()
      .sizeMm(75, 130)
      .gapMm(2, 0)
      .density(8)
      .cls()
      .text(40, 40, 'TEXT', 0, 1, 1, 'ORDER: YTO123456')
      .barcode128(40, 90, 80, 'YTO123456')
      .printCopies(1)
      .build();

    expect(payload).toContain('SIZE 75 mm,130 mm');
    expect(payload).toContain('TEXT 40,40,"TEXT",0,1,1,"ORDER: YTO123456"');
    expect(payload).toContain('BARCODE 40,90,"128",80,1,0,2,2,"YTO123456"');
    expect(payload.trim().endsWith('PRINT 1,1')).toBe(true);
  });
});
