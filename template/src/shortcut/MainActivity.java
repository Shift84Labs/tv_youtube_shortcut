package shortcut;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.Toast;

public class MainActivity extends Activity {
    private static final String URL = "__URL__";
    private static final String YT_PKG = "__YT_PKG__";
    private static final String YT_ACT = "__YT_ACT__";

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(URL));
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        // Pin to a specific YouTube app. Several packages claim youtube.com URLs
        // (tv / tvunplugged / tvmusic on Google TV), and an unpinned intent raises
        // an app chooser instead of playing.
        i.setClassName(YT_PKG, YT_ACT);
        try {
            startActivity(i);
        } catch (ActivityNotFoundException e) {
            // Wrong target package for this device, or YouTube is not installed.
            // Fall back to an unpinned intent so the user gets a chooser, not nothing.
            try {
                startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(URL))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            } catch (ActivityNotFoundException e2) {
                Toast.makeText(this, "No YouTube app found", Toast.LENGTH_LONG).show();
            }
        }
        finish();
    }
}
