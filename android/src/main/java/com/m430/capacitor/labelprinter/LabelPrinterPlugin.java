package com.m430.capacitor.labelprinter;

import android.Manifest;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;
import java.util.ArrayList;
import java.util.List;

@CapacitorPlugin(
    name = "LabelPrinter",
    permissions = {
        @Permission(alias = "bluetoothConnect", strings = { Manifest.permission.BLUETOOTH_CONNECT }),
        @Permission(alias = "bluetoothScan", strings = { Manifest.permission.BLUETOOTH_SCAN })
    }
)
public class LabelPrinterPlugin extends Plugin {
    private static final String BLUETOOTH_CONNECT_ALIAS = "bluetoothConnect";
    private static final String BLUETOOTH_SCAN_ALIAS = "bluetoothScan";
    private static final String[] DISCOVERY_PERMISSION_ALIASES = new String[] {
        BLUETOOTH_CONNECT_ALIAS,
        BLUETOOTH_SCAN_ALIAS
    };
    private static final String[] CONNECTION_PERMISSION_ALIASES = new String[] { BLUETOOTH_CONNECT_ALIAS };
    private static final String PERMISSION_DENIED_CODE = "PERMISSION_DENIED";
    private AndroidPrinterManager manager;

    @Override
    public void load() {
        manager = new AndroidPrinterManager(new VendorAndroidDeviceCatalog(getContext()), new AndroidStatusMapper());
    }

    @PluginMethod
    public void isSupported(PluginCall call) {
        JSObject result = new JSObject();
        result.put("supported", true);
        call.resolve(result);
    }

    @PluginMethod
    @Override
    public void checkPermissions(PluginCall call) {
        call.resolve(buildPermissionResult(currentBluetoothConnectState(), currentBluetoothScanState()));
    }

    @PluginMethod
    public void ensurePermissions(PluginCall call) {
        if (hasPermissionAliases(DISCOVERY_PERMISSION_ALIASES)) {
            call.resolve(buildPermissionResult(currentBluetoothConnectState(), currentBluetoothScanState()));
            return;
        }

        if (!requiresNearbyDevicesPermission()) {
            call.resolve(buildPermissionResult(PermissionState.GRANTED, PermissionState.GRANTED));
            return;
        }

        requestPermissionForAliases(DISCOVERY_PERMISSION_ALIASES, call, "ensurePermissionsCallback");
    }

    @PluginMethod
    public void discoverDevices(PluginCall call) {
        if (!hasPermissionAliases(DISCOVERY_PERMISSION_ALIASES)) {
            if (!requiresNearbyDevicesPermission()) {
                performDiscoverDevices(call);
                return;
            }

            requestPermissionForAliases(DISCOVERY_PERMISSION_ALIASES, call, "discoverDevicesPermissionCallback");
            return;
        }

        performDiscoverDevices(call);
    }

    @PluginMethod
    public void connect(PluginCall call) {
        if (!hasPermissionAliases(CONNECTION_PERMISSION_ALIASES)) {
            if (!requiresNearbyDevicesPermission()) {
                performConnect(call);
                return;
            }

            requestPermissionForAliases(CONNECTION_PERMISSION_ALIASES, call, "connectPermissionCallback");
            return;
        }

        performConnect(call);
    }

    @PluginMethod
    public void disconnect(PluginCall call) {
        manager.disconnect();
        call.resolve();
    }

    @PluginMethod
    public void getConnectionState(PluginCall call) {
        call.resolve(manager.getConnectionState());
    }

    @PluginMethod
    public void print(PluginCall call) {
        if (!hasPermissionAliases(CONNECTION_PERMISSION_ALIASES)) {
            rejectPermissionCall(call);
            return;
        }

        String payload = call.getString("payload", "");
        String language = call.getString("language", "tspl");
        Integer copiesValue = call.getInt("copies", 1);
        int copies = copiesValue != null ? copiesValue : 1;
        try {
            manager.print(payload, language, copies);
            call.resolve();
        } catch (Exception exception) {
            call.reject(exception.getMessage(), exception);
        }
    }

    @PluginMethod
    public void getStatus(PluginCall call) {
        call.resolve(manager.getStatus());
    }

    @PluginMethod
    public void openAppSettings(PluginCall call) {
        Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        intent.setData(Uri.fromParts("package", getContext().getPackageName(), null));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().startActivity(intent);
        call.resolve();
    }

