package com.korlixdeveloper.fax;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import androidx.activity.result.ActivityResult;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.ActivityCallback;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.OutputStream;

@CapacitorPlugin(name = "FaxFiles")
public class FaxFiles extends Plugin {
    private File exportFile(PluginCall call) throws IOException {
        Uri uri = Uri.parse(call.getString("uri", ""));
        if (!"file".equals(uri.getScheme()) || uri.getPath() == null) throw new IOException();
        File file = new File(uri.getPath()).getCanonicalFile();
        File exports = new File(getContext().getCacheDir(), "fax-exports").getCanonicalFile();
        if (!file.getPath().startsWith(exports.getPath() + File.separator) || !file.isFile()) throw new IOException();
        return file;
    }

    @PluginMethod
    public void save(PluginCall call) {
        try {
            File file = exportFile(call);
            String name = file.getName();
            String mime = name.toLowerCase(java.util.Locale.ROOT).endsWith(".csv") ? "text/csv" : "application/pdf";
            Intent picker = new Intent(Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType(mime)
                .putExtra(Intent.EXTRA_TITLE, name);
            startActivityForResult(call, picker, "finishSave");
        } catch (Exception error) {
            call.reject("The file picker could not be opened.");
        }
    }

    @ActivityCallback
    private void finishSave(PluginCall call, ActivityResult result) {
        if (call == null) return;
        if (result.getResultCode() != Activity.RESULT_OK) {
            call.resolve();
            return;
        }
        Uri destination = result.getData() == null ? null : result.getData().getData();
        if (destination == null || !"content".equals(destination.getScheme())) {
            call.reject("Choose a writable destination.");
            return;
        }
        getBridge().execute(() -> {
            try (FileInputStream input = new FileInputStream(exportFile(call));
                 OutputStream output = getContext().getContentResolver().openOutputStream(destination, "wt")) {
                if (output == null) throw new IOException();
                byte[] buffer = new byte[32768];
                int count;
                while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            } catch (IOException | SecurityException error) {
                call.reject("The file could not be saved to this destination.");
                return;
            }
            call.resolve();
        });
    }
}
