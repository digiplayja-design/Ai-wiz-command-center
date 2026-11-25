package com.korlixdeveloper.fax;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle state) {
        registerPlugin(FaxFiles.class);
        super.onCreate(state);
    }
}
