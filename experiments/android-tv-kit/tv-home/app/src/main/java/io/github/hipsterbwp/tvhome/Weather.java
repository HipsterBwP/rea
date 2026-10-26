package io.github.hipsterbwp.tvhome;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.Locale;

/**
 * Current weather from Open-Meteo (free, no account or key). The place is a ZIP code or
 * town name; it is geocoded once and the coordinates are kept in preferences.
 */
final class Weather {
    interface Callback {
        void done(String text);
    }

    private static final String PREFS = "weather";
    private final SharedPreferences prefs;
    private final Handler main = new Handler(Looper.getMainLooper());
    private volatile boolean busy;

    Weather(Context c) {
        prefs = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    void setPlace(String place) {
        prefs.edit().putString("place", place.trim()).remove("lat").remove("lon")
                .remove("name").remove("text").apply();
    }

    void setUnits(String units) {
        prefs.edit().putString("units", units.toLowerCase(Locale.US).startsWith("c") ? "c" : "f")
                .remove("text").apply();
    }

    String cached() {
        String place = prefs.getString("place", null);
        if (place == null || place.isEmpty()) return "";
        return prefs.getString("text", "");
    }

    void fetch(final Callback cb) {
        final String place = prefs.getString("place", null);
        if (place == null || place.isEmpty() || busy) return;
        busy = true;
        new Thread(new Runnable() {
            @Override
            public void run() {
                String text;
                try {
                    text = load(place);
                    prefs.edit().putString("text", text).apply();
                } catch (Exception e) {
                    text = prefs.getString("text", "");
                }
                final String shown = text;
                busy = false;
                main.post(new Runnable() {
                    @Override
                    public void run() {
                        cb.done(shown);
                    }
                });
            }
        }, "weather").start();
    }

    private String load(String place) throws Exception {
        String lat = prefs.getString("lat", null);
        String lon = prefs.getString("lon", null);
        String name = prefs.getString("name", place);
        if (lat == null || lon == null) {
            String q = place.contains(",") ? place.substring(0, place.indexOf(',')).trim() : place;
            String url = "https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name="
                    + URLEncoder.encode(q, "UTF-8") + (q.matches("\\d{5}") ? "&countryCode=US" : "");
            JSONArray results = new JSONObject(get(url)).optJSONArray("results");
            if (results == null || results.length() == 0) return "Weather: place \"" + place + "\" not found";
            JSONObject r = results.getJSONObject(0);
            lat = String.valueOf(r.getDouble("latitude"));
            lon = String.valueOf(r.getDouble("longitude"));
            name = r.optString("name", place);
            prefs.edit().putString("lat", lat).putString("lon", lon).putString("name", name).apply();
        }
        boolean celsius = "c".equals(prefs.getString("units", "f"));
        String url = "https://api.open-meteo.com/v1/forecast?current=temperature_2m,weather_code&timezone=auto"
                + "&latitude=" + lat + "&longitude=" + lon
                + (celsius ? "" : "&temperature_unit=fahrenheit");
        JSONObject cur = new JSONObject(get(url)).getJSONObject("current");
        long temp = Math.round(cur.getDouble("temperature_2m"));
        return temp + (celsius ? "°C" : "°F") + "  " + describe(cur.optInt("weather_code", -1)) + "\n" + name;
    }

    private static String get(String address) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(address).openConnection();
        c.setConnectTimeout(10000);
        c.setReadTimeout(10000);
        try {
            if (c.getResponseCode() != 200) throw new IOException("HTTP " + c.getResponseCode());
            InputStream in = c.getInputStream();
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            return out.toString("UTF-8");
        } finally {
            c.disconnect();
        }
    }

    /** WMO weather interpretation codes, as documented by Open-Meteo. */
    private static String describe(int code) {
        if (code == 0) return "Clear";
        if (code == 1) return "Mostly clear";
        if (code == 2) return "Partly cloudy";
        if (code == 3) return "Cloudy";
        if (code == 45 || code == 48) return "Fog";
        if (code >= 51 && code <= 57) return "Drizzle";
        if (code >= 61 && code <= 67) return "Rain";
        if (code >= 71 && code <= 77) return "Snow";
        if (code >= 80 && code <= 82) return "Showers";
        if (code == 85 || code == 86) return "Snow showers";
        if (code >= 95) return "Thunderstorms";
        return "";
    }
}
