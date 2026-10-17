#!/bin/bash
set -e
echo "[ELAINA] Generating project..."

cat > ".gitignore" <<'__XH_EOF__'
*.iml
.gradle
/local.properties
/.idea
.DS_Store
/build
/app/build
/captures
.externalNativeBuild
.cxx

__XH_EOF__

cat > "README.md" <<'__XH_EOF__'
# ELAINA Optimasi

App optimasi game + crosshair + **turbo tap (macro klik cepat)** via **Shizuku**.

## Fitur
- Crosshair overlay
- Turbo / Game mode
- Monitor RAM, baterai, CPU (dengan Shizuku: % CPU asli)
- **Tombol TAP mengambang** — spam klik cepat (butuh Shizuku)
- Pembersih RAM (force-stop app latar)
- Pelicin animasi layar

## Syarat HP
- Android 10+
- Install [Shizuku](https://shizuku.rikka.app/)
- Android 11+: nyalakan lewat Wireless Debugging
- Android 10: nyalakan lewat PC/ADB sekali

## Cara dapat APK (tanpa PC)
1. Buka tab **Actions** di repo ini
2. Pilih workflow **Build APK**
3. Tunggu selesai (centang hijau)
4. Klik run terbaru → **Artifacts** → download `elaina-optimasi-apk`
5. Extract ZIP → install APK di HP

Atau tekan **Actions → Build APK → Run workflow** untuk build manual.

__XH_EOF__

mkdir -p "app"
cat > "app/build.gradle.kts" <<'__XH_EOF__'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.crosshair.pro"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.crosshair.pro"
        minSdk = 29
        targetSdk = 34
        versionCode = 2
        versionName = "1.1-shizuku"
    }
    buildTypes { release { isMinifyEnabled = false } }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation("dev.rikka.shizuku:api:4.1.0")
    implementation("dev.rikka.shizuku:provider:4.1.0")
}

__XH_EOF__

mkdir -p "app/src/main"
cat > "app/src/main/AndroidManifest.xml" <<'__XH_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.ACCESS_NOTIFICATION_POLICY" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES" />
    <queries>
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent>
        <package android:name="moe.shizuku.privileged.api" />
    </queries>
    <application
        android:label="ELAINA Optimasi"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher"
        android:allowBackup="false"
        android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service
            android:name=".OverlayService"
            android:exported="false"
            android:foregroundServiceType="specialUse|mediaProjection">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="game overlay crosshair" />
        </service>
        <provider
            android:name="rikka.shizuku.ShizukuProvider"
            android:authorities="${applicationId}.shizuku"
            android:multiprocess="false"
            android:enabled="true"
            android:exported="true"
            android:permission="android.permission.INTERACT_ACROSS_USERS_FULL" />
    </application>
</manifest>

__XH_EOF__

mkdir -p "app/src/main/java/com/crosshair/pro"
cat > "app/src/main/java/com/crosshair/pro/Bg.kt" <<'__XH_EOF__'
package com.crosshair.pro

import android.graphics.Bitmap

object Bg {
    /** Returns (full-size result with transparent background, cropped result or null if empty). */
    fun process(src: Bitmap, tol: Int, feather: Int, mode: Int, bgIn: Int?): Pair<Bitmap, Bitmap?> {
        val w = src.width
        val h = src.height
        val n = w * h
        val px = IntArray(n)
        src.getPixels(px, 0, w, 0, 0, w, h)
        val bg = bgIn ?: avgBorder(px, w, h)
        val br = (bg shr 16) and 255
        val bgG = (bg shr 8) and 255
        val bb = bg and 255
        val t2 = tol * tol
        fun match(i: Int): Boolean {
            val c = px[i]
            if ((c ushr 24) < 8) return true
            val dr = ((c shr 16) and 255) - br
            val dg = ((c shr 8) and 255) - bgG
            val db = (c and 255) - bb
            return dr * dr + dg * dg + db * db <= t2
        }
        val rem = BooleanArray(n)
        if (mode == 1) {
            for (i in 0 until n) if (match(i)) rem[i] = true
        } else {
            val st = IntArray(n + 8)
            var sp = 0
            fun push(x: Int, y: Int) {
                val q = y * w + x
                if (!rem[q] && match(q)) { rem[q] = true; st[sp++] = q }
            }
            for (x in 0 until w) { push(x, 0); push(x, h - 1) }
            for (y in 0 until h) { push(0, y); push(w - 1, y) }
            while (sp > 0) {
                val q = st[--sp]
                val x = q % w
                val y = q / w
                if (x > 0) push(x - 1, y)
                if (x < w - 1) push(x + 1, y)
                if (y > 0) push(x, y - 1)
                if (y < h - 1) push(x, y + 1)
            }
        }
        val a0 = FloatArray(n) { (px[it] ushr 24).toFloat() }
        var a = FloatArray(n) { if (rem[it]) 0f else a0[it] }
        repeat(feather) {
            val b2 = FloatArray(n)
            for (y in 0 until h) for (x in 0 until w) {
                var s = 0f
                var cnt = 0
                for (oy in -1..1) {
                    val ny = y + oy
                    if (ny < 0 || ny >= h) continue
                    for (ox in -1..1) {
                        val nx = x + ox
                        if (nx < 0 || nx >= w) continue
                        s += a[ny * w + nx]
                        cnt++
                    }
                }
                b2[y * w + x] = s / cnt
            }
            val na = FloatArray(n)
            for (j in 0 until n) na[j] = if (rem[j]) b2[j] * 0.6f else minOf(a0[j], b2[j] * 1.2f)
            a = na
        }
        var minx = w; var miny = h; var maxx = -1; var maxy = -1
        val out = IntArray(n)
        for (i in 0 until n) {
            val av = a[i].toInt().coerceIn(0, 255)
            out[i] = (av shl 24) or (px[i] and 0xFFFFFF)
            if (av > 20) {
                val x = i % w
                val y = i / w
                if (x < minx) minx = x
                if (x > maxx) maxx = x
                if (y < miny) miny = y
                if (y > maxy) maxy = y
            }
        }
        val full = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        full.setPixels(out, 0, w, 0, 0, w, h)
        val cropped = if (maxx < 0) null else Bitmap.createBitmap(full, minx, miny, maxx - minx + 1, maxy - miny + 1)
        return Pair(full, cropped)
    }

    private fun avgBorder(px: IntArray, w: Int, h: Int): Int {
        val pts = arrayOf(
            intArrayOf(0, 0), intArrayOf(w - 1, 0), intArrayOf(0, h - 1), intArrayOf(w - 1, h - 1),
            intArrayOf(w / 2, 0), intArrayOf(w / 2, h - 1), intArrayOf(0, h / 2), intArrayOf(w - 1, h / 2)
        )
        var r = 0; var g = 0; var b = 0
        for (p in pts) {
            val c = px[p[1] * w + p[0]]
            r += (c shr 16) and 255; g += (c shr 8) and 255; b += c and 255
        }
        return (0xFF shl 24) or ((r / pts.size) shl 16) or ((g / pts.size) shl 8) or (b / pts.size)
    }
}

__XH_EOF__

mkdir -p "app/src/main/java/com/crosshair/pro"
cat > "app/src/main/java/com/crosshair/pro/MainActivity.kt" <<'__XH_EOF__'
package com.crosshair.pro

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.media.ExifInterface
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.*
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class Game(val pkg: String, val name: String, val icon: Drawable, val isGame: Boolean)

