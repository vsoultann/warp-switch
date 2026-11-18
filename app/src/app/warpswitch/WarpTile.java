package app.warpswitch;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

public class WarpTile extends TileService {
    private volatile boolean busy;

    @Override public void onStartListening() { update(); }

    private void update() {
        new Thread(() -> {
            Warp.Status s = Warp.status();
            set(s.on() ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE,
                s.on() ? (s.warpOn ? (s.colo.isEmpty() ? "On" : "On · " + s.colo) : "Reconnecting") : "Off");
        }).start();
    }

    private void set(int state, String sub) {
        Tile t = getQsTile();
        if (t == null) return;
        t.setState(state);
        t.setLabel("WARP");
        t.setSubtitle(sub);
        t.updateTile();
    }

    @Override public void onClick() {
        if (busy) return;
        Tile t = getQsTile();
        final boolean turnOn = t == null || t.getState() != Tile.STATE_ACTIVE;
        busy = true;
        set(Tile.STATE_UNAVAILABLE, turnOn ? "Connecting…" : "Turning off…");
        new Thread(() -> {
            Warp.run(turnOn ? "up" : "down");
            busy = false;
            update();
        }).start();
    }
}
