package com.m430.capacitor.labelprinter;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;

public class AndroidPrinterManager {
    interface DeviceCatalog {
        JSArray discover(List<String> prefixes);

        PrinterSession openSession(String deviceId);
    }

    interface PrinterSession {
        void connect() throws IOException;

        void disconnect();

        boolean isConnected();

        String getConnectionState();

        String getDeviceName();

        void print(byte[] payload) throws IOException;

        byte[] queryStatus() throws IOException;
    }

    private final DeviceCatalog deviceCatalog;
    private final AndroidStatusMapper statusMapper;
    private PrinterSession session;
    private String connectedDeviceId;

    public AndroidPrinterManager(DeviceCatalog deviceCatalog, AndroidStatusMapper statusMapper) {
        this.deviceCatalog = deviceCatalog;
        this.statusMapper = statusMapper;
    }

    public JSArray getBondedDevices(List<String> prefixes) {
        return deviceCatalog.discover(prefixes);
    }

    public void connect(String deviceId) throws IOException {
        if (deviceId == null || deviceId.trim().isEmpty()) {
            throw new IllegalArgumentException("deviceId is required");
        }

        PrinterSession nextSession = deviceCatalog.openSession(deviceId);
        if (nextSession == null) {
            throw new IllegalArgumentException("printer device not found: " + deviceId);
        }

        disconnect();
        nextSession.connect();
        session = nextSession;
        connectedDeviceId = deviceId;
    }

    public void disconnect() {
        if (session != null) {
            session.disconnect();
        }
        session = null;
        connectedDeviceId = null;
    }

    public void print(String payload, int copies) throws IOException {
        if (payload == null || payload.isEmpty()) {
            throw new IllegalArgumentException("payload is empty");
        }
        PrinterSession activeSession = requireSession();
        activeSession.print(payload.repeat(Math.max(copies, 1)).getBytes(StandardCharsets.UTF_8));
    }

    public JSObject getConnectionState() {
        JSObject state = new JSObject();
        state.put("state", session == null ? "disconnected" : session.getConnectionState());
        return state;
    }

    public JSObject getStatus() {
        if (session == null || !session.isConnected()) {
            return statusMapper.disconnected("disconnected");
        }

        JSObject status = statusMapper.toPluginStatus(true, AndroidStatusMapper.STATE_READY, "ready");
        status.put("deviceId", connectedDeviceId);
        status.put("deviceName", session.getDeviceName());

        try {
            byte[] response = session.queryStatus();
            if (response != null && response.length > 0) {
                String rawText = new String(response, StandardCharsets.UTF_8).trim();
                if (!rawText.isEmpty()) {
                    status.put("raw", rawText);
                    status.put("message", rawText);
                    applyStatusHints(status, rawText);
                }
            }
        } catch (IOException exception) {
            status.put("message", exception.getMessage());
        }

        return status;
    }

    private PrinterSession requireSession() {
        if (session == null || !session.isConnected()) {
            throw new IllegalStateException("printer is not connected");
        }
        return session;
    }

    private void applyStatusHints(JSObject status, String rawText) {
        String normalized = rawText.toUpperCase();
        if (normalized.contains("PAPER")) {
            status.put("ready", false);
            status.put("paperOut", true);
        }
        if (normalized.contains("COVER") || normalized.contains("OPEN")) {
            status.put("ready", false);
            status.put("coverOpen", true);
        }
        if (normalized.contains("HEAT")) {
            status.put("ready", false);
            status.put("overheating", true);
        }
    }
}
