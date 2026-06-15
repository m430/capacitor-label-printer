package com.m430.capacitor.labelprinter;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Set;

public class AndroidPrinterManager {
    private final BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
    private final AndroidStatusMapper statusMapper = new AndroidStatusMapper();
    private boolean connected = false;
    private String connectedDeviceId;

    public JSArray getBondedDevices(List<String> prefixes) {
        JSArray devices = new JSArray();
        if (adapter == null) {
            return devices;
        }

        Set<BluetoothDevice> bonded = adapter.getBondedDevices();
        for (BluetoothDevice device : bonded) {
            if (!matchesPrefix(device.getName(), prefixes)) {
                continue;
            }
            JSObject item = new JSObject();
            item.put("id", device.getAddress());
            item.put("name", device.getName());
            item.put("address", device.getAddress());
            item.put("transport", "classic");
            item.put("bonded", true);
            devices.put(item);
        }
        return devices;
    }

    public void connect(String deviceId) {
        this.connected = true;
        this.connectedDeviceId = deviceId;
    }

    public void disconnect() {
        this.connected = false;
        this.connectedDeviceId = null;
    }

    public void print(String payload, int copies) {
        byte[] bytes = payload.repeat(Math.max(copies, 1)).getBytes(StandardCharsets.UTF_8);
        if (bytes.length == 0) {
            throw new IllegalArgumentException("payload is empty");
        }
        if (!connected) {
            throw new IllegalStateException("printer is not connected");
        }
    }

    public JSObject getConnectionState() {
        JSObject state = new JSObject();
        state.put("state", connected ? "connected" : "disconnected");
        return state;
    }

    public JSObject getStatus() {
        return statusMapper.toPluginStatus(
            connected,
            connected ? AndroidStatusMapper.STATE_READY : AndroidStatusMapper.STATE_PAPER_OUT,
            connected ? "ready" : "disconnected"
        );
    }

    private boolean matchesPrefix(String value, List<String> prefixes) {
        if (value == null) {
            return false;
        }
        if (prefixes == null || prefixes.isEmpty()) {
            return true;
        }
        for (String prefix : prefixes) {
            if (value.startsWith(prefix)) {
                return true;
            }
        }
        return false;
    }
}