    @PermissionCallback
    private void ensurePermissionsCallback(PluginCall call) {
        call.resolve(buildPermissionResult(currentBluetoothConnectState(), currentBluetoothScanState()));
    }

    @PermissionCallback
    private void discoverDevicesPermissionCallback(PluginCall call) {
        if (!hasPermissionAliases(DISCOVERY_PERMISSION_ALIASES)) {
            rejectPermissionCall(call);
            return;
        }

        performDiscoverDevices(call);
    }

    @PermissionCallback
    private void connectPermissionCallback(PluginCall call) {
        if (!hasPermissionAliases(CONNECTION_PERMISSION_ALIASES)) {
            rejectPermissionCall(call);
            return;
        }

        performConnect(call);
    }

    private void performDiscoverDevices(PluginCall call) {
        JSArray prefixesArray = call.getArray("namePrefixes");
        List<String> prefixes = new ArrayList<>();
        if (prefixesArray != null) {
            for (int index = 0; index < prefixesArray.length(); index++) {
                String item = prefixesArray.optString(index, null);
                if (item != null) {
                    prefixes.add(item);
                }
            }
        }

        try {
            JSObject result = new JSObject();
            result.put("devices", manager.getBondedDevices(prefixes));
            call.resolve(result);
        } catch (Exception exception) {
            call.reject(exception.getMessage(), exception);
        }
    }

    private void performConnect(PluginCall call) {
        try {
            manager.connect(call.getString("deviceId"));
            call.resolve();
        } catch (Exception exception) {
            call.reject(exception.getMessage(), exception);
        }
    }

    private void rejectPermissionCall(PluginCall call) {
        call.reject(
            "需要附近设备权限才能扫描、连接和打印蓝牙标签机",
            PERMISSION_DENIED_CODE,
            buildPermissionResult(currentBluetoothConnectState(), currentBluetoothScanState())
        );
    }

    private boolean requiresNearbyDevicesPermission() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S;
    }

    private PermissionState currentBluetoothConnectState() {
        if (!requiresNearbyDevicesPermission()) {
            return PermissionState.GRANTED;
        }
        return getPermissionState(BLUETOOTH_CONNECT_ALIAS);
    }

    private PermissionState currentBluetoothScanState() {
        if (!requiresNearbyDevicesPermission()) {
            return PermissionState.GRANTED;
        }
        return getPermissionState(BLUETOOTH_SCAN_ALIAS);
    }

    private boolean hasPermissionAliases(String[] aliases) {
        if (!requiresNearbyDevicesPermission()) {
            return true;
        }
        for (String alias : aliases) {
            if (getPermissionState(alias) != PermissionState.GRANTED) {
                return false;
            }
        }
        return true;
    }

    private static PermissionState aggregateBluetoothState(PermissionState bluetoothConnect, PermissionState bluetoothScan) {
        if (bluetoothConnect == PermissionState.DENIED || bluetoothScan == PermissionState.DENIED) {
            return PermissionState.DENIED;
        }
        if (
            bluetoothConnect == PermissionState.PROMPT_WITH_RATIONALE ||
            bluetoothScan == PermissionState.PROMPT_WITH_RATIONALE
        ) {
            return PermissionState.PROMPT_WITH_RATIONALE;
        }
        if (bluetoothConnect == PermissionState.PROMPT || bluetoothScan == PermissionState.PROMPT) {
            return PermissionState.PROMPT;
        }
        return PermissionState.GRANTED;
    }

    private static boolean canPrompt(PermissionState state) {
        return state == PermissionState.PROMPT || state == PermissionState.PROMPT_WITH_RATIONALE;
    }

    private static JSObject buildPermissionResult(PermissionState bluetoothConnect, PermissionState bluetoothScan) {
        PermissionState bluetooth = aggregateBluetoothState(bluetoothConnect, bluetoothScan);

        JSObject permissions = new JSObject();
        permissions.put("bluetoothConnect", bluetoothConnect.toString());
        permissions.put("bluetoothScan", bluetoothScan.toString());
        permissions.put("bluetooth", bluetooth.toString());

        JSObject result = new JSObject();
        result.put("granted", bluetooth == PermissionState.GRANTED);
        result.put("canPrompt", canPrompt(bluetooth));
        result.put("shouldOpenSettings", bluetooth != PermissionState.GRANTED && !canPrompt(bluetooth));
        result.put("permissions", permissions);
        return result;
    }
}
