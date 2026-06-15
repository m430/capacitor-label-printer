package com.m430.capacitor.labelprinter;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.util.ArrayList;
import java.util.List;

@CapacitorPlugin(name = "LabelPrinter")
public class LabelPrinterPlugin extends Plugin {
    private final AndroidPrinterManager manager = new AndroidPrinterManager();

    @PluginMethod
    public void isSupported(PluginCall call) {
        JSObject result = new JSObject();
        result.put("supported", true);
        call.resolve(result);
    }

    @PluginMethod
    public void ensurePermissions(PluginCall call) {
        JSObject result = new JSObject();
        result.put("granted", true);
        call.resolve(result);
    }

    @PluginMethod
    public void discoverDevices(PluginCall call) {
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

        JSObject result = new JSObject();
        result.put("devices", manager.getBondedDevices(prefixes));
        call.resolve(result);
    }

    @PluginMethod
    public void connect(PluginCall call) {
        manager.connect(call.getString("deviceId"));
        call.resolve();
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
        String payload = call.getString("payload", "");
        Integer copiesValue = call.getInt("copies", 1);
        int copies = copiesValue != null ? copiesValue : 1;
        manager.print(payload, copies);
        call.resolve();
    }

    @PluginMethod
    public void getStatus(PluginCall call) {
        call.resolve(manager.getStatus());
    }
}