class MainActivity : Activity() {
    private lateinit var s: Spec
    private lateinit var content: FrameLayout
    private lateinit var navRow: LinearLayout
    private var tab = 0
    private var allApps: List<Game> = emptyList()
    private var preview: CrosshairView? = null
    private var pick: PickView? = null
    private var pending: String? = null
    private val ex = Executors.newSingleThreadExecutor()
    private val hd = Handler(Looper.getMainLooper())
    private var monitor: Runnable? = null
    private var turboTap: TurboTap? = null

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        s = Spec(this)
        window.statusBarColor = C.BG
        window.navigationBarColor = C.BG
        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setBackgroundColor(C.BG)
        content = FrameLayout(this)
        root.addView(content, LinearLayout.LayoutParams(-1, 0, 1f))
        navRow = LinearLayout(this)
        navRow.setBackgroundColor(C.PANEL)
        val names = listOf("TURBO", "CROSSHAIR", "MONITOR", "SETELAN")
        for (i in names.indices) {
            val t = label(names[i], 12f, C.MUTE, true)
            t.gravity = Gravity.CENTER
            t.setPadding(0, dp(16), 0, dp(16))
            t.setOnClickListener { showTab(i) }
            navRow.addView(t, LinearLayout.LayoutParams(0, -2, 1f))
        }
        root.addView(navRow, LinearLayout.LayoutParams(-1, -2))
        setContentView(root)
        loadGames()
        showTab(0)
    }

    override fun onResume() {
        super.onResume()
        if (tab == 0 || tab == 3) showTab(tab)
    }

    override fun onPause() {
        super.onPause()
        monitor?.let { hd.removeCallbacks(it) }
    }

    private fun toast(t: String) { Toast.makeText(this, t, Toast.LENGTH_LONG).show() }

    private fun showTab(i: Int) {
        tab = i
        monitor?.let { hd.removeCallbacks(it) }
        monitor = null
        for (k in 0 until navRow.childCount) {
            val t = navRow.getChildAt(k) as TextView
            val on = k == i
            t.setTextColor(if (on) C.RED else C.MUTE)
            t.background = if (on) Chamfer(0x22FF1744, C.RED, dp(8).toFloat(), 2f) else null
        }
        val sv = ScrollView(this)
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.setPadding(dp(16), dp(16), dp(16), dp(24))
        when (i) {
            0 -> buildTurbo(col)
            1 -> buildCross(col)
            2 -> buildMonitor(col)
            else -> buildSettings(col)
        }
        sv.addView(col)
        content.removeAllViews()
        content.addView(sv)
    }

    private fun header(col: LinearLayout, sub: String) {
        val row = LinearLayout(this)
        row.gravity = Gravity.CENTER_VERTICAL
        val av = ShapeImageView(this, s)
        av.setImageResource(R.drawable.elaina)
        row.addView(av, LinearLayout.LayoutParams(dp(60), dp(60)))
        val tc = LinearLayout(this)
        tc.orientation = LinearLayout.VERTICAL
        tc.setPadding(dp(12), 0, 0, 0)
        val t1 = label("ELAINA", 30f, Color.WHITE, true, true)
        t1.setShadowLayer(14f, 0f, 0f, C.RED)
        tc.addView(t1)
        tc.addView(label(sub, 12f, C.RED, true))
        row.addView(tc)
        col.addView(row)
    }

    private fun tile(title: String, value: String): LinearLayout {
        val c = card(10)
        c.addView(label(title, 11f, C.MUTE, true))
        c.addView(label(value, 20f, Color.WHITE, true, true))
        return c
    }

    // ================= TURBO =================
    private fun buildTurbo(col: LinearLayout) {
        header(col, "OPTIMASI  •  GAME TURBO")
        val (_, _, rp) = Stats.ram(this)
        val (bp, bt) = Stats.battery(this)
        val st = LinearLayout(this)
        st.addView(tile("RAM", "$rp%"), lp(0, -2, 0, 1f).also { it.setMargins(0, 0, dp(4), 0) })
        st.addView(tile("BATERAI", "$bp%"), lp(0, -2, 0, 1f).also { it.setMargins(dp(4), 0, dp(4), 0) })
        st.addView(tile("SUHU", "%.0f°C".format(bt)), lp(0, -2, 0, 1f).also { it.setMargins(dp(4), 0, 0, 0) })
        col.addView(st, lp(-1, -2, 16))

        val on = OverlayService.instance != null
        val ac = card()
        ac.addView(label(if (on) "GAME TURBO AKTIF" else "GAME TURBO SIAP", 16f, if (on) C.GREEN else C.CYAN, true, true))
        ac.addView(label(if (on) "Crosshair dan panel sedang berjalan di atas game." else "Pilih game lalu tekan START. Crosshair dan panel muncul otomatis.", 12f, C.MUTE))
        if (on) ac.addView(rogBtn("MATIKAN", false) { stopService(Intent(this, OverlayService::class.java)); hd.postDelayed({ showTab(0) }, 300) }, lp(-1, -2, 10))
        col.addView(ac, lp(-1, -2, 14))

        // ---- Shizuku + Turbo Tap + RAM ----
        col.addView(section("SHIZUKU  •  MACRO"), lp(-2, -2, 22))
        val sz = card()
        val szOk = ShizukuHelper.available() && ShizukuHelper.permissionGranted()
        sz.addView(label(ShizukuHelper.statusText(), 15f, if (szOk) C.GREEN else C.CYAN, true, true))
        sz.addView(label("Macro klik cepat & pembersih RAM butuh Shizuku aktif.", 12f, C.MUTE))
        if (!ShizukuHelper.available()) {
            sz.addView(rogBtn("BUKA SHIZUKU", true) {
                try {
                    startActivity(packageManager.getLaunchIntentForPackage("moe.shizuku.privileged.api"))
                } catch (_: Exception) {
                    toast("Install aplikasi Shizuku dulu dari Play Store / GitHub")
                }
            }, lp(-1, -2, 10))
        } else if (!ShizukuHelper.permissionGranted()) {
            sz.addView(rogBtn("BERI IZIN SHIZUKU", true) {
                ShizukuHelper.requestPermission { _, res ->
                    hd.post { toast(if (res == 0) "Izin diberikan" else "Izin ditolak"); showTab(0) }
                }
            }, lp(-1, -2, 10))
        } else {
            sz.addView(label("Kecepatan ketukan: ${s.i("turboCps")} CPS", 13f, C.MUTE), lp(-1, -2, 6))
            sz.addView(seek("CPS", "turboCps", 5, 25, false), lp(-1, -2, 6))
            val turboShown = turboTap?.isShowing() == true
            sz.addView(rogBtn(if (turboShown) "MATIKAN TOMBOL TAP" else "TAMPILKAN TOMBOL TAP", true) {
                if (!Settings.canDrawOverlays(this)) {
                    startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                    toast("Izinkan tampil di atas aplikasi lain")
                    return@rogBtn
                }
                if (turboTap?.isShowing() == true) {
                    turboTap?.hide(); turboTap = null
                } else {
                    turboTap = TurboTap(this).also { it.show(s.i("turboCps")) }
                    toast("Geser tombol merah, ketuk sekali untuk ON/OFF spam klik")
                }
                showTab(0)
            }, lp(-1, -2, 8))
            sz.addView(rogBtn("BERSIHKAN RAM SEKARANG", false) {
                toast("Membersihkan...")
                ex.execute {
                    val n = ShizukuHelper.cleanRam(this)
                    hd.post {
                        toast(if (n < 0) "Shizuku belum siap" else "Selesai • ~$n app dihentikan")
                        showTab(0)
                    }
                }
            }, lp(-1, -2, 8))
            sz.addView(rogBtn(if (s.b("animSmooth")) "PELICIN: ON" else "PELICIN LAYAR", false) {
                val onA = !s.b("animSmooth")
                s.set("animSmooth", if (onA) 1 else 0)
                ShizukuHelper.animScale(if (onA) "0.5" else "1")
                toast(if (onA) "Animasi dipercepat" else "Animasi normal")
                showTab(0)
            }, lp(-1, -2, 8))
        }
        col.addView(sz, lp(-1, -2, 14))

        col.addView(section("GAME KAMU"), lp(-2, -2, 22))
        val pins = s.pins()
        val shown = allApps.filter { it.isGame || pins.contains(it.pkg) }
        if (allApps.isEmpty()) col.addView(label("Memuat daftar aplikasi...", 13f, C.MUTE), lp(-1, -2, 12))
        else if (shown.isEmpty()) col.addView(label("Belum ada game terdeteksi. Ketuk TAMBAH GAME.", 13f, C.MUTE), lp(-1, -2, 12))
        for (g in shown) {
            val r = card(10)
            r.orientation = LinearLayout.HORIZONTAL
            r.gravity = Gravity.CENTER_VERTICAL
            val ic = ShapeImageView(this, s)
            ic.setImageDrawable(g.icon)
            r.addView(ic, LinearLayout.LayoutParams(dp(48), dp(48)))
            val nm = label(g.name, 15f, Color.WHITE, true)
            nm.setPadding(dp(12), 0, dp(8), 0)
            nm.maxLines = 2
            r.addView(nm, LinearLayout.LayoutParams(0, -2, 1f))
            r.addView(rogBtn("START", true) { startGame(g) })
            r.setOnLongClickListener {
                if (pins.contains(g.pkg) && !g.isGame) {
                    val np = s.pins(); np.remove(g.pkg); s.setPins(np); showTab(0)
                } else toast("Game terdeteksi otomatis tidak bisa dihapus.")
                true
            }
            col.addView(r, lp(-1, -2, 10))
        }
        col.addView(rogBtn("+ TAMBAH GAME", false) { pickGames() }, lp(-1, -2, 14))
        col.addView(label("Tahan lama pada game untuk menghapus yang kamu tambahkan sendiri.", 11f, C.MUTE), lp(-1, -2, 8))
    }

    private fun isGame(ai: ApplicationInfo): Boolean {
        return ai.category == ApplicationInfo.CATEGORY_GAME || (ai.flags and ApplicationInfo.FLAG_IS_GAME) != 0
    }

    private fun loadGames() {
        ex.execute {
            try {
                val pm = packageManager
                val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                val list = pm.queryIntentActivities(i, 0).mapNotNull { ri ->
                    val ai = ri.activityInfo.applicationInfo
                    if (ai.packageName == packageName) null else Game(ai.packageName, ri.loadLabel(pm).toString(), ri.loadIcon(pm), isGame(ai))
                }.distinctBy { it.pkg }.sortedBy { it.name.lowercase() }
                runOnUiThread { allApps = list; if (tab == 0) showTab(0) }
            } catch (e: Exception) {
                runOnUiThread { toast("Gagal membaca daftar aplikasi.") }
            }
        }
    }

    private fun pickGames() {
        if (allApps.isEmpty()) { toast("Daftar aplikasi belum siap."); return }
        val names = allApps.map { it.name }.toTypedArray()
        val pins = s.pins()
        val chk = BooleanArray(allApps.size) { pins.contains(allApps[it].pkg) }
        AlertDialog.Builder(this).setTitle("Pilih game")
            .setMultiChoiceItems(names, chk) { _, w, c -> chk[w] = c }
            .setPositiveButton("Simpan") { _, _ ->
                val np = HashSet<String>()
                for (k in chk.indices) if (chk[k]) np.add(allApps[k].pkg)
                s.setPins(np)
                showTab(0)
            }
            .setNegativeButton("Batal", null).show()
    }

    private fun startGame(g: Game) {
        if (!Settings.canDrawOverlays(this)) {
            toast("Aktifkan izin Tampil di atas aplikasi lain untuk ELAINA, lalu kembali dan tekan START lagi.")
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
            return
        }
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        pending = g.pkg
        if (s.b("shot")) {
            try {
                val mpm = getSystemService(MediaProjectionManager::class.java)
                startActivityForResult(mpm.createScreenCaptureIntent(), 77)
                return
            } catch (e: Exception) { }
        }
        launchGame(g.pkg, null, 0)
    }

    private fun launchGame(pkg: String?, data: Intent?, code: Int) {
        val i = Intent(this, OverlayService::class.java)
        if (data != null) { i.putExtra("code", code); i.putExtra("data", data) }
        try { startForegroundService(i) } catch (e: Exception) { toast("Gagal menyalakan Game Turbo."); return }
        hd.postDelayed({
            val li = if (pkg != null) packageManager.getLaunchIntentForPackage(pkg) else null
            if (li != null) startActivity(li) else toast("Game tidak bisa dibuka.")
        }, 600)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(rc: Int, res: Int, d: Intent?) {
        super.onActivityResult(rc, res, d)
        val u = d?.data
        if (rc == 9 && res == RESULT_OK && u != null) loadPhoto(u)
        if (rc == 77) launchGame(pending, if (res == RESULT_OK) d else null, res)
    }

    // ================= CROSSHAIR =================
    private fun apply() {
        preview?.invalidate()
        OverlayService.instance?.refresh()
    }

    private fun buildCross(col: LinearLayout) {
        header(col, "EDITOR CROSSHAIR")
        val box = FrameLayout(this)
        box.background = Chamfer(0xFF1A0B33.toInt(), C.RED, dp(14).toFloat(), 3f)
        val pv = CrosshairView(this, s)
        pv.photo = Store.cut(this)
        preview = pv
        box.addView(pv, FrameLayout.LayoutParams(-1, -1))
        col.addView(box, lp(-1, dp(220), 14))

        col.addView(section("BENTUK"), lp(-2, -2, 20))
        col.addView(chipRow("shape", listOf("Plus", "T", "X", "Cincin", "Cincin+", "Titik"), false, null), lp(-1, -2, 8))
        col.addView(section("WARNA"), lp(-2, -2, 20))
        col.addView(colors(), lp(-1, -2, 8))
        col.addView(section("UKURAN"), lp(-2, -2, 20))
        col.addView(seek("Panjang garis", "len", 2, 60, false), lp(-1, -2, 6))
        col.addView(seek("Tebal garis", "th", 1, 14, false), lp(-1, -2, 6))
        col.addView(seek("Celah tengah", "gap", 0, 40, false), lp(-1, -2, 6))
        col.addView(seek("Radius cincin", "ring", 6, 60, false), lp(-1, -2, 6))
        col.addView(seek("Rotasi", "rot", 0, 360, false), lp(-1, -2, 6))
        col.addView(seek("Transparansi", "op", 10, 100, false), lp(-1, -2, 6))
        col.addView(seek("Ukuran titik", "dotSize", 1, 16, false), lp(-1, -2, 6))
        col.addView(check("Garis tepi hitam", "outline"))
        col.addView(check("Titik di tengah", "dot"))

        col.addView(section("POSISI DI LAYAR GAME"), lp(-2, -2, 20))
        col.addView(label("Geser jika crosshair game kamu tidak tepat di tengah.", 12f, C.MUTE), lp(-1, -2, 6))
        col.addView(seek("Geser kiri / kanan", "offX", -200, 200, false), lp(-1, -2, 6))
        col.addView(seek("Geser atas / bawah", "offY", -300, 300, false), lp(-1, -2, 6))

        col.addView(section("FOTO JADI CROSSHAIR"), lp(-2, -2, 22))
        col.addView(label("Crosshair foto hanya bisa diatur di sini. Latar dihapus otomatis.", 12f, C.MUTE), lp(-1, -2, 8))
        col.addView(rogBtn("PILIH FOTO", true) {
            val i = Intent(Intent.ACTION_GET_CONTENT)
            i.type = "image/*"
            startActivityForResult(i, 9)
        }, lp(-1, -2, 10))
        val pk = PickView(this)
        pk.onPick = { x, y -> pickBg(x, y) }
        pick = pk
        col.addView(pk, lp(-1, dp(220), 10))
        col.addView(label("Ketuk bagian latar pada pratinjau untuk memilih warna yang dihapus.", 12f, C.MUTE), lp(-1, -2, 6))
        col.addView(chipRow("mode", listOf("Dari tepi", "Seluruh gambar"), true, null), lp(-1, -2, 10))
        col.addView(seek("Toleransi warna", "tol", 5, 150, true), lp(-1, -2, 8))
        col.addView(seek("Haluskan tepi", "feather", 0, 6, true), lp(-1, -2, 6))
        col.addView(seek("Ukuran foto", "pSize", 10, 280, false), lp(-1, -2, 6))
        col.addView(seek("Transparansi foto", "pOp", 10, 100, false), lp(-1, -2, 6))
        col.addView(check("Pakai foto sebagai crosshair", "usePhoto"))
        col.addView(check("Satu warna (siluet)", "tint"))
        if (File(filesDir, "src.png").exists()) reprocess()
    }

    private fun chipRow(key: String, items: List<String>, reproc: Boolean, after: (() -> Unit)?): View {
        val hs = HorizontalScrollView(this)
        hs.isHorizontalScrollBarEnabled = false
        val row = LinearLayout(this)
        val chips = ArrayList<TextView>()
        fun paint() {
            for (k in chips.indices) {
                val on = s.i(key) == k
                chips[k].setTextColor(if (on) Color.WHITE else C.MUTE)
                chips[k].background = if (on) Chamfer(C.RED, 0, dp(8).toFloat(), 0f) else Chamfer(C.PANEL2, C.LINE, dp(8).toFloat())
            }
        }
        for (k in items.indices) {
            val t = label(items[k], 14f, C.MUTE, true)
            t.setPadding(dp(16), dp(10), dp(16), dp(10))
            t.setOnClickListener {
                s.set(key, k)
                paint()
                if (reproc) reprocess() else apply()
                after?.invoke()
            }
            chips.add(t)
            row.addView(t, LinearLayout.LayoutParams(-2, -2).also { it.rightMargin = dp(8) })
        }
        paint()
        hs.addView(row)
        return hs
    }

    private fun colors(): View {
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        val row = LinearLayout(this)
        val list = intArrayOf(0xFF39FF88.toInt(), 0xFFFF1744.toInt(), 0xFFFFE600.toInt(), 0xFF00E5FF.toInt(),
            0xFFFF4DFF.toInt(), 0xFFFFFFFF.toInt(), 0xFF000000.toInt())
        for (c in list) {
            val v = View(this)
            val g = GradientDrawable()
            g.shape = GradientDrawable.OVAL
            g.setColor(c)
            g.setStroke(dp(2), C.LINE)
            v.background = g
            v.setOnClickListener { s.set("color", c); apply() }
            row.addView(v, LinearLayout.LayoutParams(0, dp(40), 1f).also { it.setMargins(dp(3), 0, dp(3), 0) })
        }
        col.addView(row)
        col.addView(label("Geser untuk warna lain", 12f, C.MUTE), lp(-1, -2, 8))
        val hue = SeekBar(this)
        hue.max = 360
        hue.progressTintList = ColorStateList.valueOf(C.RED)
        hue.thumbTintList = ColorStateList.valueOf(C.RED)
        hue.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar?, p: Int, user: Boolean) {
                if (user) { s.set("color", Color.HSVToColor(floatArrayOf(p.toFloat(), 1f, 1f))); apply() }
            }
            override fun onStartTrackingTouch(bar: SeekBar?) {}
            override fun onStopTrackingTouch(bar: SeekBar?) {}
        })
        col.addView(hue)
        return col
    }

    private fun seek(name: String, key: String, lo: Int, hi: Int, reproc: Boolean): View {
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        val tv = label("", 13f, C.TEXT, true)
        fun upd() { tv.text = name + ":  " + s.i(key) }
        upd()
        val sb = SeekBar(this)
        sb.max = hi - lo
        sb.progress = (s.i(key) - lo).coerceIn(0, hi - lo)
        sb.progressTintList = ColorStateList.valueOf(C.RED)
        sb.thumbTintList = ColorStateList.valueOf(C.RED)
        sb.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar?, p: Int, user: Boolean) {
                s.set(key, p + lo); upd(); if (!reproc) apply()
            }
            override fun onStartTrackingTouch(bar: SeekBar?) {}
            override fun onStopTrackingTouch(bar: SeekBar?) { if (reproc) reprocess() }
        })
        col.addView(tv)
        col.addView(sb)
        return col
    }

    private fun check(text: String, key: String): CheckBox {
        val c = CheckBox(this)
        c.text = text
        c.setTextColor(C.TEXT)
        c.buttonTintList = ColorStateList.valueOf(C.RED)
        c.isChecked = s.b(key)
        c.setOnCheckedChangeListener { _, v -> s.set(key, if (v) 1 else 0); apply() }
        return c
    }

    // ================= MONITOR =================
    private fun buildMonitor(col: LinearLayout) {
        header(col, "MONITOR PERANGKAT")
        val ramT = label("", 14f, C.TEXT, true)
        val ramB = Bar(this)
        val stoT = label("", 14f, C.TEXT, true)
        val stoB = Bar(this)
        val batT = label("", 14f, C.TEXT, true)
        val batB = Bar(this)
        val cpuT = label("", 14f, C.TEXT, true)
        val thT = label("", 14f, C.TEXT, true)
        val pingT = label("PING: mengukur...", 14f, C.TEXT, true)
        val items = listOf(Pair(ramT, ramB), Pair(stoT, stoB), Pair(batT, batB))
        for (p in items) {
            val c = card()
            c.addView(p.first)
            c.addView(p.second, LinearLayout.LayoutParams(-1, dp(8)).also { it.topMargin = dp(8) })
            col.addView(c, lp(-1, -2, 12))
        }
        val c2 = card()
        c2.addView(cpuT)
        c2.addView(thT, lp(-1, -2, 8))
        c2.addView(pingT, lp(-1, -2, 8))
        c2.addView(label("Perangkat: " + Build.MANUFACTURER + " " + Build.MODEL + "  •  Android " + Build.VERSION.RELEASE, 12f, C.MUTE), lp(-1, -2, 8))
        col.addView(c2, lp(-1, -2, 12))
        col.addView(label("Dengan Shizuku aktif, persentase CPU dibaca lewat shell. Tanpa Shizuku hanya core + frekuensi.", 11f, C.MUTE), lp(-1, -2, 10))
        var n = 0
        val r = object : Runnable {
            override fun run() {
                val (u, t, p) = Stats.ram(this@MainActivity)
                ramT.text = "RAM:  $u / $t MB  ($p%)"; ramB.pct = p; ramB.invalidate()
                val (su, stt, sp) = Stats.storage()
                stoT.text = "PENYIMPANAN:  $su / $stt GB  ($sp%)"; stoB.pct = sp; stoB.col = C.CYAN; stoB.invalidate()
                val (bp, bt) = Stats.battery(this@MainActivity)
                batT.text = "BATERAI:  $bp%  •  " + "%.1f".format(bt) + "°C"; batB.pct = bp; batB.col = C.GREEN; batB.invalidate()
                val cpuSz = if (ShizukuHelper.available() && ShizukuHelper.permissionGranted()) {
                    val p = ShizukuHelper.cpuPercent()
                    if (p >= 0) "CPU:  $p%  •  " + Stats.cpu() else "CPU:  " + Stats.cpu()
                } else "CPU:  " + Stats.cpu() + "  (aktifkan Shizuku untuk %)"
                cpuT.text = cpuSz
                thT.text = "STATUS SUHU:  " + Stats.thermal(this@MainActivity)
                n++
                if (n % 2 == 1) Stats.ping { ms -> pingT.text = if (ms < 0) "PING:  tidak terhubung" else "PING:  $ms ms" }
                hd.postDelayed(this, 2000)
            }
        }
        monitor = r
        r.run()
    }

    // ================= SETELAN =================
    private fun buildSettings(col: LinearLayout) {
        header(col, "PENGATURAN")
        col.addView(section("BENTUK GAMBAR"), lp(-2, -2, 20))
        col.addView(label("Berlaku untuk semua gambar di aplikasi: foto profil, ikon game, dan lainnya.", 12f, C.MUTE), lp(-1, -2, 8))
        col.addView(chipRow("imgShape", listOf("Lingkaran", "Kotak"), false) { showTab(3) }, lp(-1, -2, 10))
        val av = ShapeImageView(this, s)
        av.setImageResource(R.drawable.elaina)
        col.addView(av, lp(dp(96), dp(96), 12))

        col.addView(section("MODE FOKUS"), lp(-2, -2, 24))
        col.addView(label("Saat Game Turbo menyala, notifikasi dibungkam (hanya alarm yang bunyi). Kembali normal saat dimatikan.", 12f, C.MUTE), lp(-1, -2, 8))
        col.addView(check("Aktifkan mode fokus", "focus"))
        val nm = getSystemService(NotificationManager::class.java)
        val dnd = nm.isNotificationPolicyAccessGranted
        col.addView(label("Izin Jangan Ganggu: " + if (dnd) "AKTIF" else "BELUM AKTIF", 13f, if (dnd) C.GREEN else C.RED, true), lp(-1, -2, 8))
        if (!dnd) col.addView(rogBtn("BERI IZIN JANGAN GANGGU", false) { startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)) }, lp(-1, -2, 8))

        col.addView(section("SCREENSHOT"), lp(-2, -2, 24))
        col.addView(label("Android akan meminta izin rekam layar setiap kali START ditekan. Pilih Seluruh layar.", 12f, C.MUTE), lp(-1, -2, 8))
        col.addView(check("Aktifkan screenshot di panel game", "shot"))

        col.addView(section("IZIN"), lp(-2, -2, 24))
        val ov = Settings.canDrawOverlays(this)
        col.addView(label("Tampil di atas aplikasi lain: " + if (ov) "AKTIF" else "BELUM AKTIF", 13f, if (ov) C.GREEN else C.RED, true), lp(-1, -2, 8))
        if (!ov) col.addView(rogBtn("BERI IZIN OVERLAY", true) { startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))) }, lp(-1, -2, 8))

        col.addView(rogBtn("RESET SEMUA PENGATURAN", false) {
            s.reset()
            File(filesDir, "cut.png").delete()
            File(filesDir, "src.png").delete()
            OverlayService.instance?.refresh()
            showTab(3)
        }, lp(-1, -2, 24))
        col.addView(label("ELAINA Optimasi v1.0", 11f, C.MUTE), lp(-1, -2, 12))
    }

    // ================= FOTO =================
    private fun loadPhoto(u: Uri) {
        ex.execute {
            try {
                val o = BitmapFactory.Options()
                o.inJustDecodeBounds = true
                contentResolver.openInputStream(u)?.use { BitmapFactory.decodeStream(it, null, o) }
                var ss = 1
                while (maxOf(o.outWidth, o.outHeight) / ss > 1100) ss *= 2
                val o2 = BitmapFactory.Options()
                o2.inSampleSize = ss
                var bmp: Bitmap = contentResolver.openInputStream(u)?.use { BitmapFactory.decodeStream(it, null, o2) }
                    ?: throw Exception("decode")
                val deg = try {
                    contentResolver.openInputStream(u)?.use {
                        when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)) {
                            6 -> 90
                            3 -> 180
                            8 -> 270
                            else -> 0
                        }
                    } ?: 0
                } catch (e: Exception) { 0 }
                if (deg != 0) {
                    val m = Matrix()
                    m.postRotate(deg.toFloat())
                    bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
                }
                val big = maxOf(bmp.width, bmp.height)
                if (big > 560) {
                    val k = 560f / big
                    bmp = Bitmap.createScaledBitmap(bmp, (bmp.width * k).toInt().coerceAtLeast(1), (bmp.height * k).toInt().coerceAtLeast(1), true)
                }
                FileOutputStream(File(filesDir, "src.png")).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
                s.set("hasBg", 0)
                s.set("usePhoto", 1)
                doProcess()
                runOnUiThread { if (tab == 1) showTab(1) }
            } catch (e: Exception) {
                runOnUiThread { toast("Foto tidak bisa dibuka. Coba foto JPG atau PNG lain.") }
            }
        }
    }

    private fun reprocess() { ex.execute { doProcess() } }

    private fun doProcess() {
        try {
            val f = File(filesDir, "src.png")
            if (!f.exists()) return
            val src = BitmapFactory.decodeFile(f.path) ?: return
            val bg = if (s.b("hasBg")) s.i("bgColor") else null
            val r = Bg.process(src, s.i("tol"), s.i("feather"), s.i("mode"), bg)
            val cut = r.second
            val cf = File(filesDir, "cut.png")
            if (cut != null) FileOutputStream(cf).use { cut.compress(Bitmap.CompressFormat.PNG, 100, it) } else cf.delete()
            runOnUiThread {
                pick?.bmp = r.first
                pick?.invalidate()
                preview?.photo = cut
                if (cut == null) toast("Semua area terhapus. Turunkan toleransi atau pilih warna latar lain.")
                apply()
            }
        } catch (e: Exception) {
            runOnUiThread { toast("Gagal memproses foto.") }
        }
    }

    private fun pickBg(x: Int, y: Int) {
        ex.execute {
            val src = BitmapFactory.decodeFile(File(filesDir, "src.png").path) ?: return@execute
            s.set("bgColor", src.getPixel(x.coerceIn(0, src.width - 1), y.coerceIn(0, src.height - 1)))
            s.set("hasBg", 1)
            doProcess()
        }
    }
}

