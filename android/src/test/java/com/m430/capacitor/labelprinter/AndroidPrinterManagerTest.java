package com.m430.capacitor.labelprinter;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.Test;

public class AndroidPrinterManagerTest {

    @Test
    public void connectCreatesSessionAndUpdatesConnectionState() throws Exception {
        FakePrinterSession session = new FakePrinterSession();
        FakeDeviceCatalog catalog = new FakeDeviceCatalog(session);
        AndroidPrinterManager manager = new AndroidPrinterManager(catalog, new AndroidStatusMapper());

        manager.connect("AA:BB:CC");

        assertTrue(session.connectCalled);
        assertEquals("connected", manager.getConnectionState().getString("state"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void connectFailsWhenDeviceDoesNotExist() throws Exception {
        AndroidPrinterManager manager = new AndroidPrinterManager(new FakeDeviceCatalog(null), new AndroidStatusMapper());
        manager.connect("missing");
    }

    @Test
    public void printDelegatesExpandedPayloadToActiveSession() throws Exception {
        FakePrinterSession session = new FakePrinterSession();
        FakeDeviceCatalog catalog = new FakeDeviceCatalog(session);
        AndroidPrinterManager manager = new AndroidPrinterManager(catalog, new AndroidStatusMapper());
        manager.connect("AA:BB:CC");

        manager.print("TEST", "cpcl", 2);

        assertArrayEquals("TESTTEST".getBytes(StandardCharsets.UTF_8), session.lastPayload);
        assertEquals("cpcl", session.lastLanguage);
    }

    @Test
    public void disconnectedStatusDoesNotPretendPaperOut() {
        AndroidPrinterManager manager = new AndroidPrinterManager(new FakeDeviceCatalog(null), new AndroidStatusMapper());

        JSObject status = manager.getStatus();

        assertEquals(false, status.getBool("connected"));
        assertEquals(false, status.getBool("paperOut"));
        assertEquals("disconnected", status.getString("message"));
    }

    private static final class FakeDeviceCatalog implements AndroidPrinterManager.DeviceCatalog {
        private final Map<String, AndroidPrinterManager.PrinterSession> sessions = new HashMap<>();

        FakeDeviceCatalog(AndroidPrinterManager.PrinterSession session) {
            if (session != null) {
                sessions.put("AA:BB:CC", session);
            }
        }

        @Override
        public JSArray discover(List<String> prefixes) {
            return new JSArray();
        }

        @Override
        public AndroidPrinterManager.PrinterSession openSession(String deviceId) {
            return sessions.get(deviceId);
        }
    }

    private static final class FakePrinterSession implements AndroidPrinterManager.PrinterSession {
        private boolean connectCalled;
        private boolean connected;
        private byte[] lastPayload;
        private String lastLanguage;

        @Override
        public void connect() {
            connectCalled = true;
            connected = true;
        }

        @Override
        public void disconnect() {
            connected = false;
        }

        @Override
        public boolean isConnected() {
            return connected;
        }

        @Override
        public String getConnectionState() {
            return connected ? "connected" : "disconnected";
        }

        @Override
        public String getDeviceName() {
            return "QR-365";
        }

        @Override
        public void print(String language, byte[] payload) {
            lastLanguage = language;
            lastPayload = payload;
        }

        @Override
        public byte[] queryStatus() {
            return "READY".getBytes(StandardCharsets.UTF_8);
        }
    }
}
