/**
 * 插件内部约定的连接通道类型。
 */
export type PrinterTransport = 'classic' | 'ble';

/**
 * 打印负载的协议类型。
 */
export type PrinterLanguage = 'tspl' | 'cpcl' | 'raw';

/**
 * 统一连接状态枚举。
 */
export type PrinterConnectionState = 'disconnected' | 'connecting' | 'connected';
