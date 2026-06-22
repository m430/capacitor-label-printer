package com.m430.capacitor.labelprinter;

import static org.junit.Assert.assertEquals;

import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import java.lang.reflect.Method;
import org.junit.Test;

public class LabelPrinterPluginTest {

    @Test
    public void buildPermissionResultMarksSettingsWhenPermissionDenied() throws Exception {
        Method method = LabelPrinterPlugin.class.getDeclaredMethod(
            "buildPermissionResult",
            PermissionState.class,
            PermissionState.class
        );
        method.setAccessible(true);

        JSObject result = (JSObject) method.invoke(null, PermissionState.GRANTED, PermissionState.DENIED);
        JSObject permissions = result.getJSObject("permissions");

        assertEquals(false, result.getBool("granted"));
        assertEquals(false, result.getBool("canPrompt"));
        assertEquals(true, result.getBool("shouldOpenSettings"));
        assertEquals("denied", permissions.getString("bluetooth"));
        assertEquals("granted", permissions.getString("bluetoothConnect"));
        assertEquals("denied", permissions.getString("bluetoothScan"));
    }
}
