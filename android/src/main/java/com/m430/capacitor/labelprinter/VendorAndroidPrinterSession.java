package com.m430.capacitor.labelprinter;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothDevice;
import com.printer.psdk.device.adapter.ConnectedDevice;
import com.printer.psdk.device.adapter.ReadOptions;
import com.printer.psdk.device.adapter.types.WroteReporter;
import com.printer.psdk.frame.father.args.common.Raw;
import com.printer.psdk.device.bluetooth.Bluetooth;
import com.printer.psdk.device.bluetooth.ConnectListener;
import com.printer.psdk.device.bluetooth.Connection;
import com.printer.psdk.tspl.GenericTSPL;
import com.printer.psdk.tspl.TSPL;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

final class VendorAndroidPrinterSession implements AndroidPrinterManager.PrinterSession {
    private static final int RAW_WRITE_CHUNK_SIZE = 1024;
    private static final int RAW_WRITE_CHUNK_DELAY_MS = 20;

    private final Connection connection;
    private final TsplTransport tsplTransport;
    private final VendorConnectListener listener = new VendorConnectListener();
    private String activeLanguage;

    VendorAndroidPrinterSession(Bluetooth bluetooth, BluetoothDevice device) {
        connection = bluetooth.createConnectionClassic(device, listener);
        tsplTransport = new SdkTsplTransport(connection);
    }

    VendorAndroidPrinterSession(Connection connection, TsplTransport tsplTransport) {
        this.connection = connection;
        this.tsplTransport = tsplTransport;
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
    @SuppressLint("MissingPermission")
    public String getDeviceName() {
        if (connection == null || connection.getDevice() == null) {
            return null;
        }
        return connection.getDevice().getName();
    }

    public void print(byte[] payload) throws IOException {
        print("tspl", payload);
    }

    @Override
    public void print(String language, byte[] payload) throws IOException {
        if (connection == null) {
            throw new IOException("printer connection is unavailable");
        }
        this.activeLanguage = language;
        if (isTsplLanguage(language)) {
            tsplTransport.send(payload);
            return;
        }
        writeRawPayload(payload);
    }

    private void writeRawPayload(byte[] payload) throws IOException {
        if (connection == null) {
            throw new IOException("printer connection is unavailable");
        }
        if (!connection.isConnected()) {
            throw new IOException("printer is not connected");
        }

        int offset = 0;
        while (offset < payload.length) {
            if (!connection.isConnected()) {
                throw new IOException("printer connection lost during write");
            }

            int length = Math.min(RAW_WRITE_CHUNK_SIZE, payload.length - offset);
            connection.write(Arrays.copyOfRange(payload, offset, offset + length));
            offset += length;

            if (offset < payload.length && RAW_WRITE_CHUNK_DELAY_MS > 0) {
                try {
                    Thread.sleep(RAW_WRITE_CHUNK_DELAY_MS);
                } catch (InterruptedException interruptedException) {
                    Thread.currentThread().interrupt();
                    throw new IOException("write interrupted", interruptedException);
                }
            }
        }
    }

    @Override
    public byte[] queryStatus() throws IOException {
        if (connection == null || !isTsplLanguage(activeLanguage)) {
            return null;
        }
        return tsplTransport.queryStatus();
    }

    interface TsplTransport {
        void send(byte[] payload) throws IOException;

        byte[] queryStatus() throws IOException;
    }

    static final class SdkTsplTransport implements TsplTransport {
        private final Connection connection;

        SdkTsplTransport(Connection connection) {
            this.connection = connection;
        }

        @Override
        public void send(byte[] payload) throws IOException {
            String[] commands = splitCommands(payload);
            if (commands.length == 0) {
                throw new IOException("tspl payload does not contain any printable commands");
            }

            GenericTSPL tspl = TSPL.generic(connection);
            for (String command : commands) {
                tspl.raw(Raw.builder().command(command, StandardCharsets.UTF_8).build());
            }
            requireReporterOk(tspl.write(), "failed to write tspl payload");
        }

        @Override
        public byte[] queryStatus() throws IOException {
            GenericTSPL tspl = TSPL.generic(connection).state();
            requireReporterOk(tspl.write(), "failed to query printer status");
            return tspl.read(ReadOptions.builder().timeout(1500).build());
        }

        static String[] splitCommands(byte[] payload) {
            return new String(payload, StandardCharsets.UTF_8)
                .replace("\r\n", "\n")
                .replace('\r', '\n')
                .lines()
                .map(String::trim)
                .filter(command -> !command.isEmpty())
                .toArray(String[]::new);
        }

        private static void requireReporterOk(WroteReporter reporter, String fallbackMessage) throws IOException {
            if (reporter.isOk()) {
                return;
            }

            throw new IOException(
                reporter.getException() != null ? reporter.getException().getMessage() : fallbackMessage,
                reporter.getException()
            );
        }
    }

    private static boolean isTsplLanguage(String language) {
        return language == null || language.trim().isEmpty() || "tspl".equalsIgnoreCase(language);
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
