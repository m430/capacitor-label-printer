import { LabelPrinter, TsplBuilder } from '@m430/capacitor-label-printer';

async function main() {
  const supported = await LabelPrinter.isSupported();
  const app = document.querySelector('#app');
  if (!app) {
    return;
  }

  const builder = new TsplBuilder()
    .sizeMm(75, 130)
    .gapMm(2, 0)
    .density(8)
    .cls()
    .text(40, 40, 'TEXT', 0, 1, 1, 'QR-365 TEST')
    .barcode128(40, 90, 80, 'YTO123456')
    .printCopies(1);

  app.innerHTML = `
    <button id="scan">scan</button>
    <button id="print">print</button>
    <pre id="log">${JSON.stringify(supported, null, 2)}</pre>
  `;

  document.querySelector('#scan')?.addEventListener('click', async () => {
    const devices = await LabelPrinter.discoverDevices({ namePrefixes: ['QR-365'] });
    const log = document.querySelector('#log');
    if (log) {
      log.textContent = JSON.stringify(devices, null, 2);
    }
  });

  document.querySelector('#print')?.addEventListener('click', async () => {
    await LabelPrinter.print({ payload: builder.build(), language: 'tspl', copies: 1 });
  });
}

main();
