package com.m430.capacitor.labelprinter;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.Context;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.printer.psdk.device.bluetooth.Bluetooth;
import java.util.List;
import java.util.Set;

final class VendorAndroidDeviceCatalog implements AndroidPrinterManager.DeviceCatalog {
    private final Context appContext;
    private final Bluetooth bluetooth;
    private final BluetoothAdapter adapter;

    VendorAndroidDeviceCatalog(Context context) {
        appContext = context.getApplicationContext();
        bluetooth = Bluetooth.getInstance();
        bluetooth.initialize(appContext);
        adapter = BluetoothAdapter.getDefaultAdapter();
    }

    @Override
    @SuppressLint("MissingPermission")
    public JSArray discover(List<String> prefixes) {
        JSArray devices = new JSArray();
        if (adapter == null || !bluetooth.hasConnectPermission(appContext)) {
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

    @Override
    @SuppressLint("MissingPermission")
    public AndroidPrinterManager.PrinterSession openSession(String deviceId) {
        if (adapter == null || deviceId == null || !bluetooth.hasConnectPermission(appContext)) {
            return null;
        }

        for (BluetoothDevice device : adapter.getBondedDevices()) {
            if (deviceId.equalsIgnoreCase(device.getAddress())) {
                return new VendorAndroidPrinterSession(bluetooth, device);
            }
        }

        return null;
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
