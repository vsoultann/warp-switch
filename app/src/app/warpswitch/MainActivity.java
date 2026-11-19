package app.warpswitch;

import android.app.Activity;
import android.content.ComponentName;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.TileService;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

public class MainActivity extends Activity {
    private final Handler ui = new Handler(Looper.getMainLooper());
    private TextView state, detail, log;
    private Button toggle;
    private boolean busy, on;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        float d = getResources().getDisplayMetrics().density;
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding((int) (24 * d), (int) (72 * d), (int) (24 * d), (int) (24 * d));

        TextView title = new TextView(this);
        title.setText("WARP");
        title.setTextSize(20);
        title.setAlpha(0.7f);
        root.addView(title);

        state = new TextView(this);
        state.setTextSize(40);
        state.setPadding(0, (int) (8 * d), 0, (int) (4 * d));
        root.addView(state);

        detail = new TextView(this);
        detail.setTextSize(15);
        detail.setGravity(Gravity.CENTER);
        detail.setAlpha(0.8f);
        root.addView(detail);

        toggle = new Button(this);
        toggle.setTextSize(20);
        toggle.setAllCaps(false);
        toggle.setTextColor(Color.WHITE);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams((int) (220 * d), (int) (220 * d));
        lp.topMargin = (int) (40 * d);
        lp.bottomMargin = (int) (32 * d);
        toggle.setLayoutParams(lp);
        toggle.setOnClickListener(v -> doToggle());
        root.addView(toggle);

        TextView hint = new TextView(this);
        hint.setText("Termux stays on the direct connection.\nAdd the \"WARP\" tile in Quick Settings for one-tap control.");
        hint.setGravity(Gravity.CENTER);
        hint.setTextSize(13);
        hint.setAlpha(0.6f);
        root.addView(hint);

        log = new TextView(this);
        log.setTextSize(11);
        log.setTypeface(android.graphics.Typeface.MONOSPACE);
        log.setAlpha(0.55f);
        log.setPadding(0, (int) (24 * d), 0, 0);
        root.addView(log);

        ScrollView sv = new ScrollView(this);
        sv.addView(root);
        setContentView(sv);
    }

    @Override protected void onResume() { super.onResume(); refresh(); }

    private void paint(String s, String det, int color) {
        state.setText(s);
        state.setTextColor(color);
        detail.setText(det);
        GradientDrawable g = new GradientDrawable();
        g.setShape(GradientDrawable.OVAL);
        g.setColor(busy ? Color.GRAY : (on ? 0xFFF38020 : 0xFF455A64));
        toggle.setBackground(g);
        toggle.setText(busy ? "…" : (on ? "Turn off" : "Turn on"));
        toggle.setEnabled(!busy);
    }

    private void refresh() {
        busy = true;
        paint("Checking…", "", Color.GRAY);
        new Thread(() -> {
            Warp.Status s = Warp.status();
            ui.post(() -> show(s));
        }).start();
    }

    private void show(Warp.Status s) {
        busy = false;
        on = s.on();
        log.setText(s.raw.trim());
        if (!s.rootOk) { paint("No root", "Grant root to WARP Switch in your root manager (KernelSU / Magisk / APatch), then reopen.", 0xFFE53935); return; }
        if (!s.setupOk) { paint("Not set up", "WARP files are missing on this phone. In Termux run: cd warp-switch && ./install.sh", 0xFFE53935); return; }
        if (on && s.warpOn) paint("On", "Exit IP " + s.ip + (s.colo.isEmpty() ? "" : "  ·  " + s.colo), 0xFFF38020);
        else if (on) paint("Reconnecting", "Tunnel up, waiting for Cloudflare…", 0xFFFFB300);
        else if (s.engine) paint("Paused", "WARP unreachable – apps use the direct connection", 0xFFFFB300);
        else paint("Off", "Apps use the direct connection", Color.GRAY);
    }

    private void doToggle() {
        final String arg = on ? "down" : "up";
        busy = true;
        paint(on ? "Turning off…" : "Connecting…", "", Color.GRAY);
        new Thread(() -> {
            String r = Warp.run(arg);
            Warp.Status s = Warp.status();
            s.raw = r.trim() + "\n\n" + s.raw;
            ui.post(() -> {
                show(s);
                TileService.requestListeningState(this, new ComponentName(this, WarpTile.class));
            });
        }).start();
    }
}
