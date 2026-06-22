import { describe, expect, it, vi } from 'vitest';

import { createDemoController } from './demo-controller';

describe('createDemoController', () => {
  it('扫描后写入设备列表并默认选择第一台设备', async () => {
    const printer = {
      isSupported: vi.fn().mockResolvedValue({ supported: true }),
      ensurePermissions: vi.fn().mockResolvedValue({
        granted: true,
        canPrompt: false,
        shouldOpenSettings: false,
        permissions: { bluetoothConnect: 'granted', bluetoothScan: 'granted' },
      }),
      discoverDevices: vi.fn().mockResolvedValue({
        devices: [
          { id: 'printer-1', name: 'QR-365-A', transport: 'classic' },
          { id: 'printer-2', name: 'QR-365-B', transport: 'classic' },
        ],
      }),
      connect: vi.fn().mockResolvedValue(undefined),
      disconnect: vi.fn().mockResolvedValue(undefined),
      getConnectionState: vi.fn().mockResolvedValue({ state: 'disconnected' }),
      print: vi.fn().mockResolvedValue(undefined),
      getStatus: vi.fn().mockResolvedValue({ connected: false }),
      openAppSettings: vi.fn().mockResolvedValue(undefined),
    };

    const controller = createDemoController(printer, () => 'TEST');

    await controller.scan();

    expect(printer.discoverDevices).toHaveBeenCalledWith({
      timeout: 4000,
      namePrefixes: [],
    });
    expect(printer.ensurePermissions).toHaveBeenCalledOnce();
    expect(controller.getState().devices).toHaveLength(2);
    expect(controller.getState().selectedDeviceId).toBe('printer-1');
    expect(controller.getState().logs[0]).toContain('发现 2 台设备');
  });

  it('扫描到 0 台设备时给出已配对和权限提示', async () => {
    const printer = {
      isSupported: vi.fn().mockResolvedValue({ supported: true }),
      ensurePermissions: vi.fn().mockResolvedValue({
        granted: true,
        canPrompt: false,
        shouldOpenSettings: false,
        permissions: { bluetoothConnect: 'granted', bluetoothScan: 'granted' },
      }),
      discoverDevices: vi.fn().mockResolvedValue({ devices: [] }),
      connect: vi.fn().mockResolvedValue(undefined),
      disconnect: vi.fn().mockResolvedValue(undefined),
      getConnectionState: vi.fn().mockResolvedValue({ state: 'disconnected' }),
      print: vi.fn().mockResolvedValue(undefined),
      getStatus: vi.fn().mockResolvedValue({ connected: false }),
      openAppSettings: vi.fn().mockResolvedValue(undefined),
    };

    const controller = createDemoController(printer, () => 'TEST');

    await controller.scan();

    expect(controller.getState().logs[0]).toContain('请先确认打印机已在系统蓝牙中配对');
  });

  it('按顺序调用连接、状态、打印和断开，并维护当前连接设备', async () => {
    const printer = {
      isSupported: vi.fn().mockResolvedValue({ supported: true }),
      ensurePermissions: vi.fn().mockResolvedValue({
        granted: true,
        canPrompt: false,
        shouldOpenSettings: false,
        permissions: { bluetoothConnect: 'granted', bluetoothScan: 'granted' },
      }),
      discoverDevices: vi.fn().mockResolvedValue({
        devices: [{ id: 'printer-1', name: 'QR-365-A', transport: 'classic' }],
      }),
      connect: vi.fn().mockResolvedValue(undefined),
      disconnect: vi.fn().mockResolvedValue(undefined),
      getConnectionState: vi.fn().mockResolvedValue({ state: 'connected' }),
      print: vi.fn().mockResolvedValue(undefined),
      getStatus: vi.fn().mockResolvedValue({ connected: true, ready: true }),
      openAppSettings: vi.fn().mockResolvedValue(undefined),
    };

    const controller = createDemoController(printer, () => 'TSPL-PAYLOAD');

    await controller.scan();
    await controller.connectSelected();
    await controller.readConnectionState();
    await controller.printTestLabel();
    await controller.readStatus();
    await controller.disconnect();

    expect(printer.connect).toHaveBeenCalledWith({ deviceId: 'printer-1' });
    expect(printer.getConnectionState).toHaveBeenCalledOnce();
    expect(printer.print).toHaveBeenCalledWith({
      payload: 'TSPL-PAYLOAD',
      language: 'cpcl',
      copies: 1,
    });
    expect(printer.getStatus).toHaveBeenCalledOnce();
    expect(printer.disconnect).toHaveBeenCalledOnce();
    expect(controller.getState().connectedDeviceId).toBeNull();
    expect(controller.getState().connectionState).toBe('disconnected');
  });

  it('扫描前先确保权限，权限被永久拒绝时不继续发现设备', async () => {
    const printer = {
      isSupported: vi.fn().mockResolvedValue({ supported: true }),
      ensurePermissions: vi.fn().mockResolvedValue({
        granted: false,
        canPrompt: false,
        shouldOpenSettings: true,
        permissions: { bluetoothConnect: 'denied', bluetoothScan: 'denied' },
      }),
      discoverDevices: vi.fn().mockResolvedValue({ devices: [] }),
      connect: vi.fn().mockResolvedValue(undefined),
      disconnect: vi.fn().mockResolvedValue(undefined),
      getConnectionState: vi.fn().mockResolvedValue({ state: 'disconnected' }),
      print: vi.fn().mockResolvedValue(undefined),
      getStatus: vi.fn().mockResolvedValue({ connected: false }),
      openAppSettings: vi.fn().mockResolvedValue(undefined),
    };

    const controller = createDemoController(printer as never, () => 'TEST');

    await controller.scan();

    expect(printer.ensurePermissions).toHaveBeenCalledOnce();
    expect(printer.discoverDevices).not.toHaveBeenCalled();
    expect(controller.getState().logs[0]).toContain('去设置开启附近设备权限');
  });
});
