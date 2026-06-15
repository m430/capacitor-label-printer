package com.m430.capacitor.labelprinter;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import com.getcapacitor.JSObject;
import org.junit.Test;

public class AndroidStatusMapperTest {

    @Test
    public void mapsReadyState() {
        AndroidStatusMapper mapper = new AndroidStatusMapper();
        JSObject status = mapper.toPluginStatus(true, AndroidStatusMapper.STATE_READY, "ready");
        assertTrue(status.getBool("connected"));
        assertTrue(status.getBool("ready"));
        assertEquals("ready", status.getString("message"));
    }

    @Test
    public void mapsPaperOutState() {
        AndroidStatusMapper mapper = new AndroidStatusMapper();
        JSObject status = mapper.toPluginStatus(true, AndroidStatusMapper.STATE_PAPER_OUT, "paper out");
        assertTrue(status.getBool("paperOut"));
        assertEquals("paper out", status.getString("message"));
    }
}