__XH_EOF__

mkdir -p "app/src/main/java/com/crosshair/pro"
cat > "app/src/main/java/com/crosshair/pro/OverlayService.kt" <<'__XH_EOF__'
package com.crosshair.pro

import android.app.*
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.Icon
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.MediaStore
import android.util.DisplayMetrics
import android.view.Display
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

class OverlayService : Service() {
    companion object { @JvmField var instance: OverlayService? = null }

    private val h = Handler(Looper.getMainLooper())
    private lateinit var wm: WindowManager
    private lateinit var s: Spec
    private var xh: CrosshairView? = null
    private var root: LinearLayout? = null
    private var body: LinearLayout? = null
    private var handleTv: TextView? = null
    private var ramT: TextView? = null
    private var cpuT: TextView? = null
    private var batT: TextView? = null
    private var pingT: TextView? = null
    private var ramBar: Bar? = null
    private var ovBtn: TextView? = null
    private var focusBtn: TextView? = null
    private val chips = ArrayList<TextView>()
    private val chipVals = intArrayOf(0, 1, 2, 3, 5)
    private var open = false
    private var added = false
    private var tickN = 0
    private var prevFilter = -1
    private var projection: MediaProjection? = null
    private var vd: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var shotBusy = false
    private var closing = false

    private val tick = object : Runnable {
        override fun run() {
            if (open) updateStats()
            h.postDelayed(this, 2000)
        }
    }

