package com.m430.capacitor.labelprinter;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import android.bluetooth.BluetoothDevice;
import com.printer.psdk.device.adapter.ReadOptions;
import com.printer.psdk.device.adapter.types.ConnectionState;
import com.printer.psdk.device.bluetooth.Connection;
import java.io.IOException;
import org.junit.Test;

public class VendorAndroidPrinterSessionTest {

    @Test
    public void printUsesTsplTransportInsteadOfDirectConnectionWrite() throws Exception {
        FakeConnection connection = new FakeConnection();
        FakeTsplTransport transport = new FakeTsplTransport();
        VendorAndroidPrinterSession session = new VendorAndroidPrinterSession(connection, transport);

        byte[] payload = "SIZE 75 mm,130 mm\nPRINT 1,1\n".getBytes();
        session.print("tspl", payload);

        assertArrayEquals(payload, transport.lastPayload);
        assertEquals(0, connection.writeCalls);
    }

    @Test(expected = IOException.class)
    public void printPropagatesTsplTransportFailure() throws Exception {
        FakeConnection connection = new FakeConnection();
        FakeTsplTransport transport = new FakeTsplTransport();
        transport.writeException = new IOException("write failed");
        VendorAndroidPrinterSession session = new VendorAndroidPrinterSession(connection, transport);

        session.print("tspl", "PRINT 1,1\n".getBytes());
    }

    @Test
    public void printUsesDirectConnectionWriteForCpclLanguage() throws Exception {
        FakeConnection connection = new FakeConnection();
        FakeTsplTransport transport = new FakeTsplTransport();
        VendorAndroidPrinterSession session = new VendorAndroidPrinterSession(connection, transport);

        byte[] payload = "! 0 200 200 640 1\nPRINT\n".getBytes();
        session.print("cpcl", payload);

        assertEquals(1, connection.writeCalls);
        assertArrayEquals(payload, connection.lastWrittenPayload);
        assertEquals(null, transport.lastPayload);
    }

    @Test
    public void queryStatusSkipsTsplCommandAfterCpclPrint() throws Exception {
        FakeConnection connection = new FakeConnection();
        FakeTsplTransport transport = new FakeTsplTransport();
        VendorAndroidPrinterSession session = new VendorAndroidPrinterSession(connection, transport);

        session.print("cpcl", "! 0 200 200 640 1\nPRINT\n".getBytes());
        byte[] result = session.queryStatus();

        assertNull(result);
        assertEquals(0, transport.queryStatusCalls);
    }

    @Test
    public void queryStatusUsesTsplTransportAfterTsplPrint() throws Exception {
        FakeConnection connection = new FakeConnection();
        FakeTsplTransport transport = new FakeTsplTransport();
        transport.queryStatusReturnValue = "READY".getBytes();
        VendorAndroidPrinterSession session = new VendorAndroidPrinterSession(connection, transport);

        session.print("tspl", "SIZE 75 mm,130 mm\nPRINT 1,1\n".getBytes());
        byte[] result = session.queryStatus();

        assertArrayEquals("READY".getBytes(), result);
        assertEquals(1, transport.queryStatusCalls);
    }

    @Test
    public void queryStatusUsesTsplTransportByDefaultBeforeAnyPrint() throws Exception {
        FakeConnection connection = new FakeConnection();
        FakeTsplTransport transport = new FakeTsplTransport();
        transport.queryStatusReturnValue = "READY".getBytes();
        VendorAndroidPrinterSession session = new VendorAndroidPrinterSession(connection, transport);

        byte[] result = session.queryStatus();

        assertArrayEquals("READY".getBytes(), result);
        assertEquals(1, transport.queryStatusCalls);
    }

    private static final class FakeTsplTransport implements VendorAndroidPrinterSession.TsplTransport {
        private byte[] lastPayload;
        private IOException writeException;
        private int queryStatusCalls;
        private byte[] queryStatusReturnValue;

        @Override
        public void send(byte[] payload) throws IOException {
            if (writeException != null) {
                throw writeException;
            }
            lastPayload = payload;
        }

        @Override
        public byte[] queryStatus() {
            queryStatusCalls++;
            return queryStatusReturnValue;
        }
    }

    private static final class FakeConnection extends Connection {
        private int writeCalls;
        private byte[] lastWrittenPayload;

        @Override
        public void setState(int state) {
        }

        @Override
        public boolean isReleased() {
            return false;
        }

        @Override
        public boolean isConnected() {
            return true;
        }

        @Override
        public BluetoothDevice getDevice() {
            return null;
        }

        @Override
        public boolean connect(java.util.UUID uuid) {
            return true;
        }

        @Override
        public void disconnect() {
        }

        @Override
        public void release() {
        }

        @Override
        public int getState() {
            return Connection.STATE_CONNECTED;
        }

        @Override
        public String deviceName() {
            return "QR-365";
        }

        @Override
        public ConnectionState connectionState() {
            return null;
        }

        @Override
        public void write(byte[] bytes) {
            writeCalls++;
            lastWrittenPayload = bytes;
        }

        @Override
        public byte[] read(ReadOptions readOptions) {
            return null;
        }
    }
}
