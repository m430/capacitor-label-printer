package com.m430.capacitor.labelprinter;

import android.bluetooth.BluetoothDevice;
import com.printer.psdk.device.adapter.ConnectedDevice;
import com.printer.psdk.device.adapter.ReadOptions;
import com.printer.psdk.device.adapter.types.WroteReporter;
import com.printer.psdk.device.bluetooth.Bluetooth;
import com.printer.psdk.device.bluetooth.ConnectListener;
import com.printer.psdk.device.bluetooth.Connection;
import com.printer.psdk.tspl.GenericTSPL;
import com.printer.psdk.tspl.TSPL;
import java.io.IOException;

final class VendorAndroidPrinterSession implements AndroidPrinterManager.PrinterSession {
    private final Connection connection;
    private final VendorConnectListener listener = new VendorConnectListener();

    VendorAndroidPrinterSession(Bluetooth bluetooth, BluetoothDevice device) {
        connection = bluetooth.createConnectionClassic(device, listener);
    }

    @Override
    public void connect() throws IOException {
        if (connection == null) {
            throw new IOException("unable to create classic bluetooth connection");
        }

        boolean success = connection.connect(null);
        if (!success || !connection.isConnected()) {
            throw new IOException(listener.lastErrorMessage != null ? listener.lastErrorMessage : "connect failed");
        }
    }

    @Override
    public void disconnect() {
        if (connection != null) {
            connection.disconnect();
        }
    }

    @Override
    public boolean isConnected() {
        return connection != null && connection.isConnected();
    }

    @Override
    public String getConnectionState() {
        if (connection == null) {
            return "disconnected";
        }

        switch (connection.getState()) {
            case Connection.STATE_CONNECTING:
            case Connection.STATE_PAIRING:
            case Connection.STATE_PAIRED:
                return "connecting";
            case Connection.STATE_CONNECTED:
                return "connected";
            default:
                return "disconnected";
        }
    }

    @Override
    public String getDeviceName() {
        if (connection == null || connection.getDevice() == null) {
            return null;
        }
        return connection.getDevice().getName();
    }

    @Override
    public void print(byte[] payload) throws IOException {
        if (connection == null) {
            throw new IOException("printer connection is unavailable");
        }
        connection.write(payload);
    }

    @Override
    public byte[] queryStatus() throws IOException {
        if (connection == null) {
            return null;
        }

        GenericTSPL tspl = TSPL.generic(connection).state();
        WroteReporter reporter = tspl.write();
        if (!reporter.isOk()) {
            throw new IOException(
                reporter.getException() != null ? reporter.getException().getMessage() : "failed to query printer status",
                reporter.getException()
            );
        }
        return tspl.read(ReadOptions.builder().timeout(1500).build());
    }

    private static final class VendorConnectListener implements ConnectListener {
        private String lastErrorMessage;

        @Override
        public void onConnectSuccess(ConnectedDevice connectedDevice) {
            lastErrorMessage = null;
        }

        @Override
        public void onConnectFail(String errMsg, Throwable throwable) {
            if (throwable != null && throwable.getMessage() != null) {
                lastErrorMessage = errMsg + ": " + throwable.getMessage();
                return;
            }
            lastErrorMessage = errMsg;
        }

        @Override
        public void onConnectionStateChanged(BluetoothDevice device, int state) {
            // 状态直接从 Connection.getState() 读取，这里无需额外处理。
        }
    }
}
