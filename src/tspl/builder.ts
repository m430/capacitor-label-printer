import { escapeTsplText } from './helpers';

export class TsplBuilder {
  private readonly lines: string[] = [];

  sizeMm(width: number, height: number): this {
    this.lines.push(`SIZE ${width} mm,${height} mm`);
    return this;
  }

  gapMm(gap: number, offset: number): this {
    this.lines.push(`GAP ${gap} mm,${offset} mm`);
    return this;
  }

  density(level: number): this {
    this.lines.push(`DENSITY ${level}`);
    return this;
  }

  speed(level: number): this {
    this.lines.push(`SPEED ${level}`);
    return this;
  }

  cls(): this {
    this.lines.push('CLS');
    return this;
  }

  text(x: number, y: number, font: string, rotation: number, xScale: number, yScale: number, value: string): this {
    this.lines.push(`TEXT ${x},${y},"${font}",${rotation},${xScale},${yScale},"${escapeTsplText(value)}"`);
    return this;
  }

  barcode128(x: number, y: number, height: number, value: string): this {
    this.lines.push(`BARCODE ${x},${y},"128",${height},1,0,2,2,"${escapeTsplText(value)}"`);
    return this;
  }

  qrcode(x: number, y: number, cellWidth: number, value: string): this {
    this.lines.push(`QRCODE ${x},${y},L,${cellWidth},A,0,"${escapeTsplText(value)}"`);
    return this;
  }

  printCopies(copies: number): this {
    this.lines.push(`PRINT 1,${copies}`);
    return this;
  }

  build(): string {
    return `${this.lines.join('\n')}\n`;
  }
}
