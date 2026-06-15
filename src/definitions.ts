import type { PrinterConnectionState, PrinterLanguage, PrinterTransport } from './types';

/**
 * 扫描或枚举到的标签打印机设备。
 */
export interface PrinterDevice {
  id: string;
  name: string;
  address?: string;
  transport: PrinterTransport;
  bonded?: boolean;
  rssi?: number;
}

/**
 * 发现设备时使用的过滤参数。
 */
export interface DiscoverDevicesOptions {
  timeout?: number;
  namePrefixes?: string[];
}

/**
 * 连接指定设备时使用的参数。
 */
export interface ConnectOptions {
  deviceId: string;
}

/**
 * 打印任务参数。
 */
export interface PrintOptions {
  payload: string;
  language?: PrinterLanguage;
  copies?: number;
}

/**
 * 插件统一输出的打印机状态。
 */
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
  /**
   * 判断当前运行环境是否支持原生标签打印。
   */
  isSupported(): Promise<{ supported: boolean }>;

  /**
   * 确保蓝牙访问权限已就绪。
   */
  ensurePermissions(): Promise<{ granted: boolean }>;

  /**
   * 发现可用于连接的打印机列表。
   */
  discoverDevices(options?: DiscoverDevicesOptions): Promise<{ devices: PrinterDevice[] }>;

  /**
   * 连接指定打印机。
   */
  connect(options: ConnectOptions): Promise<void>;

  /**
   * 断开当前打印机连接。
   */
  disconnect(): Promise<void>;

  /**
   * 查询当前连接状态。
   */
  getConnectionState(): Promise<{ state: PrinterConnectionState }>;

  /**
   * 发送原始打印负载到打印机。
   */
  print(options: PrintOptions): Promise<void>;

  /**
   * 查询当前打印机状态。
   */
  getStatus(): Promise<PrinterStatus>;
}
