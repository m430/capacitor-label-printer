import { WebPlugin } from '@capacitor/core';

import { UNSUPPORTED_WEB_ERROR } from './errors';

import type {
  ConnectOptions,
  DiscoverDevicesOptions,
  LabelPrinterPlugin,
  PrintOptions,
  PrinterStatus,
} from './definitions';
import type { PrinterConnectionState } from './types';

export class LabelPrinterWeb extends WebPlugin implements LabelPrinterPlugin {
  async isSupported(): Promise<{ supported: boolean }> {
    return { supported: false };
  }

  async ensurePermissions(): Promise<{ granted: boolean }> {
    throw new Error(UNSUPPORTED_WEB_ERROR);
  }

  async discoverDevices(_options?: DiscoverDevicesOptions): Promise<{ devices: [] }> {
    throw new Error(UNSUPPORTED_WEB_ERROR);
  }

  async connect(_options: ConnectOptions): Promise<void> {
    throw new Error(UNSUPPORTED_WEB_ERROR);
  }

  async disconnect(): Promise<void> {
    throw new Error(UNSUPPORTED_WEB_ERROR);
  }

  async getConnectionState(): Promise<{ state: PrinterConnectionState }> {
    return { state: 'disconnected' };
  }

  async print(_options: PrintOptions): Promise<void> {
    throw new Error(UNSUPPORTED_WEB_ERROR);
  }

  async getStatus(): Promise<PrinterStatus> {
    return { connected: false, message: UNSUPPORTED_WEB_ERROR };
  }
}
