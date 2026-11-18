package app.warpswitch;

import java.io.BufferedReader;
import java.io.InputStreamReader;

/** Runs ~/warp/warp.sh as root and parses its status output. */
final class Warp {
    static final String SCRIPT = "/data/data/com.termux/files/home/warp/warp.sh";

    static final class Status {
        boolean engine, steering, warpOn, rootOk = true;
        String ip = "", colo = "", raw = "";
        boolean on() { return engine && steering; }
    }

    static String run(String arg) {
        StringBuilder out = new StringBuilder();
        try {
            Process p = new ProcessBuilder("su", "-c", SCRIPT + " " + arg).redirectErrorStream(true).start();
            try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
                String l;
                while ((l = r.readLine()) != null) out.append(l).append('\n');
            }
            int rc = p.waitFor();
            if (rc != 0 && out.length() == 0) out.append("exit ").append(rc);
        } catch (Exception e) {
            out.append("ERROR: ").append(e.getMessage());
        }
        return out.toString();
    }

    static Status status() {
        Status s = new Status();
        s.raw = run("status");
        for (String l : s.raw.split("\n")) {
            if (l.startsWith("sing-box running")) s.engine = true;
            else if (l.startsWith("steering ON")) s.steering = true;
            else if (l.equals("warp=on")) s.warpOn = true;
            else if (l.startsWith("ip=")) s.ip = l.substring(3);
            else if (l.startsWith("colo=")) s.colo = l.substring(5);
            else if (l.startsWith("ERROR") || l.contains("Permission denied") || l.contains("not allowed")) s.rootOk = false;
        }
        return s;
    }
}
