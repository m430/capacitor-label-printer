import type { PrinterConnectionState, PrinterLanguage, PrinterTransport } from './types';

export interface PrinterDevice {
  id: string;
  name: string;
  address?: string;
  transport: PrinterTransport;
  bonded?: boolean;
  rssi?: number;
}

export interface DiscoverDevicesOptions {
  timeout?: number;
  namePrefixes?: string[];
}

export interface ConnectOptions {
  deviceId: string;
}

export interface PrintOptions {
  payload: string;
  language?: PrinterLanguage;
  copies?: number;
}

export interface PrinterStatus {
  connected: boolean;
  ready?: boolean;
  paperOut?: boolean;
  coverOpen?: boolean;
  overheating?: boolean;
  message?: string;
  raw?: unknown;
}

export interface LabelPrinterPlugin {
  isSupported(): Promise<{ supported: boolean }>;
  ensurePermissions(): Promise<{ granted: boolean }>;
  discoverDevices(options?: DiscoverDevicesOptions): Promise<{ devices: PrinterDevice[] }>;
  connect(options: ConnectOptions): Promise<void>;
  disconnect(): Promise<void>;
  getConnectionState(): Promise<{ state: PrinterConnectionState }>;
  print(options: PrintOptions): Promise<void>;
  getStatus(): Promise<PrinterStatus>;
}
