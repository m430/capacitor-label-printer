# API

`@m430/capacitor-label-printer` 当前公开的是一组偏底层的打印能力，业务层建议自行封装打印模板、重试策略和任务队列。

## 方法

### `isSupported()`

判断当前运行环境是否支持原生标签打印。

返回：

```ts
Promise<{ supported: boolean }>
```

### `checkPermissions()`

查询当前蓝牙权限状态。

返回：

```ts
Promise<PrinterPermissionResult>
```

### `ensurePermissions()`

确保蓝牙访问权限已就绪。

- Android：会主动触发“附近设备”权限申请
- iOS：按需初始化蓝牙管理器并等待系统授权结果；未决定授权时不会提前返回 `granted: true`。授权成功不代表蓝牙开关已开启

返回：

```ts
Promise<PrinterPermissionResult>
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

说明：

- Android / iOS 上如果权限不足，插件会在内部先尝试申请权限
- 权限仍不足时会抛出 `PERMISSION_DENIED`
- iOS 在授权和蓝牙就绪后才开始扫描计时；蓝牙关闭或不可用时拒绝调用，而非返回空设备列表
- iOS 只返回广播了名称的设备；未广播名称的 BLE 设备不会出现在结果中（与厂商 demo 行为一致，避免把无法识别的设备当成打印机）
- iOS 的 `timeout` 单位为毫秒，范围为大于 0、至多 60000；蓝牙就绪等待另有 10 秒超时

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

说明：

- iOS 上必须先调用 `discoverDevices()`，再使用返回的 `id` 连接（BLE 需要持有外设实例）
- iOS 等待服务、可确认写入的特征及通知订阅就绪后才返回成功；仅支持无响应写入的设备会明确报错
- 优先采用厂商专用 UUID；通用设备必须提供唯一的同服务写入/通知特征组合，缺少或有歧义时拒绝连接，避免误写配置特征
- iOS 连接超时会取消底层连接；取消尚未完成时拒绝新连接，避免迟到回调污染新会话

### `disconnect()`

断开当前打印机连接。iOS 会取消进行中的扫描、连接、打印或状态查询，并等待底层断开回调后返回；断开超时会拒绝调用。

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
type PrinterLanguage = 'tspl' | 'cpcl' | 'raw';
```

返回：

```ts
Promise<void>
```

说明：

- `print()` 的成功语义是“写入完成”，不等待纸张物理走完
- Android：`tspl` 按行经厂商管道写入，`cpcl` / `raw` 按 1024 字节分块写入（块间 20ms）
- iOS：使用 `CoreBluetooth.writeValue(..., .withResponse)`，按协商的最大写入长度分块；每块收到 `didWriteValueFor` 成功回调后才发送下一块，最后一块确认后才 resolve。这是 BLE 特征写入确认，不是打印机解析或出纸确认
- iOS 的 `tspl` 按文本行规范为 CRLF；`cpcl` / `raw` 不替换或追加换行，分块连接后与原始编码字节完全相同。二进制负载请使用 `raw`
- `cpcl` / `raw` 使用 `ISO-8859-1` 编码，其余使用 `UTF-8`
- iOS 的 `copies` 为 1–1000；写入失败或每块确认超时（10 秒）会取消连接。失败时可能已有部分字节送达，业务层不要盲目重试，以免重复打印
- iOS 的扫描、连接、打印和主动查询不可并行；冲突的写操作会报告 busy，业务层应顺序 `await`

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

说明：

- Android 在 `tspl` 或默认语言下会主动发送 `state` 查询；`cpcl` / `raw` 跳过主动查询
- iOS 仅在当前连接已通过 `print({ language: 'tspl', ... })` 明确语言、通知已订阅且无其他操作时发送厂商 `READSTA` 查询；刚连接、`cpcl` / `raw`、忙碌时不发送
- iOS 在发送前建立接收上下文，合并分片，等待 CRLF 或 `ENDRECEIVE` 结束标记；写入确认后最多再等待 1.5 秒。超时或接收错误后，本次连接不再主动查询，需重连恢复，以免迟到响应串入后续查询
- iOS 的状态响应格式尚待真机确认。通知没有请求编号，查询窗口也可能收到此前打印的回报，因此 `raw` 返回 `{ data: string | number[], correlated: false }`，仅作诊断，不保证属于本次查询
- iOS 不根据未关联通知推测 `ready`、缺纸或开盖；未知字段会省略，断开时 `ready` 为 false。没有响应不代表就绪

### `openAppSettings()`

跳转到应用系统设置页。

返回：

```ts
Promise<void>
```

## 主要类型

### `PrinterPermissionResult`

```ts
interface PrinterPermissionResult {
  granted: boolean;
  canPrompt: boolean;
  shouldOpenSettings: boolean;
  permissions: {
    bluetoothConnect?: PermissionState;
    bluetoothScan?: PermissionState;
    bluetooth?: PermissionState;
  };
}
```

```ts
type PermissionState = 'prompt' | 'prompt-with-rationale' | 'granted' | 'denied';
```

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

## 导出的 Builder 与 Helper

除了 `LabelPrinter` 插件对象，包里还导出了：

- `CpclBuilder`
- `TsplBuilder`
- `mmToDots`
- `escapeTsplText`

推荐业务层先用 `CpclBuilder` 或 `TsplBuilder` 组装 `payload`，再调用 `print()`。

## 额外说明

- Web 端只有 `isSupported()` 和 `getConnectionState()` / `getStatus()` 的兜底返回，其余方法会抛错
- 自动生成的结构化 API 元数据位于 `dist/docs.json`