    override fun onBind(i: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        s = Spec(this)
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(i: Intent?, f: Int, id: Int): Int {
        if (i?.action == "STOP") { stopSelf(); return START_NOT_STICKY }
        val code = i?.getIntExtra("code", 0) ?: 0
        val data: Intent? = i?.getParcelableExtra("data")
        val proj = data != null && code == Activity.RESULT_OK
        startFg(proj)
        if (!added) {
            addViews()
            applyFocus(s.b("focus"))
            h.post(tick)
        }
        if (proj && projection == null && data != null) initProjection(code, data)
        return START_NOT_STICKY
    }

    private fun toast(t: String) { h.post { Toast.makeText(this, t, Toast.LENGTH_LONG).show() } }

    private fun startFg(proj: Boolean) {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("xh", "ELAINA Game Turbo", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, OverlayService::class.java).setAction("STOP"), PendingIntent.FLAG_IMMUTABLE)
        val n = Notification.Builder(this, "xh")
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("ELAINA Game Turbo aktif")
            .setContentText("Ketuk untuk membuka aplikasi")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(Icon.createWithResource(this, R.drawable.ic_stat), "Matikan", stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            var t = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            if (proj) t = t or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            startForeground(1, n, t)
        } else if (proj) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(1, n)
        }
    }

    private fun addViews() {
        try {
            val d = resources.displayMetrics.density
            val size = (300 * d).toInt()
            val v = CrosshairView(this, s)
            v.photo = Store.cut(this)
            val lp = WindowManager.LayoutParams(
                size, size, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            )
            lp.gravity = Gravity.CENTER
            lp.x = (s.i("offX") * d).toInt()
            lp.y = (s.i("offY") * d).toInt()
            wm.addView(v, lp)
            xh = v
            v.visibility = if (s.b("ovOn")) View.VISIBLE else View.INVISIBLE
            buildPanel()
            val plp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            )
            plp.gravity = Gravity.START or Gravity.CENTER_VERTICAL
            wm.addView(root, plp)
            added = true
        } catch (e: Exception) {
            toast("Gagal menampilkan overlay. Pastikan izin Tampil di atas aplikasi lain aktif.")
            stopSelf()
        }
    }

    fun refresh() {
        val v = xh ?: return
        val d = resources.displayMetrics.density
        v.photo = Store.cut(this)
        v.visibility = if (s.b("ovOn")) View.VISIBLE else View.INVISIBLE
        try {
            val lp = v.layoutParams as WindowManager.LayoutParams
            lp.x = (s.i("offX") * d).toInt()
            lp.y = (s.i("offY") * d).toInt()
            wm.updateViewLayout(v, lp)
        } catch (e: Exception) { }
        v.invalidate()
    }

    private fun paintChips() {
        for (k in chips.indices) {
            val on = s.i("shape") == chipVals[k] && !s.b("usePhoto")
            chips[k].setTextColor(if (on) Color.WHITE else C.MUTE)
            chips[k].background = if (on) Chamfer(C.RED, 0, dp(6).toFloat(), 0f) else Chamfer(C.PANEL2, C.LINE, dp(6).toFloat())
        }
    }

    private fun paintToggles() {
        ovBtn?.text = if (s.b("ovOn")) "CROSSHAIR: ON" else "CROSSHAIR: OFF"
        focusBtn?.text = if (s.b("focus")) "FOKUS: ON" else "FOKUS: OFF"
    }

    private fun resize(d: Int) {
        if (s.b("usePhoto")) { toast("Ukuran foto crosshair diatur di aplikasi ELAINA."); return }
        s.set("len", (s.i("len") + 2 * d).coerceIn(4, 50))
        s.set("th", (s.i("th") + d).coerceIn(1, 12))
        s.set("ring", (s.i("ring") + 2 * d).coerceIn(8, 60))
        s.set("dotSize", (s.i("dotSize") + d).coerceIn(1, 16))
        refresh()
    }

    private fun buildPanel() {
        val r = LinearLayout(this)
        r.orientation = LinearLayout.HORIZONTAL
        r.gravity = Gravity.CENTER_VERTICAL
        val b = LinearLayout(this)
        b.orientation = LinearLayout.VERTICAL
        b.setPadding(dp(12), dp(12), dp(12), dp(12))
        b.background = Chamfer(0xF2101018.toInt(), C.RED, dp(14).toFloat(), 3f)
        b.visibility = View.GONE
        val t1 = label("ELAINA", 22f, Color.WHITE, true, true)
        t1.setShadowLayer(12f, 0f, 0f, C.RED)
        b.addView(t1)
        b.addView(label("GAME TURBO", 11f, C.RED, true))
        ramT = label("RAM", 12f, C.TEXT, true)
        b.addView(ramT, lp(-1, -2, 10))
        ramBar = Bar(this)
        b.addView(ramBar, LinearLayout.LayoutParams(-1, dp(6)).also { it.topMargin = dp(4) })
        cpuT = label("CPU", 12f, C.TEXT, true)
        b.addView(cpuT, lp(-1, -2, 6))
        batT = label("BAT", 12f, C.TEXT, true)
        b.addView(batT, lp(-1, -2, 4))
        pingT = label("PING", 12f, C.TEXT, true)
        b.addView(pingT, lp(-1, -2, 4))

        b.addView(label("CROSSHAIR", 11f, C.CYAN, true), lp(-1, -2, 12))
        val sr = LinearLayout(this)
        val names = listOf("Plus", "T", "X", "Cincin", "Titik")
        for (k in names.indices) {
            val t = label(names[k], 12f, C.MUTE, true)
            t.gravity = Gravity.CENTER
            t.setPadding(dp(4), dp(8), dp(4), dp(8))
            t.setOnClickListener { s.set("shape", chipVals[k]); s.set("usePhoto", 0); refresh(); paintChips() }
            chips.add(t)
            sr.addView(t, lp(0, -2, 0, 1f).also { it.setMargins(dp(2), 0, dp(2), 0) })
        }
        b.addView(sr, lp(-1, -2, 6))

        val cr = LinearLayout(this)
        val cols = intArrayOf(0xFF39FF88.toInt(), 0xFFFF1744.toInt(), 0xFFFFE600.toInt(), 0xFF00E5FF.toInt(), 0xFFFF4DFF.toInt(), 0xFFFFFFFF.toInt())
        for (c in cols) {
            val v = View(this)
            val g = GradientDrawable()
            g.shape = GradientDrawable.OVAL
            g.setColor(c)
            g.setStroke(dp(2), C.LINE)
            v.background = g
            v.setOnClickListener { s.set("color", c); refresh() }
            cr.addView(v, lp(0, dp(30), 0, 1f).also { it.setMargins(dp(3), 0, dp(3), 0) })
        }
        b.addView(cr, lp(-1, -2, 8))

        val sz = LinearLayout(this)
        sz.gravity = Gravity.CENTER_VERTICAL
        sz.addView(rogBtn("-", false) { resize(-1) }, lp(0, -2, 0, 1f))
        val ul = label("UKURAN", 12f, C.MUTE, true)
        ul.gravity = Gravity.CENTER
        sz.addView(ul, lp(0, -2, 0, 1.4f))
        sz.addView(rogBtn("+", false) { resize(1) }, lp(0, -2, 0, 1f))
        b.addView(sz, lp(-1, -2, 8))

        val tg = LinearLayout(this)
        ovBtn = rogBtn("", false) { s.set("ovOn", if (s.b("ovOn")) 0 else 1); refresh(); paintToggles() }
        focusBtn = rogBtn("", false) { val nv = if (s.b("focus")) 0 else 1; s.set("focus", nv); applyFocus(nv == 1); paintToggles() }
        ovBtn?.textSize = 12f
        focusBtn?.textSize = 12f
        tg.addView(ovBtn, lp(0, -2, 0, 1f).also { it.rightMargin = dp(4) })
        tg.addView(focusBtn, lp(0, -2, 0, 1f).also { it.leftMargin = dp(4) })
        b.addView(tg, lp(-1, -2, 10))

        b.addView(rogBtn("SCREENSHOT", true) { shot() }, lp(-1, -2, 10))
        b.addView(rogBtn("BERHENTI", false) { stopSelf() }, lp(-1, -2, 8))
        b.addView(label("Foto crosshair hanya bisa diubah di aplikasi ELAINA.", 10f, C.MUTE), lp(-1, -2, 8))

        val hd = label(">", 22f, Color.WHITE, true)
        hd.gravity = Gravity.CENTER
        hd.background = Chamfer(C.RED, 0, dp(8).toFloat(), 0f)
        hd.setOnClickListener { toggle() }
        handleTv = hd
        r.addView(b, LinearLayout.LayoutParams(dp(270), LinearLayout.LayoutParams.WRAP_CONTENT))
        r.addView(hd, LinearLayout.LayoutParams(dp(30), dp(80)))
        root = r
        body = b
        paintChips()
        paintToggles()
    }

    private fun toggle() {
        open = !open
        body?.visibility = if (open) View.VISIBLE else View.GONE
        handleTv?.text = if (open) "<" else ">"
        if (open) updateStats()
    }

    private fun updateStats() {
        val (u, t, p) = Stats.ram(this)
        ramT?.text = "RAM  $u / $t MB  ($p%)"
        ramBar?.pct = p
        ramBar?.invalidate()
        cpuT?.text = "CPU  " + Stats.cpu()
        val (bp, bt) = Stats.battery(this)
        batT?.text = "BAT  $bp%  •  " + "%.1f".format(bt) + "°C  •  " + Stats.thermal(this)
        tickN++
        if (tickN % 2 == 1) Stats.ping { ms -> pingT?.text = if (ms < 0) "PING  -" else "PING  $ms ms" }
    }

    private fun applyFocus(on: Boolean) {
        try {
            val nm = getSystemService(NotificationManager::class.java)
            if (!nm.isNotificationPolicyAccessGranted) {
                if (on) toast("Mode fokus butuh izin Jangan Ganggu. Aktifkan di Setelan aplikasi.")
                return
            }
            if (on) {
                if (prevFilter < 0) prevFilter = nm.currentInterruptionFilter
                nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALARMS)
            } else if (prevFilter >= 0) {
                nm.setInterruptionFilter(prevFilter)
                prevFilter = -1
            }
        } catch (e: Exception) { }
    }

    // ---- screenshot ----
    private fun initProjection(code: Int, data: Intent) {
        try {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val mp = mpm.getMediaProjection(code, data)
            mp.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() { if (!closing) { projection = null; vd = null } }
            }, h)
            val dm = DisplayMetrics()
            getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY).getRealMetrics(dm)
            val rd = ImageReader.newInstance(dm.widthPixels, dm.heightPixels, PixelFormat.RGBA_8888, 2)
            reader = rd
            vd = mp.createVirtualDisplay("elaina", dm.widthPixels, dm.heightPixels, dm.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, rd.surface, null, h)
            projection = mp
        } catch (e: Exception) {
            toast("Screenshot tidak bisa diaktifkan di perangkat ini.")
        }
    }

    private fun shot() {
        if (projection == null || vd == null) {
            toast("Screenshot belum aktif. Nyalakan Game Turbo dari aplikasi dan izinkan rekam layar.")
            return
        }
        if (shotBusy) return
        shotBusy = true
        root?.visibility = View.INVISIBLE
        xh?.visibility = View.INVISIBLE
        h.postDelayed({ doShot() }, 400)
    }

    private fun doShot() {
        try {
            val dm = DisplayMetrics()
            getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY).getRealMetrics(dm)
            val w = dm.widthPixels
            val hh = dm.heightPixels
            reader?.close()
            val r = ImageReader.newInstance(w, hh, PixelFormat.RGBA_8888, 2)
            reader = r
            r.setOnImageAvailableListener({ rd -> save(rd) }, h)
            vd?.resize(w, hh, dm.densityDpi)
            vd?.surface = r.surface
            h.postDelayed({ if (shotBusy) finishShot("Gagal mengambil screenshot. Coba lagi.") }, 3000)
        } catch (e: Exception) {
            finishShot("Gagal mengambil screenshot.")
        }
    }

    private fun save(rd: ImageReader) {
        if (!shotBusy) return
        var img: Image? = null
        try {
            img = rd.acquireLatestImage() ?: return
            val pl = img.planes[0]
            val ps = pl.pixelStride
            val pad = pl.rowStride - ps * img.width
            val bmp = Bitmap.createBitmap(img.width + pad / ps, img.height, Bitmap.Config.ARGB_8888)
            bmp.copyPixelsFromBuffer(pl.buffer)
            val out = Bitmap.createBitmap(bmp, 0, 0, img.width, img.height)
            val cv = ContentValues()
            cv.put(MediaStore.Images.Media.DISPLAY_NAME, "ELAINA_" + System.currentTimeMillis() + ".png")
            cv.put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            cv.put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/ELAINA")
            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cv)
            if (uri == null) { finishShot("Gagal menyimpan screenshot."); return }
            contentResolver.openOutputStream(uri)?.use { out.compress(Bitmap.CompressFormat.PNG, 100, it) }
            finishShot("Screenshot tersimpan di Galeri (Pictures/ELAINA).")
        } catch (e: Exception) {
            finishShot("Gagal menyimpan screenshot.")
        } finally {
            img?.close()
        }
    }

    private fun finishShot(msg: String) {
        shotBusy = false
        reader?.setOnImageAvailableListener(null, null)
        root?.visibility = View.VISIBLE
        xh?.visibility = if (s.b("ovOn")) View.VISIBLE else View.INVISIBLE
        toast(msg)
    }

    override fun onDestroy() {
        closing = true
        h.removeCallbacksAndMessages(null)
        applyFocus(false)
        try { xh?.let { wm.removeView(it) } } catch (e: Exception) { }
        try { root?.let { wm.removeView(it) } } catch (e: Exception) { }
        try { vd?.release() } catch (e: Exception) { }
        try { reader?.close() } catch (e: Exception) { }
        try { projection?.stop() } catch (e: Exception) { }
        xh = null; root = null; vd = null; reader = null; projection = null
        instance = null
        super.onDestroy()
    }
}

