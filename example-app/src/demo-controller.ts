export interface DemoPrinterDevice {
  id: string;
  name: string;
  address?: string;
  transport: string;
  bonded?: boolean;
  rssi?: number;
}

export interface DemoPrinterStatus {
  connected: boolean;
  ready?: boolean;
  paperOut?: boolean;
  coverOpen?: boolean;
  overheating?: boolean;
  message?: string;
  raw?: unknown;
}

export interface DemoPrinterPermissionResult {
  granted: boolean;
  canPrompt: boolean;
  shouldOpenSettings: boolean;
  permissions: {
    bluetoothConnect?: 'prompt' | 'prompt-with-rationale' | 'granted' | 'denied';
    bluetoothScan?: 'prompt' | 'prompt-with-rationale' | 'granted' | 'denied';
    bluetooth?: 'prompt' | 'prompt-with-rationale' | 'granted' | 'denied';
  };
}

export interface DemoPrinterClient {
  isSupported(): Promise<{ supported: boolean }>;
  ensurePermissions(): Promise<DemoPrinterPermissionResult>;
  discoverDevices(options: {
    timeout?: number;
    namePrefixes?: string[];
  }): Promise<{ devices: DemoPrinterDevice[] }>;
  connect(options: { deviceId: string }): Promise<void>;
  disconnect(): Promise<void> | void;
  getConnectionState(): Promise<{
    state: 'disconnected' | 'connecting' | 'connected';
  }>;
  print(options: {
    payload: string;
    language: 'tspl' | 'cpcl';
    copies: number;
  }): Promise<void>;
  getStatus(): Promise<DemoPrinterStatus>;
  openAppSettings(): Promise<void>;
}

export interface DemoControllerState {
  supported: boolean | null;
  devices: DemoPrinterDevice[];
  selectedDeviceId: string;
  connectedDeviceId: string | null;
  connectionState: 'unknown' | 'disconnected' | 'connecting' | 'connected';
  status: DemoPrinterStatus | null;
  permissionResult: DemoPrinterPermissionResult | null;
  logs: string[];
  busyAction: string | null;
}

type StateListener = (state: DemoControllerState) => void;

export function createDemoController(
  printer: DemoPrinterClient,
  buildPayload: () => string,
) {
  const listeners = new Set<StateListener>();
  const state: DemoControllerState = {
    supported: null,
    devices: [],
    selectedDeviceId: '',
    connectedDeviceId: null,
    connectionState: 'unknown',
    status: null,
    permissionResult: null,
    logs: [],
    busyAction: null,
  };

  const emit = () => {
    const snapshot = getState();
    listeners.forEach((listener) => listener(snapshot));
  };

  const setState = (patch: Partial<DemoControllerState>) => {
    Object.assign(state, patch);
    emit();
  };

  const prependLog = (message: string) => {
    state.logs = [`${new Date().toLocaleTimeString()} ${message}`, ...state.logs].slice(0, 30);
    emit();
  };

  const runAction = async <T>(action: string, task: () => Promise<T>) => {
    setState({ busyAction: action });
    try {
      return await task();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      prependLog(`${action}失败：${message}`);
      throw error;
    } finally {
      setState({ busyAction: null });
    }
  };

  const syncSelectedDevice = (devices: DemoPrinterDevice[]) => {
    if (devices.some((device) => device.id === state.selectedDeviceId)) {
      return state.selectedDeviceId;
    }

    return devices[0]?.id ?? '';
  };

  const getState = (): DemoControllerState => ({
    ...state,
    devices: [...state.devices],
    status: state.status ? { ...state.status } : null,
    permissionResult: state.permissionResult
      ? {
          ...state.permissionResult,
          permissions: { ...state.permissionResult.permissions },
        }
      : null,
    logs: [...state.logs],
  });

  return {
    subscribe(listener: StateListener) {
      listeners.add(listener);
      listener(getState());

      return () => {
        listeners.delete(listener);
      };
    },

    getState,

    async init() {
      return runAction('初始化', async () => {
        const result = await printer.isSupported();
        setState({ supported: result.supported });
        prependLog(result.supported ? '原生标签打印能力可用' : '当前平台不支持原生标签打印');
      });
    },

    selectDevice(deviceId: string) {
      setState({ selectedDeviceId: deviceId });
      const selected = state.devices.find((device) => device.id === deviceId);
      if (selected) {
        prependLog(`已选择设备：${selected.name}`);
      }
    },

    async scan() {
      return runAction('扫描', async () => {
        const permissionResult = await printer.ensurePermissions();
        setState({ permissionResult });
        if (!permissionResult.granted) {
          prependLog(
            permissionResult.shouldOpenSettings
              ? '蓝牙权限已被拒绝，请先去设置开启附近设备权限'
              : '需要先允许附近设备权限，才能扫描打印机',
          );
          return;
        }

        const result = await printer.discoverDevices({
          timeout: 4000,
          namePrefixes: [],
        });

        const selectedDeviceId = syncSelectedDevice(result.devices);
        setState({
          devices: result.devices,
          selectedDeviceId,
        });
        if (result.devices.length === 0) {
          prependLog(
            '发现 0 台设备，请先确认打印机已在系统蓝牙中配对，然后重新扫描',
          );
          return;
        }

        prependLog(`发现 ${result.devices.length} 台设备`);
      });
    },

    async connectSelected() {
      return runAction('连接', async () => {
        if (!state.selectedDeviceId) {
          throw new Error('请先扫描并选择一台打印机');
        }

        await printer.connect({ deviceId: state.selectedDeviceId });
        const selected = state.devices.find((device) => device.id === state.selectedDeviceId);
        setState({
          connectedDeviceId: state.selectedDeviceId,
          connectionState: 'connected',
        });
        prependLog(`已连接设备：${selected?.name ?? state.selectedDeviceId}`);
      });
    },

    async readConnectionState() {
      return runAction('连接状态', async () => {
        const result = await printer.getConnectionState();
        const connectedDeviceId =
          result.state === 'connected' ? state.connectedDeviceId ?? state.selectedDeviceId : null;

        setState({
          connectionState: result.state,
          connectedDeviceId,
        });
        prependLog(`连接状态：${result.state}`);
      });
    },

    async readStatus() {
      return runAction('打印机状态', async () => {
        const result = await printer.getStatus();
        setState({ status: result });
        prependLog(
          `打印机状态：connected=${result.connected}, ready=${result.ready ?? 'unknown'}`,
        );
      });
    },

    async refreshStatus() {
      await this.readConnectionState();
      await this.readStatus();
    },

    async printTestLabel() {
      return runAction('打印', async () => {
        if (state.connectionState !== 'connected') {
          throw new Error('请先连接打印机');
        }

        await printer.print({
          payload: buildPayload(),
          language: 'cpcl',
          copies: 1,
        });
        prependLog('测试标签已发送到打印机');
      });
    },

    async disconnect() {
      return runAction('断开', async () => {
        await printer.disconnect();
        setState({
          connectedDeviceId: null,
          connectionState: 'disconnected',
          status: null,
        });
        prependLog('已断开当前打印机会话');
      });
    },

    async openSettings() {
      return runAction('权限设置', async () => {
        await printer.openAppSettings();
        prependLog('已打开系统设置页，请为应用开启附近设备权限后返回重试');
      });
    },
  };
}
