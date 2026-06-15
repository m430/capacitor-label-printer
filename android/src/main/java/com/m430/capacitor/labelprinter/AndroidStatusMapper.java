package com.m430.capacitor.labelprinter;

import com.getcapacitor.JSObject;
import org.json.JSONException;

public class AndroidStatusMapper {
    public static final int STATE_READY = 0;
    public static final int STATE_PAPER_OUT = 1;
    public static final int STATE_COVER_OPEN = 2;
    public static final int STATE_OVERHEATING = 3;

    public JSObject toPluginStatus(boolean connected, int stateCode, String message) {
        String messageValue = message == null
            ? "null"
            : "\"" + message.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
        String payload = "{"
            + "\"connected\":" + connected + ","
            + "\"ready\":" + (stateCode == STATE_READY) + ","
            + "\"paperOut\":" + (stateCode == STATE_PAPER_OUT) + ","
            + "\"coverOpen\":" + (stateCode == STATE_COVER_OPEN) + ","
            + "\"overheating\":" + (stateCode == STATE_OVERHEATING) + ","
            + "\"message\":" + messageValue + ","
            + "\"raw\":" + stateCode
            + "}";

        try {
            return new JSObject(payload);
        } catch (JSONException exception) {
            throw new IllegalStateException("Failed to map printer status", exception);
        }
    }
}
