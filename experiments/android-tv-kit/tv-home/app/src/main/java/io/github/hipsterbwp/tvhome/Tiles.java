package io.github.hipsterbwp.tvhome;

import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Builds focusable app tiles and launches apps; shared by the home and all-apps screens. */
final class Tiles {
    private Tiles() {}

    static int dp(Context c, float v) {
        return Math.round(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, v, c.getResources().getDisplayMetrics()));
    }

    /** The launch intent for a TV app, or null when it is missing or disabled. */
    static Intent launchIntent(PackageManager pm, String pkg) {
        try {
            ApplicationInfo info = pm.getApplicationInfo(pkg, 0);
            if (!info.enabled) return null;
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
        Intent i = pm.getLeanbackLaunchIntentForPackage(pkg);
        if (i == null) i = pm.getLaunchIntentForPackage(pkg);
        return i;
    }

    static void launch(Context c, Intent i) {
        Intent copy = new Intent(i).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            c.startActivity(copy);
        } catch (ActivityNotFoundException | SecurityException ignored) {
            // App vanished or refused; the home screen simply stays put.
        }
    }

    static Drawable banner(PackageManager pm, Intent launch) {
        ComponentName cn = launch.getComponent();
        if (cn == null) return null;
        try {
            Drawable d = pm.getActivityBanner(cn);
            return d != null ? d : pm.getApplicationBanner(cn.getPackageName());
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
    }

    static CharSequence label(PackageManager pm, String pkg, CharSequence fallback) {
        try {
            return pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0));
        } catch (PackageManager.NameNotFoundException e) {
            return fallback;
        }
    }

    /** A 16:9 tile showing the app banner, or its icon and name when it has no banner. */
    static View tile(Context c, Drawable banner, Drawable icon, CharSequence name,
                     int width, int height, View.OnClickListener onClick) {
        final FrameLayout tile = new FrameLayout(c);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(0x33FFFFFF);
        bg.setCornerRadius(dp(c, 10));
        tile.setBackground(bg);
        tile.setClipToOutline(true);
        tile.setFocusable(true);
        tile.setClickable(true);
        tile.setContentDescription(name);
        tile.setOnClickListener(onClick);

        if (banner != null) {
            ImageView img = new ImageView(c);
            img.setImageDrawable(banner);
            img.setScaleType(ImageView.ScaleType.FIT_XY);
            tile.addView(img, new FrameLayout.LayoutParams(width, height));
        } else {
            LinearLayout box = new LinearLayout(c);
            box.setOrientation(LinearLayout.VERTICAL);
            box.setGravity(Gravity.CENTER);
            if (icon != null) {
                ImageView img = new ImageView(c);
                img.setImageDrawable(icon);
                int s = Math.min(dp(c, 64), height / 2);
                box.addView(img, new LinearLayout.LayoutParams(s, s));
            }
            TextView t = new TextView(c);
            t.setText(name);
            t.setTextColor(Color.WHITE);
            t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
            t.setTypeface(Typeface.DEFAULT_BOLD);
            t.setGravity(Gravity.CENTER);
            t.setSingleLine(true);
            box.addView(t);
            tile.addView(box, new FrameLayout.LayoutParams(width, height));
        }

        final GradientDrawable ring = new GradientDrawable();
        ring.setColor(Color.TRANSPARENT);
        ring.setStroke(dp(c, 4), Color.WHITE);
        ring.setCornerRadius(dp(c, 10));
        tile.setOnFocusChangeListener(new View.OnFocusChangeListener() {
            @Override
            public void onFocusChange(View v, boolean focused) {
                tile.setForeground(focused ? ring : null);
                float s = focused ? 1.08f : 1f;
                v.animate().scaleX(s).scaleY(s).translationZ(focused ? dp(v.getContext(), 8) : 0)
                        .setDuration(120).start();
            }
        });
        return tile;
    }

    /** Lays tiles out in rows of {@code columns}, centred, with {@code gap} spacing. */
    static LinearLayout grid(Context c, java.util.List<View> tiles, int columns, int width,
                             int height, int gap) {
        LinearLayout rows = new LinearLayout(c);
        rows.setOrientation(LinearLayout.VERTICAL);
        LinearLayout row = null;
        for (int i = 0; i < tiles.size(); i++) {
            if (i % columns == 0) {
                row = new LinearLayout(c);
                row.setOrientation(LinearLayout.HORIZONTAL);
                row.setClipChildren(false);
                LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
                rp.bottomMargin = gap;
                rows.addView(row, rp);
            }
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(width, height);
            if (i % columns != 0) lp.leftMargin = gap;
            row.addView(tiles.get(i), lp);
        }
        rows.setClipChildren(false);
        return rows;
    }
}
