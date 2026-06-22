function escapeCpclText(value: string): string {
  return value.replace(/[\r\n]+/g, ' ').trim();
}

export class CpclBuilder {
  private readonly lines: string[] = [];

  page(height: number, copies = 1, offset = 0, horizontalDpi = 200, verticalDpi = 200): this {
    this.lines.push(`! ${offset} ${horizontalDpi} ${verticalDpi} ${height} ${copies}`);
    return this;
  }

  pageWidth(width: number): this {
    this.lines.push(`PAGE-WIDTH ${width}`);
    return this;
  }

  text(font: number, rotation: number, x: number, y: number, value: string): this {
    this.lines.push(`TEXT ${font} ${rotation} ${x} ${y} ${escapeCpclText(value)}`);
    return this;
  }

  barcode128(x: number, y: number, height: number, value: string, narrow = 1, wide = 1): this {
    this.lines.push(`BARCODE 128 ${narrow} ${wide} ${height} ${x} ${y} ${escapeCpclText(value)}`);
    return this;
  }

  form(): this {
    this.lines.push('FORM');
    return this;
  }

  print(): this {
    this.lines.push('PRINT');
    return this;
  }

  build(): string {
    return `${this.lines.join('\n')}\n`;
  }
}
