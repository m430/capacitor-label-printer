export interface LabelPrinterPlugin {
  isSupported(): Promise<{ supported: boolean }>;
}
