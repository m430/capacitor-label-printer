# @m430/capacitor-label-printer

面向启锐 `QR-365` 及同类标签热敏打印机的 `Capacitor 7` 插件，内置 `CPCL` / `TSPL` 指令发送能力。

这个包的目标不是把业务模板写死在插件里，而是提供一层可复用的原生打印通道，统一暴露设备发现、连接、状态查询和标签打印能力，并随 npm 包分发 Android `jar` 与 iOS `framework`。

## 当前状态

- 已完成独立仓库、npm 包、Capacitor 插件骨架和 `example-app`
- 已完成 Android `jar` 与 iOS `framework` 的随包分发
- 已完成统一 JS API、`CPCL` / `TSPL` builder、Android/iOS 编译链路验证
- Android 端基于厂商经典蓝牙 `jar`；iOS 使用 `CoreBluetooth` 异步传输，已补充桥接注册、权限、字节保真与写入确认的自动化回归，打印机兼容性仍需真机验收

## 安装

```bash
npm install @m430/capacitor-label-printer
npx cap sync
```

如果宿主项目还没有添加原生平台，请先执行：

```bash
npx cap add android
npx cap add ios
```

## 宿主项目权限

### Android

Android 蓝牙权限已经随插件一起分发并参与宿主 Manifest 合并，通常不需要宿主项目再手写：

- `BLUETOOTH`、`BLUETOOTH_ADMIN`，并带 `maxSdkVersion=30`
- `BLUETOOTH_CONNECT`
- `BLUETOOTH_SCAN`，并带 `neverForLocation`

体验约定：

- 首次调用 `discoverDevices()` 时，插件会自动触发“附近设备”权限申请
- 也可以先主动调用 `ensurePermissions()`，拿到结构化权限状态后再决定是否继续
- 如果用户永久拒绝权限，可调用 `openAppSettings()` 引导跳转系统设置页

### iOS

宿主项目需要在自己的 `Info.plist` 中补充蓝牙用途说明：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>App 需要连接蓝牙标签打印机以打印物流面单与条码标签</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>App 需要访问蓝牙设备以完成标签打印</string>
```

## 快速使用

```ts
import { CpclBuilder, LabelPrinter } from '@m430/capacitor-label-printer';

async function printDemoLabel() {
  const support = await LabelPrinter.isSupported();
  if (!support.supported) {
    throw new Error('当前平台不支持原生标签打印');
  }

  const permissionResult = await LabelPrinter.ensurePermissions();
  if (!permissionResult.granted) {
    if (permissionResult.shouldOpenSettings) {
      await LabelPrinter.openAppSettings();
    }
    throw new Error('需要先允许蓝牙附近设备权限');
  }

  const { devices } = await LabelPrinter.discoverDevices({
    namePrefixes: ['QR', 'QIRUI', 'BEEPRT']
  });

  if (!devices.length) {
    throw new Error('没有找到可用打印机');
  }

  await LabelPrinter.connect({ deviceId: devices[0].id });

  const payload = new CpclBuilder()
    .page(640, 1)
    .pageWidth(576)
    .text(4, 0, 40, 40, 'YT1234567890')
    .barcode128(40, 120, 80, 'YT1234567890')
    .form()
    .print()
    .build();

  await LabelPrinter.print({
    payload,
    language: 'cpcl',
    copies: 1
  });

  const status = await LabelPrinter.getStatus();
  console.log(status);
}
```

## API 概览

插件当前公开这些方法：

- `isSupported`
- `checkPermissions`
- `ensurePermissions`
- `discoverDevices`
- `connect`
- `disconnect`
- `getConnectionState`
- `print`
- `getStatus`
- `openAppSettings`

完整 API 文档见 [API.md](./API.md)。

## Helper

已内置 `CpclBuilder`、`TsplBuilder` 与基础 helper，适合物流面单、条码标签这类“一张一张打”的场景：

- `page`
- `pageWidth`
- `sizeMm`
- `gapMm`
- `density`
- `speed`
- `cls`
- `text`
- `barcode128`
- `qrcode`
- `printCopies`

## 平台说明

### Android

- 当前集成的是厂商 `TSPL classic bluetooth` 方向的 `jar`
- 插件包内已带上 `android/libs/fat-generic-tspl-bluetooth-classic-0.1.16-GA.jar`
- 现阶段 `discoverDevices` 主要基于已配对设备过滤，适合作为 `QR-365` 的首版接入基线
- `discoverDevices()` 与 `connect()` 会在 Android 12+ 自动兜底附近设备权限

### iOS

- 当前包内已带上 `ios/VendorFrameworks/` 下的厂商 `framework`
- `CocoaPods` 集成使用的是 `M430CapacitorLabelPrinter.podspec`
- 已验证 `npx cap sync ios` 与 `xcodebuild` 编译链路可通过
- iOS 直接使用 `CoreBluetooth` 异步回调，不再依赖厂商 `WroteReporter` 判断送达；按协商长度分块，逐块等待 BLE 写入确认后才 resolve，不等待物理出纸
- `CPCL` / `raw` 保留原始编码字节，不改写或追加换行；只支持无响应写入的 BLE 设备会明确拒绝连接
- `getStatus()` 仅在当前会话明确打印过 `TSPL` 后主动查询；未知语言和 `CPCL` / `raw` 不查询。无有效状态依据时省略 `ready` 等字段，原始响应通过 `raw` 返回
- 状态查询超时后禁用本次连接的后续查询，重连恢复，避免迟到响应污染下一次查询；详细超时与调用约束见 [API.md](./API.md)
- `connect()` 前必须先调用 `discoverDevices()`（BLE 需要持有外设实例）
- `discoverDevices()` 只返回广播了名称的 BLE 设备（与厂商 demo 一致）；未广播名称的设备不会出现在结果中
- iOS 仍需要宿主在 `Info.plist` 中声明蓝牙用途说明

### Web

- 不支持
- `isSupported()` 返回 `false`
- 其余原生能力会抛出 `Label printing is not supported on web.`

## 开发与发布校验

```bash
npm run verify
python3 scripts/test-ios.py --mutations
npm run verify:ios
npm run verify:release
```

其中：

- `verify` 会执行单测、Android Gradle 构建和插件打包
- `python3 scripts/test-ios.py --mutations` 在 macOS 上用 BLE 测试替身运行真实 Swift 管理器和插件的回归，并验证测试能检出重新引入的错误；它不能替代真机 BLE 验收
- `verify:ios` 会执行 `example-app` 的 `cap sync ios` 与 `xcodebuild`
- `verify:release` 会串起完整发布前检查，并执行 `npm pack --dry-run`

## 已随包分发的原生资源

- Android `jar`
- iOS `framework`
- iOS `podspec`

宿主项目安装后不需要再单独下载一份厂商 SDK。

## 已知限制

- 当前版本以“统一 API + 原生依赖分发 + 构建链路打通”为主
- Android 已基于厂商经典蓝牙 `jar` 接入；iOS 使用 `CoreBluetooth`，服务选择兼容厂商示例的特征规则，但具体设备的写入确认支持、状态响应格式及纸张打印效果仍需真机验收
- iOS 的 BLE 写入确认不代表打印机已解析指令；通知没有请求编号，`raw.correlated` 固定为 false，目前不把这些未关联的数据映射成缺纸、开盖等布尔值
- 还没有内置打印队列、自动重连、模板编辑器和图片调试工具

## 仓库

- GitHub: `https://github.com/m430/capacitor-label-printer`
- npm: `@m430/capacitor-label-printer`
