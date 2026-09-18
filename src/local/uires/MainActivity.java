package local.uires;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.os.IBinder;
import android.provider.Settings;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Switches the forced UI resolution of display 0. Same effect as
 * `adb shell wm size WxH`, applied live through IWindowManager.
 * Needs WRITE_SECURE_SETTINGS granted via adb.
 *
 * Density is deliberately NOT touched: this HiSilicon/Newlink ROM has an
 * ActivityManager hook (adjustDisplayDensityForPackage) that wipes
 * display_density_forced on every activity switch. Presets are therefore
 * chosen so the dp space stays sane at the fixed 240 dpi:
 *   1920x1080 -> 1280x720 dp (native)
 *   1440x810  ->  960x540 dp (canonical Android TV layout size)
 *   1280x720  ->  853x480 dp (fastest, slightly below canonical)
 * Video playback is unaffected (hardware overlay at native resolution).
 */
public class MainActivity extends Activity {

    private static final String TAG = "uires";
    private static final int DISPLAY_ID = 0;

    private static final int[][] PRESETS = {
            {0, 0},        // native
            {1440, 810},
            {1280, 720},
    };
    private static final String[] LABELS = {
            "1920×1080  — родное",
            "1440×810  — оптимально (960×540 dp)",
            "1280×720  — максимум скорости",
    };

    private TextView status;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        int pad = dp(24);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("Разрешение интерфейса");
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22);
        title.setTextColor(Color.WHITE);
        root.addView(title);

        status = new TextView(this);
        status.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        status.setPadding(0, dp(8), 0, dp(16));
        root.addView(status);

        int current = currentPreset();
        Button focus = null;
        for (int i = 0; i < PRESETS.length; i++) {
            final int idx = i;
            Button b = new Button(this);
            b.setText((i == current ? "●  " : "") + LABELS[i]);
            b.setAllCaps(false);
            b.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) { apply(PRESETS[idx][0], PRESETS[idx][1]); }
            });
            root.addView(b, buttonParams());
            // Focus the next preset after the current one so a single OK press cycles.
            if (i == (current + 1) % PRESETS.length) focus = b;
        }

        setContentView(root);
        status.setText("Сейчас: " + LABELS[current].split(" ")[0]);
        if (focus != null) focus.requestFocus();
    }

    private int currentPreset() {
        String forced = Settings.Global.getString(getContentResolver(), "display_size_forced");
        if (forced == null || forced.isEmpty()) return 0;
        for (int i = 1; i < PRESETS.length; i++) {
            if (forced.startsWith(PRESETS[i][0] + ",")) return i;
        }
        return 0;
    }

    /** width/height 0 = clear forced size (back to native). */
    private void apply(int w, int h) {
        try {
            IBinder binder = (IBinder) Class.forName("android.os.ServiceManager")
                    .getMethod("getService", String.class).invoke(null, "window");
            Object wm = Class.forName("android.view.IWindowManager$Stub")
                    .getMethod("asInterface", IBinder.class).invoke(null, binder);
            Class<?> c = wm.getClass();
            if (w > 0) {
                c.getMethod("setForcedDisplaySize", int.class, int.class, int.class)
                        .invoke(wm, DISPLAY_ID, w, h);
            } else {
                c.getMethod("clearForcedDisplaySize", int.class).invoke(wm, DISPLAY_ID);
            }
            Toast.makeText(this, "Интерфейс: " + (w > 0 ? w + "×" + h : "1920×1080"), Toast.LENGTH_SHORT).show();
            finish();
        } catch (Exception e) {
            Throwable t = e.getCause() != null ? e.getCause() : e;
            Log.e(TAG, "apply failed", t);
            status.setText("Ошибка: " + t.getClass().getSimpleName() + ": " + t.getMessage()
                    + "\n\nВыдайте разрешение:\nadb shell pm grant local.uires android.permission.WRITE_SECURE_SETTINGS");
        }
    }

    private LinearLayout.LayoutParams buttonParams() {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(340), LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(8);
        return lp;
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }
}
