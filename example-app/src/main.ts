import { CpclBuilder, LabelPrinter } from '@m430/capacitor-label-printer';

import type { DemoControllerState } from './demo-controller';
import { createDemoController } from './demo-controller';

function buildTestPayload() {
  return new CpclBuilder()
    .page(640, 1)
    .pageWidth(576)
    .text(4, 0, 40, 40, 'QR-365 TEST')
    .text(4, 0, 40, 90, 'Capacitor Label Printer')
    .barcode128(40, 150, 80, 'YTO123456')
    .form()
    .print()
    .build();
}

function escapeHtml(content: string) {
  return content
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function toPrettyJson(value: unknown) {
  return escapeHtml(JSON.stringify(value, null, 2));
}

function render(state: DemoControllerState) {
  const selectedDevice = state.devices.find((device) => device.id === state.selectedDeviceId) ?? null;
  const isBusy = state.busyAction !== null;
  const canConnect = Boolean(state.selectedDeviceId) && !isBusy;
  const canPrint = state.connectionState === 'connected' && !isBusy;
  const canDisconnect = state.connectionState !== 'disconnected' && !isBusy;
  const canOpenSettings = Boolean(state.permissionResult?.shouldOpenSettings) && !isBusy;
  const permissionSummary =
    state.permissionResult == null
      ? '未检查'
      : state.permissionResult.granted
        ? '已授权'
        : state.permissionResult.shouldOpenSettings
          ? '需去设置开启'
          : '待授权';

  return `
    <style>
      :root {
        font-family: "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
        color: #102a43;
        background:
          radial-gradient(circle at top left, rgba(255, 214, 153, 0.75), transparent 35%),
          linear-gradient(180deg, #fffaf2 0%, #eef4ff 100%);
      }

      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
      }

      .page {
        min-height: 100vh;
        padding: 24px 16px 40px;
      }

      .panel {
        max-width: 880px;
        margin: 0 auto;
        background: rgba(255, 255, 255, 0.88);
        border: 1px solid rgba(16, 42, 67, 0.08);
        border-radius: 24px;
        box-shadow: 0 16px 48px rgba(16, 42, 67, 0.12);
        overflow: hidden;
      }

      .hero {
        padding: 28px 24px 18px;
        background: linear-gradient(135deg, #103d60 0%, #1d5f91 60%, #4d95c7 100%);
        color: #fff7ef;
      }

      .hero h1 {
        margin: 0;
        font-size: 28px;
        line-height: 1.1;
      }

      .hero p {
        margin: 10px 0 0;
        color: rgba(255, 247, 239, 0.88);
        line-height: 1.6;
      }

      .content {
        display: grid;
        gap: 18px;
        padding: 20px;
      }

      .card {
        padding: 18px;
        background: #ffffff;
        border: 1px solid rgba(16, 42, 67, 0.08);
        border-radius: 18px;
      }

      .card h2 {
        margin: 0 0 12px;
        font-size: 16px;
      }

      .summary {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
        gap: 12px;
      }

      .metric {
        padding: 12px;
        border-radius: 14px;
        background: #f7fbff;
      }

      .metric strong {
        display: block;
        font-size: 12px;
        color: #486581;
        margin-bottom: 6px;
      }

      .metric span {
        font-size: 14px;
        word-break: break-word;
      }

      .controls {
        display: grid;
        gap: 12px;
      }

      .toolbar {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
        gap: 10px;
      }

      button,
      select {
        width: 100%;
        min-height: 44px;
        border-radius: 12px;
        border: 1px solid rgba(16, 42, 67, 0.16);
        font-size: 14px;
      }

      button {
        background: linear-gradient(180deg, #fff2d8 0%, #ffd77c 100%);
        color: #5a3d00;
        font-weight: 600;
      }

      button[disabled] {
        opacity: 0.48;
      }

      select {
        background: #fff;
        padding: 0 12px;
      }

      .hint {
        margin: 0;
        color: #486581;
        line-height: 1.6;
      }

      pre {
        margin: 0;
        padding: 14px;
        border-radius: 14px;
        background: #0f172a;
        color: #d7e3fc;
        overflow: auto;
        white-space: pre-wrap;
        word-break: break-word;
      }
    </style>
    <div class="page">
      <div class="panel">
        <section class="hero">
          <h1>Label Printer 真机联调页</h1>
          <p>用于验证 QR-365 等标签打印机的扫描、连接、状态查询、打印与断开流程。</p>
        </section>
        <div class="content">
          <section class="card">
            <h2>当前概览</h2>
            <div class="summary">
              <div class="metric">
                <strong>平台支持</strong>
                <span>${state.supported === null ? '检测中' : state.supported ? '支持' : '不支持'}</span>
              </div>
              <div class="metric">
                <strong>连接状态</strong>
                <span>${escapeHtml(state.connectionState)}</span>
              </div>
              <div class="metric">
                <strong>已连接设备</strong>
                <span>${escapeHtml(selectedDevice?.name ?? state.connectedDeviceId ?? '未连接')}</span>
              </div>
              <div class="metric">
                <strong>忙碌动作</strong>
                <span>${escapeHtml(state.busyAction ?? '空闲')}</span>
              </div>
              <div class="metric">
                <strong>蓝牙权限</strong>
                <span>${escapeHtml(permissionSummary)}</span>
              </div>
            </div>
          </section>

          <section class="card controls">
            <h2>设备操作</h2>
            <select id="device-select">
              <option value="">${state.devices.length ? '请选择设备' : '请先点击扫描'}</option>
              ${state.devices
                .map(
                  (device) => `
                    <option value="${escapeHtml(device.id)}" ${
                      device.id === state.selectedDeviceId ? 'selected' : ''
                    }>
                      ${escapeHtml(device.name)}${device.rssi !== undefined ? ` · RSSI ${device.rssi}` : ''}
                    </option>
                  `,
                )
                .join('')}
            </select>
            <div class="toolbar">
              <button data-action="scan" ${isBusy ? 'disabled' : ''}>扫描</button>
              <button data-action="connect" ${canConnect ? '' : 'disabled'}>连接</button>
              <button data-action="status" ${isBusy ? 'disabled' : ''}>状态</button>
              <button data-action="print" ${canPrint ? '' : 'disabled'}>打印</button>
              <button data-action="disconnect" ${canDisconnect ? '' : 'disabled'}>断开</button>
              ${canOpenSettings ? '<button data-action="settings">去设置开启权限</button>' : ''}
            </div>
            <p class="hint">
              首次扫描会自动申请蓝牙权限。Android 建议先到系统蓝牙完成配对；如果权限曾被永久拒绝，可使用“去设置开启权限”按钮恢复。
            </p>
          </section>

          <section class="card">
            <h2>最近状态</h2>
            <pre>${toPrettyJson(
              state.status ?? {
                selectedDeviceId: state.selectedDeviceId || null,
                connectedDeviceId: state.connectedDeviceId,
                devices: state.devices,
                permissionResult: state.permissionResult,
              },
            )}</pre>
          </section>

          <section class="card">
            <h2>操作日志</h2>
            <pre>${escapeHtml(state.logs.join('\n') || '暂无日志')}</pre>
          </section>
        </div>
      </div>
    </div>
  `;
}

async function main() {
  const app = document.querySelector<HTMLDivElement>('#app');
  if (!app) {
    return;
  }

  const controller = createDemoController(LabelPrinter, buildTestPayload);

  controller.subscribe((state) => {
    app.innerHTML = render(state);
  });

  app.addEventListener('change', (event) => {
    const target = event.target;
    if (!(target instanceof HTMLSelectElement) || target.id !== 'device-select') {
      return;
    }

    controller.selectDevice(target.value);
  });

  app.addEventListener('click', async (event) => {
    const target = event.target;
    if (!(target instanceof HTMLElement)) {
      return;
    }

    const action = target.closest<HTMLElement>('[data-action]')?.dataset.action;
    if (!action) {
      return;
    }

    try {
      if (action === 'scan') {
        await controller.scan();
      } else if (action === 'connect') {
        await controller.connectSelected();
      } else if (action === 'status') {
        await controller.refreshStatus();
      } else if (action === 'print') {
        await controller.printTestLabel();
      } else if (action === 'disconnect') {
        await controller.disconnect();
      } else if (action === 'settings') {
        await controller.openSettings();
      }
    } catch {
      // 控制器里已经统一记录错误日志，这里只避免未处理异常冒泡。
    }
  });

  try {
    await controller.init();
  } catch {
    // 控制器里已经统一记录错误日志，这里只避免未处理异常冒泡。
  }
}

main();