__XH_EOF__

mkdir -p "app/src/main/java/com/crosshair/pro"
cat > "app/src/main/java/com/crosshair/pro/Painter.kt" <<'__XH_EOF__'
package com.crosshair.pro

import android.content.Context
import android.graphics.*
import android.view.View

object Painter {
    fun draw(c: Canvas, cx: Float, cy: Float, sc: Float, s: Spec, photo: Bitmap?) {
        val rot = s.i("rot").toFloat()
        if (s.b("usePhoto") && photo != null) {
            val m = maxOf(photo.width, photo.height).toFloat()
            val k = s.i("pSize") * sc / m
            val w = photo.width * k
            val h = photo.height * k
            val p = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
            p.alpha = s.i("pOp") * 255 / 100
            if (s.b("tint")) p.colorFilter = PorterDuffColorFilter(s.i("color"), PorterDuff.Mode.SRC_IN)
            c.save()
            c.rotate(rot, cx, cy)
            c.drawBitmap(photo, null, RectF(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), p)
            c.restore()
            return
        }
        val shape = s.i("shape")
        val th = s.i("th") * sc
        val len = s.i("len") * sc
        val gap = s.i("gap") * sc
        val ring = s.i("ring") * sc
        val ol = maxOf(1f, sc * 0.9f)
        val col = s.i("color")
        val outline = s.b("outline")
        val angles = when (shape) {
            0, 4 -> floatArrayOf(0f, 90f, 180f, 270f)
            1 -> floatArrayOf(0f, 90f, 180f)
            2 -> floatArrayOf(45f, 135f, 225f, 315f)
            else -> floatArrayOf()
        }
        val start = if (shape == 4) ring + gap else gap
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val layer = c.saveLayerAlpha(null, s.i("op") * 255 / 100)
        c.translate(cx, cy)
        c.rotate(rot)
        if (shape == 3 || shape == 4) {
            p.style = Paint.Style.STROKE
            if (outline) { p.color = Color.BLACK; p.strokeWidth = th + ol * 2; c.drawCircle(0f, 0f, ring, p) }
            p.color = col; p.strokeWidth = th; c.drawCircle(0f, 0f, ring, p)
        }
        p.style = Paint.Style.FILL
        for (a in angles) {
            c.save()
            c.rotate(a)
            if (outline) { p.color = Color.BLACK; c.drawRect(start - ol, -th / 2 - ol, start + len + ol, th / 2 + ol, p) }
            p.color = col
            c.drawRect(start, -th / 2, start + len, th / 2, p)
            c.restore()
        }
        if (s.b("dot") || shape == 5) {
            val r = maxOf(s.i("dotSize"), 1) * sc / 2
            if (outline) { p.color = Color.BLACK; c.drawCircle(0f, 0f, r + ol, p) }
            p.color = col
            c.drawCircle(0f, 0f, r, p)
        }
        c.restoreToCount(layer)
    }
}

