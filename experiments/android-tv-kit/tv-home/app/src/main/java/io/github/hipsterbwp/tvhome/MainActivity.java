package io.github.hipsterbwp.tvhome;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextClock;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

/**
 * The home screen: clock, date and weather on top, then big tiles for the chosen apps,
 * All apps and Settings. Weather location is set with
 * {@code adb shell am start -n io.github.hipsterbwp.tvhome/.MainActivity --es place 74103}.
 */
public class MainActivity extends Activity {
    /** Package and fallback name, in display order. Missing or disabled apps are skipped. */
    private static final String[][] FAVORITES = {
            {"com.google.android.youtube.tv", "YouTube"},
            {"com.netflix.ninja", "Netflix"},
            {"com.wbd.stream", "Max"},
            {"com.amazon.amazonvideo.livingroom", "Prime Video"},
            {"com.disney.disneyplus", "Disney+"},
            {"com.espn.score_center", "ESPN"},
            {"tv.twitch.android.app", "Twitch"},
            {"air.com.vudu.air.DownloaderTablet", "Fandango"},
            {"net.comeandsee.ott.thechosen", "The Chosen"},
    };
    private static final int COLUMNS = 4;
    private static final long WEATHER_REFRESH_MS = 30 * 60 * 1000L;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private LinearLayout gridHolder;
    private TextView weatherView;
    private Weather weather;
    private String lastFocused;

    private final Runnable weatherTick = new Runnable() {
        @Override
        public void run() {
            weather.fetch(new Weather.Callback() {
                @Override
                public void done(String text) {
                    weatherView.setText(text);
                }
            });
            handler.postDelayed(this, WEATHER_REFRESH_MS);
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        weather = new Weather(this);
        applyExtras(getIntent());

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setClipChildren(false);
        root.setPadding(Tiles.dp(this, 56), Tiles.dp(this, 28), Tiles.dp(this, 56), Tiles.dp(this, 16));
        root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR,
                new int[] {0xFF14253D, 0xFF0A0F1A}));

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout clockBox = new LinearLayout(this);
        clockBox.setOrientation(LinearLayout.VERTICAL);
        TextClock time = new TextClock(this);
        time.setFormat12Hour("h:mm");
        time.setFormat24Hour("HH:mm");
        time.setTextColor(Color.WHITE);
        time.setTextSize(TypedValue.COMPLEX_UNIT_SP, 52);
        TextClock date = new TextClock(this);
        date.setFormat12Hour("EEEE, MMMM d");
        date.setFormat24Hour("EEEE, MMMM d");
        date.setTextColor(0xCCFFFFFF);
        date.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
        clockBox.addView(time);
        clockBox.addView(date);
        top.addView(clockBox, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1));

        weatherView = new TextView(this);
        weatherView.setTextColor(Color.WHITE);
        weatherView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        weatherView.setGravity(Gravity.END);
        weatherView.setText(weather.cached());
        top.addView(weatherView);

        root.addView(top);

        gridHolder = new LinearLayout(this);
        gridHolder.setGravity(Gravity.CENTER);
        gridHolder.setClipChildren(false);
        LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1);
        root.addView(gridHolder, gp);

        setContentView(root);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        applyExtras(intent);
    }

    @Override
    protected void onResume() {
        super.onResume();
        buildGrid();
        handler.removeCallbacks(weatherTick);
        handler.post(weatherTick);
    }

    @Override
    protected void onPause() {
        handler.removeCallbacks(weatherTick);
        super.onPause();
    }

    @Override
    public void onBackPressed() {
        // This is the home screen; there is nothing to go back to.
    }

    private void applyExtras(Intent intent) {
        if (intent == null) return;
        String place = intent.getStringExtra("place");
        if (place != null) weather.setPlace(place);
        String units = intent.getStringExtra("units");
        if (units != null) weather.setUnits(units);
    }

    private void buildGrid() {
        final PackageManager pm = getPackageManager();
        List<View> tiles = new ArrayList<>();
        List<String> keys = new ArrayList<>();

        DisplayMetrics m = getResources().getDisplayMetrics();
        int gap = Tiles.dp(this, 22);
        int count = 2;
        for (String[] f : FAVORITES) if (Tiles.launchIntent(pm, f[0]) != null) count++;
        int rows = (count + COLUMNS - 1) / COLUMNS;
        int availW = m.widthPixels - Tiles.dp(this, 112);
        int availH = m.heightPixels - Tiles.dp(this, 28 + 16 + 130 + 24);
        int w = (availW - (COLUMNS - 1) * gap) / COLUMNS;
        int h = w * 9 / 16;
        int maxH = (availH - (rows - 1) * gap) / rows;
        if (h > maxH) {
            h = maxH;
            w = h * 16 / 9;
        }

        for (String[] f : FAVORITES) {
            final Intent launch = Tiles.launchIntent(pm, f[0]);
            if (launch == null) continue;
            final String pkg = f[0];
            View t = Tiles.tile(this, Tiles.banner(pm, launch), iconOf(pm, pkg),
                    Tiles.label(pm, pkg, f[1]), w, h, new View.OnClickListener() {
                        @Override
                        public void onClick(View v) {
                            lastFocused = pkg;
                            Tiles.launch(MainActivity.this, launch);
                        }
                    });
            tiles.add(t);
            keys.add(pkg);
        }
        tiles.add(Tiles.tile(this, null, getDrawable(android.R.drawable.ic_menu_more), "All apps",
                w, h, new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        lastFocused = "#all";
                        startActivity(new Intent(MainActivity.this, AllAppsActivity.class));
                    }
                }));
        keys.add("#all");
        tiles.add(Tiles.tile(this, null, getDrawable(android.R.drawable.ic_menu_preferences), "Settings",
                w, h, new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        lastFocused = "#settings";
                        Tiles.launch(MainActivity.this, new Intent(Settings.ACTION_SETTINGS));
                    }
                }));
        keys.add("#settings");

        gridHolder.removeAllViews();
        gridHolder.addView(Tiles.grid(this, tiles, COLUMNS, w, h, gap));
        int focus = lastFocused == null ? 0 : Math.max(0, keys.indexOf(lastFocused));
        tiles.get(focus).requestFocus();
    }

    private static android.graphics.drawable.Drawable iconOf(PackageManager pm, String pkg) {
        try {
            return pm.getApplicationIcon(pkg);
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
    }
}
