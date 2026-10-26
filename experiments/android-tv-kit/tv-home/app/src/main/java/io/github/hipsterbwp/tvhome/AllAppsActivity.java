package io.github.hipsterbwp.tvhome;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/** Every enabled TV app, alphabetically, so nothing is out of reach without the stock launcher. */
public class AllAppsActivity extends Activity {
    private static final int COLUMNS = 5;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        final PackageManager pm = getPackageManager();

        Intent query = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER);
        List<ResolveInfo> apps = new ArrayList<>(pm.queryIntentActivities(query, 0));
        List<ResolveInfo> kept = new ArrayList<>();
        for (ResolveInfo r : apps) {
            if (r.activityInfo.packageName.equals(getPackageName())) continue;
            kept.add(r);
        }
        Collections.sort(kept, new Comparator<ResolveInfo>() {
            @Override
            public int compare(ResolveInfo a, ResolveInfo b) {
                return a.loadLabel(pm).toString().compareToIgnoreCase(b.loadLabel(pm).toString());
            }
        });

        DisplayMetrics m = getResources().getDisplayMetrics();
        int gap = Tiles.dp(this, 18);
        int w = (m.widthPixels - Tiles.dp(this, 112) - (COLUMNS - 1) * gap) / COLUMNS;
        int h = w * 9 / 16;

        List<View> tiles = new ArrayList<>();
        for (ResolveInfo r : kept) {
            final Intent launch = new Intent(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
                    .setClassName(r.activityInfo.packageName, r.activityInfo.name);
            tiles.add(Tiles.tile(this, Tiles.banner(pm, launch), r.loadIcon(pm), r.loadLabel(pm), w, h,
                    new View.OnClickListener() {
                        @Override
                        public void onClick(View v) {
                            Tiles.launch(AllAppsActivity.this, launch);
                        }
                    }));
        }

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setClipChildren(false);
        int pad = Tiles.dp(this, 56);
        col.setPadding(pad, Tiles.dp(this, 32), pad, Tiles.dp(this, 32));
        TextView title = new TextView(this);
        title.setText("All apps");
        title.setTextColor(Color.WHITE);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 32);
        LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        tp.bottomMargin = Tiles.dp(this, 24);
        col.addView(title, tp);
        col.addView(Tiles.grid(this, tiles, COLUMNS, w, h, gap));

        ScrollView scroll = new ScrollView(this);
        scroll.setClipChildren(false);
        scroll.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR,
                new int[] {0xFF14253D, 0xFF0A0F1A}));
        scroll.addView(col);
        setContentView(scroll);
        if (!tiles.isEmpty()) tiles.get(0).requestFocus();
    }
}