class CrosshairView(ctx: Context, private val spec: Spec) : View(ctx) {
    var photo: Bitmap? = null
    override fun onDraw(canvas: Canvas) {
        Painter.draw(canvas, width / 2f, height / 2f, resources.displayMetrics.density, spec, photo)
    }
}

class PickView(ctx: Context) : View(ctx) {
    var bmp: Bitmap? = null
    var onPick: ((Int, Int) -> Unit)? = null
    private val dst = RectF()
    private val p = Paint()
    override fun onDraw(c: Canvas) {
        val sq = 24
        var y = 0
        while (y < height) {
            var x = 0
            while (x < width) {
                p.color = if (((x / sq) + (y / sq)) % 2 == 0) 0xFF8A949C.toInt() else 0xFFC9D0D5.toInt()
                c.drawRect(x.toFloat(), y.toFloat(), (x + sq).toFloat(), (y + sq).toFloat(), p)
                x += sq
            }
            y += sq
        }
        val b = bmp ?: return
        val sc = minOf(width / b.width.toFloat(), height / b.height.toFloat())
        val w = b.width * sc
        val h = b.height * sc
        dst.set((width - w) / 2, (height - h) / 2, (width + w) / 2, (height + h) / 2)
        c.drawBitmap(b, null, dst, null)
    }
    override fun onTouchEvent(e: android.view.MotionEvent): Boolean {
        val b = bmp ?: return false
        if (e.action == android.view.MotionEvent.ACTION_DOWN) return true
        if (e.action == android.view.MotionEvent.ACTION_UP && dst.contains(e.x, e.y)) {
            val x = ((e.x - dst.left) / dst.width() * b.width).toInt().coerceIn(0, b.width - 1)
            val y = ((e.y - dst.top) / dst.height() * b.height).toInt().coerceIn(0, b.height - 1)
            onPick?.invoke(x, y)
            performClick()
        }
        return true
    }
    override fun performClick(): Boolean = super.performClick()
}

