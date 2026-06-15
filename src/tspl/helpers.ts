export function mmToDots(mm: number, dpi = 203): number {
  return Math.round((mm / 25.4) * dpi);
}

export function escapeTsplText(value: string): string {
  return value.replace(/"/g, '\\"');
}
