# API

`@m430/capacitor-label-printer` 当前公开的是一组偏底层的打印能力，业务层建议自行封装打印模板、重试策略和任务队列。

## 方法

### `isSupported()`

判断当前运行环境是否支持原生标签打印。

返回：

```ts
Promise<{ supported: boolean }>
```

### `ensurePermissions()`

确保蓝牙访问权限已就绪。

返回：

```ts
Promise<{ granted: boolean }>
```

### `discoverDevices(options?)`

发现可用于连接的打印机列表。

参数：

```ts
interface DiscoverDevicesOptions {
  timeout?: number;
  namePrefixes?: string[];
}
```

返回：

```ts
Promise<{ devices: PrinterDevice[] }>
```

### `connect(options)`

连接指定打印机。

参数：

```ts
interface ConnectOptions {
  deviceId: string;
}
```

返回：

```ts
Promise<void>
```

### `disconnect()`

断开当前打印机连接。

返回：

```ts
Promise<void>
```

### `getConnectionState()`

查询当前连接状态。

返回：

```ts
Promise<{ state: PrinterConnectionState }>
```

其中 `PrinterConnectionState` 为：

```ts
type PrinterConnectionState = 'disconnected' | 'connecting' | 'connected';
```

### `print(options)`

发送原始打印负载到打印机。

参数：

```ts
interface PrintOptions {
  payload: string;
  language?: PrinterLanguage;
  copies?: number;
}
```

其中 `PrinterLanguage` 为：

```ts
type PrinterLanguage = 'tspl' | 'raw';
```

返回：

```ts
Promise<void>
```

### `getStatus()`

查询当前打印机状态。

返回：

```ts
Promise<PrinterStatus>
```

```ts
interface PrinterStatus {
  connected: boolean;
  ready?: boolean;
  paperOut?: boolean;
  coverOpen?: boolean;
  overheating?: boolean;
  message?: string;
  raw?: unknown;
}
```

## 主要类型

### `PrinterDevice`

```ts
interface PrinterDevice {
  id: string;
  name: string;
  address?: string;
  transport: PrinterTransport;
  bonded?: boolean;
  rssi?: number;
}
```

```ts
type PrinterTransport = 'classic' | 'ble';
```

## 导出的 TSPL 工具

除了 `LabelPrinter` 插件对象，包里还导出了：

- `TsplBuilder`
- `mmToDots`
- `escapeTsplText`

推荐业务层先用 `TsplBuilder` 组装 `payload`，再调用 `print()`。

## 额外说明

- Web 端只有 `isSupported()` 和 `getConnectionState()` / `getStatus()` 的兜底返回，其余方法会抛错
- 自动生成的结构化 API 元数据位于 `dist/docs.json`