__XH_EOF__

mkdir -p "app/src/main/java/com/crosshair/pro"
cat > "app/src/main/java/com/crosshair/pro/ShizukuHelper.kt" <<'__XH_EOF__'
package com.crosshair.pro

import android.content.Context
import android.content.pm.PackageManager
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader

object ShizukuHelper {
    private const val REQ = 1001

    fun available(): Boolean = try {
        Shizuku.pingBinder()
    } catch (_: Exception) { false }

    fun permissionGranted(): Boolean = try {
        Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (_: Exception) { false }

    fun requestPermission(listener: Shizuku.OnRequestPermissionResultListener) {
        try {
            if (Shizuku.isPreV11()) return
            Shizuku.addRequestPermissionResultListener(listener)
            Shizuku.requestPermission(REQ)
        } catch (_: Exception) { }
    }

    fun statusText(): String = when {
        !available() -> "Shizuku tidak aktif"
        !permissionGranted() -> "Shizuku aktif • izin belum diberikan"
        else -> "Shizuku siap"
    }

    /** Run shell command via Shizuku. Returns stdout or error message. */
    fun shell(cmd: String): String {
        if (!available() || !permissionGranted()) return "ERR:Shizuku"
        return try {
            val proc = Shizuku.newProcess(arrayOf("sh", "-c", cmd), null, null)
            val out = BufferedReader(InputStreamReader(proc.inputStream)).readText()
            val err = BufferedReader(InputStreamReader(proc.errorStream)).readText()
            proc.waitFor()
            if (out.isNotBlank()) out.trim() else err.trim().ifBlank { "OK" }
        } catch (e: Exception) {
            "ERR:${e.message}"
        }
    }

    fun tap(x: Int, y: Int): Boolean {
        val r = shell("input tap $x $y")
        return !r.startsWith("ERR")
    }

    fun forceStop(pkg: String): Boolean {
        val r = shell("am force-stop $pkg")
        return !r.startsWith("ERR")
    }

    /** Best-effort: kill background apps except system & self */
    fun cleanRam(ctx: Context, keep: Set<String> = emptySet()): Int {
        if (!available() || !permissionGranted()) return -1
        var n = 0
        try {
            val pm = ctx.packageManager
            val self = ctx.packageName
            val apps = pm.getInstalledApplications(0)
            for (ai in apps) {
                val p = ai.packageName
                if (p == self || p.startsWith("android.") || p.startsWith("com.android.") ||
                    p.contains("shizuku") || keep.contains(p)) continue
                if ((ai.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0) continue
                if (forceStop(p)) n++
            }
        } catch (_: Exception) { }
        return n
    }

    fun cpuPercent(): Int {
        // Read /proc/stat twice briefly via shell for a rough usage
        return try {
            val a = shell("cat /proc/stat | head -1")
            Thread.sleep(120)
            val b = shell("cat /proc/stat | head -1")
            fun parse(line: String): LongArray {
                val p = line.trim().split(Regex("\\s+"))
                if (p.size < 5 || p[0] != "cpu") return longArrayOf(0, 0)
                val nums = p.drop(1).mapNotNull { it.toLongOrNull() }
                val idle = (nums.getOrNull(3) ?: 0) + (nums.getOrNull(4) ?: 0)
                val total = nums.sum()
                return longArrayOf(idle, total)
            }
            val pa = parse(a)
            val pb = parse(b)
            val idle = pb[0] - pa[0]
            val total = pb[1] - pa[1]
            if (total <= 0) 0 else ((total - idle) * 100 / total).toInt().coerceIn(0, 100)
        } catch (_: Exception) { -1 }
    }

    fun animScale(scale: String) {
        shell("settings put global window_animation_scale $scale")
        shell("settings put global transition_animation_scale $scale")
        shell("settings put global animator_duration_scale $scale")
    }
}

__XH_EOF__

mkdir -p "app/src/main/java/com/crosshair/pro"
cat > "app/src/main/java/com/crosshair/pro/Spec.kt" <<'__XH_EOF__'
package com.crosshair.pro

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File

class Spec(ctx: Context) {
    private val p: SharedPreferences = ctx.getSharedPreferences("xh", Context.MODE_PRIVATE)
    companion object {
        val D = mapOf(
            "shape" to 0, "color" to 0xFF39FF88.toInt(), "len" to 14, "th" to 3, "gap" to 5,
            "rot" to 0, "op" to 100, "outline" to 1, "dot" to 0, "dotSize" to 3, "ring" to 22,
            "usePhoto" to 0, "pSize" to 70, "pOp" to 100, "tint" to 0, "tol" to 40,
            "feather" to 1, "mode" to 0, "offX" to 0, "offY" to 0, "hasBg" to 0, "bgColor" to 0,
            "imgShape" to 0, "ovOn" to 1, "focus" to 1, "shot" to 1,
            // Shizuku / turbo
            "turboCps" to 12, "turboOn" to 0, "animSmooth" to 0
        )
    }
    fun i(k: String): Int = p.getInt(k, D[k] ?: 0)
    fun b(k: String): Boolean = i(k) == 1
    fun set(k: String, v: Int) { p.edit().putInt(k, v).apply() }
    fun pins(): MutableSet<String> = p.getStringSet("pins", emptySet())!!.toMutableSet()
    fun setPins(v: Set<String>) { p.edit().putStringSet("pins", HashSet(v)).apply() }
    fun reset() { p.edit().clear().apply() }
}

object Store {
    fun cut(c: Context): Bitmap? {
        val f = File(c.filesDir, "cut.png")
        return if (f.exists()) BitmapFactory.decodeFile(f.path) else null
    }
}

__XH_EOF__

mkdir -p "app/src/main/java/com/crosshair/pro"
cat > "app/src/main/java/com/crosshair/pro/Stats.kt" <<'__XH_EOF__'
package com.crosshair.pro

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket

object Stats {
    fun ram(c: Context): Triple<Long, Long, Int> {
        val am = c.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        val t = mi.totalMem / 1048576
        val u = (mi.totalMem - mi.availMem) / 1048576
        return Triple(u, t, if (t > 0) (u * 100 / t).toInt() else 0)
    }

    fun battery(c: Context): Pair<Int, Float> {
        val i = c.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val l = i?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val sc = i?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val t = (i?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0) / 10f
        return Pair(if (l >= 0 && sc > 0) l * 100 / sc else 0, t)
    }

    fun storage(): Triple<Long, Long, Int> {
        return try {
            val st = StatFs(Environment.getDataDirectory().path)
            val total = st.blockCountLong * st.blockSizeLong
            val free = st.availableBlocksLong * st.blockSizeLong
            val used = total - free
            Triple(used / 1073741824, total / 1073741824, if (total > 0) (used * 100 / total).toInt() else 0)
        } catch (e: Exception) { Triple(0L, 0L, 0) }
    }

    fun cpu(): String {
        val n = Runtime.getRuntime().availableProcessors()
        var mx = 0L
        for (k in 0 until n) {
            try {
                val v = File("/sys/devices/system/cpu/cpu$k/cpufreq/scaling_cur_freq").readText().trim().toLong()
                if (v > mx) mx = v
            } catch (e: Exception) { }
        }
        return if (mx > 0) "$n core  •  " + "%.2f".format(mx / 1000000.0) + " GHz" else "$n core"
    }

    fun thermal(c: Context): String {
        return try {
            val pm = c.getSystemService(Context.POWER_SERVICE) as PowerManager
            when (pm.currentThermalStatus) {
                0 -> "Normal"
                1 -> "Hangat"
                2 -> "Panas ringan"
                3 -> "Panas"
                4 -> "Sangat panas"
                else -> "Kritis"
            }
        } catch (e: Exception) { "-" }
    }

    fun ping(cb: (Int) -> Unit) {
        Thread {
            var ms = -1
            try {
                val t = System.nanoTime()
                val so = Socket()
                so.connect(InetSocketAddress("8.8.8.8", 53), 1500)
                so.close()
                ms = ((System.nanoTime() - t) / 1000000).toInt()
            } catch (e: Exception) { }
            val r = ms
            Handler(Looper.getMainLooper()).post { cb(r) }
        }.start()
    }
}

__XH_EOF__

mkdir -p "app/src/main/java/com/crosshair/pro"
cat > "app/src/main/java/com/crosshair/pro/TurboTap.kt" <<'__XH_EOF__'
package com.crosshair.pro

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Floating turbo-tap button. When active, spams taps at its center via Shizuku.
 */
class TurboTap(private val ctx: Context) {
    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val h = Handler(Looper.getMainLooper())
    private val running = AtomicBoolean(false)
    private var view: FrameLayout? = null
    private var label: TextView? = null
    private var cps = 12
    private var px = 0
    private var py = 0

    fun show(cps: Int = 12) {
        this.cps = cps.coerceIn(3, 30)
        if (view != null) return
        val fl = FrameLayout(ctx)
        val tv = TextView(ctx).apply {
            text = "TAP"
            setTextColor(Color.WHITE)
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(24, 24, 24, 24)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xE0FF1744.toInt())
            }
        }
        label = tv
        fl.addView(tv, FrameLayout.LayoutParams(140, 140, Gravity.CENTER))
        val type = if (android.os.Build.VERSION.SDK_INT >= 26)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 80
            y = 400
        }
        var lastX = 0f; var lastY = 0f; var moved = false
        fl.setOnTouchListener { v, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    lastX = e.rawX; lastY = e.rawY; moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (e.rawX - lastX).toInt()
                    val dy = (e.rawY - lastY).toInt()
                    if (kotlin.math.abs(dx) > 4 || kotlin.math.abs(dy) > 4) moved = true
                    lp.x += dx; lp.y += dy
                    lastX = e.rawX; lastY = e.rawY
                    try { wm.updateViewLayout(v, lp) } catch (_: Exception) {}
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) toggle()
                    true
                }
                else -> false
            }
        }
        view = fl
        try {
            wm.addView(fl, lp)
            updatePos()
        } catch (_: Exception) {
            view = null
        }
    }

    fun hide() {
        stop()
        view?.let {
            try { if (it.isAttachedToWindow) wm.removeView(it) } catch (_: Exception) {}
        }
        view = null
        label = null
    }

    private fun toggle() {
        if (running.get()) stop() else start()
    }

    private fun start() {
        if (!ShizukuHelper.available() || !ShizukuHelper.permissionGranted()) {
            label?.text = "NO SZ"
            return
        }
        running.set(true)
        label?.text = "ON"
        label?.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(0xE000E676.toInt())
        }
        val delay = (1000L / cps).coerceAtLeast(33L)
        val loop = object : Runnable {
            override fun run() {
                if (!running.get()) return
                updatePos()
                // Tap slightly above center so finger/button doesn't block
                ShizukuHelper.tap(px, py - 8)
                h.postDelayed(this, delay)
            }
        }
        h.post(loop)
    }

    private fun stop() {
        running.set(false)
        label?.text = "TAP"
        label?.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(0xE0FF1744.toInt())
        }
    }

    private fun updatePos() {
        val v = view ?: return
        val loc = IntArray(2)
        v.getLocationOnScreen(loc)
        px = loc[0] + v.width / 2
        py = loc[1] + v.height / 2
    }

    fun isShowing(): Boolean = view != null
}

__XH_EOF__

mkdir -p "app/src/main/java/com/crosshair/pro"
cat > "app/src/main/java/com/crosshair/pro/Ui.kt" <<'__XH_EOF__'
package com.crosshair.pro

import android.content.Context
import android.graphics.*
import android.graphics.drawable.Drawable
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

object C {
    val BG = 0xFF08080D.toInt()
    val PANEL = 0xFF13131B.toInt()
    val PANEL2 = 0xFF1B1B27.toInt()
    val LINE = 0xFF2C2C3D.toInt()
    val RED = 0xFFFF1744.toInt()
    val CYAN = 0xFF00E5FF.toInt()
    val TEXT = 0xFFF4F4FA.toInt()
    val MUTE = 0xFF8E8EA8.toInt()
    val GREEN = 0xFF39FF88.toInt()
}

fun Context.dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

class Chamfer(private val fill: Int, private val stroke: Int, private val cut: Float, private val sw: Float = 2f) : Drawable() {
    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private val path = Path()
    override fun draw(c: Canvas) {
        val h = sw / 2
        val l = bounds.left + h
        val t = bounds.top + h
        val r = bounds.right - h
        val b = bounds.bottom - h
        path.reset()
        path.moveTo(l + cut, t); path.lineTo(r, t); path.lineTo(r, b - cut)
        path.lineTo(r - cut, b); path.lineTo(l, b); path.lineTo(l, t + cut); path.close()
        p.style = Paint.Style.FILL; p.color = fill; c.drawPath(path, p)
        if (sw > 0f && stroke != 0) { p.style = Paint.Style.STROKE; p.strokeWidth = sw; p.color = stroke; c.drawPath(path, p) }
    }
    override fun setAlpha(a: Int) {}
    override fun setColorFilter(cf: ColorFilter?) {}
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}

fun Context.label(t: String, sp: Float = 14f, color: Int = C.TEXT, bold: Boolean = false, italic: Boolean = false): TextView {
    val v = TextView(this)
    v.text = t
    v.textSize = sp
    v.setTextColor(color)
    val st = if (bold && italic) Typeface.BOLD_ITALIC else if (bold) Typeface.BOLD else if (italic) Typeface.ITALIC else Typeface.NORMAL
    v.typeface = Typeface.create("sans-serif-condensed", st)
    return v
}

fun Context.rogBtn(t: String, primary: Boolean, onClick: () -> Unit): TextView {
    val v = label(t, 15f, if (primary) Color.WHITE else C.TEXT, true)
    v.gravity = Gravity.CENTER
    v.setPadding(dp(16), dp(12), dp(16), dp(12))
    v.background = if (primary) Chamfer(C.RED, 0xFFFF7A93.toInt(), dp(10).toFloat()) else Chamfer(C.PANEL2, C.LINE, dp(10).toFloat())
    v.setOnClickListener { onClick() }
    return v
}

fun Context.card(pad: Int = 14): LinearLayout {
    val l = LinearLayout(this)
    l.orientation = LinearLayout.VERTICAL
    l.setPadding(dp(pad), dp(pad), dp(pad), dp(pad))
    l.background = Chamfer(C.PANEL, C.LINE, dp(12).toFloat())
    return l
}

fun Context.lp(w: Int = -1, h: Int = -2, top: Int = 0, weight: Float = 0f): LinearLayout.LayoutParams {
    val p = LinearLayout.LayoutParams(w, h, weight)
    p.topMargin = dp(top)
    return p
}

fun Context.section(t: String): TextView {
    val v = label(t, 15f, Color.WHITE, true, true)
    v.setPadding(dp(14), dp(4), dp(20), dp(4))
    v.background = Chamfer(C.RED, 0, dp(8).toFloat(), 0f)
    return v
}

class Bar(ctx: Context) : View(ctx) {
    var pct = 0
    var col = C.RED
    private val p = Paint()
    override fun onDraw(c: Canvas) {
        p.color = C.PANEL2
        c.drawRect(0f, 0f, width.toFloat(), height.toFloat(), p)
        p.color = col
        c.drawRect(0f, 0f, width * pct.coerceIn(0, 100) / 100f, height.toFloat(), p)
    }
}

class ShapeImageView(ctx: Context, private val sp: Spec) : ImageView(ctx) {
    private val path = Path()
    init { scaleType = ScaleType.CENTER_CROP }
    override fun onDraw(c: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        path.reset()
        if (sp.i("imgShape") == 0) path.addOval(0f, 0f, w, h, Path.Direction.CW) else path.addRect(0f, 0f, w, h, Path.Direction.CW)
        c.save()
        c.clipPath(path)
        super.onDraw(c)
        c.restore()
    }
}

__XH_EOF__

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/elaina.xml" <<'__XH_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FF1744"
        android:pathData="M54,10c-24,0 -44,20 -44,44s20,44 44,44 44,-20 44,-44 -20,-44 -44,-44z"/>
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M54,30c-8,0 -14,6 -14,14 0,6 4,11 10,13v6h8v-6c6,-2 10,-7 10,-13 0,-8 -6,-14 -14,-14zM40,72c0,-6 6,-10 14,-10s14,4 14,10v4H40v-4z"/>
</vector>

__XH_EOF__

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/ic_fg.xml" <<'__XH_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<inset xmlns:android="http://schemas.android.com/apk/res/android"
    android:drawable="@drawable/elaina"
    android:inset="17%" />

__XH_EOF__

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/ic_stat.xml" <<'__XH_EOF__'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M11,2h2v7h-2z M11,15h2v7h-2z M2,11h7v2h-7z M15,11h7v2h-7z" />
</vector>

__XH_EOF__

mkdir -p "app/src/main/res/mipmap-anydpi-v26"
cat > "app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" <<'__XH_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/icbg" />
    <foreground android:drawable="@drawable/ic_fg" />
</adaptive-icon>

__XH_EOF__

mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/colors.xml" <<'__XH_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="icbg">#08080D</color>
</resources>

__XH_EOF__

cat > "build.gradle.kts" <<'__XH_EOF__'
plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}

__XH_EOF__

mkdir -p "gradle/wrapper"
cat > "gradle/wrapper/gradle-wrapper.properties" <<'__XH_EOF__'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists

__XH_EOF__

cat > "gradle.properties" <<'__XH_EOF__'
org.gradle.jvmargs=-Xmx2048m
android.useAndroidX=false
kotlin.code.style=official

__XH_EOF__

cat > "settings.gradle.kts" <<'__XH_EOF__'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "CrosshairPro"
include(":app")

__XH_EOF__

mkdir -p .github/workflows
cat > .github/workflows/build-apk.yml <<'__XH_EOF__'
name: Build APK

on:
  push:
    branches: [ main, master ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17

      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v3
        with:
          gradle-version: "8.5"

      - name: Build debug APK
        run: gradle assembleDebug --no-daemon --stacktrace

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: elaina-optimasi-apk
          path: app/build/outputs/apk/debug/*.apk
          if-no-files-found: error

__XH_EOF__

echo "[ELAINA] Done. Project ready."
find . -type f | head -40