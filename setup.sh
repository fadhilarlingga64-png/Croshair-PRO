#!/bin/bash
set -e
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
        versionCode = 1
        versionName = "1.0"
    }
    buildTypes { release { isMinifyEnabled = false } }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
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
    <queries>
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent>
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
        col.addView(label("Catatan: Android tidak mengizinkan aplikasi biasa membaca persentase CPU, jadi yang tampil jumlah core dan frekuensi (jika didukung perangkat), plus status suhu sistem.", 11f, C.MUTE), lp(-1, -2, 10))
        var n = 0
        val r = object : Runnable {
            override fun run() {
                val (u, t, p) = Stats.ram(this@MainActivity)
                ramT.text = "RAM:  $u / $t MB  ($p%)"; ramB.pct = p; ramB.invalidate()
                val (su, stt, sp) = Stats.storage()
                stoT.text = "PENYIMPANAN:  $su / $stt GB  ($sp%)"; stoB.pct = sp; stoB.col = C.CYAN; stoB.invalidate()
                val (bp, bt) = Stats.battery(this@MainActivity)
                batT.text = "BATERAI:  $bp%  •  " + "%.1f".format(bt) + "°C"; batB.pct = bp; batB.col = C.GREEN; batB.invalidate()
                cpuT.text = "CPU:  " + Stats.cpu()
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
            "imgShape" to 0, "ovOn" to 1, "focus" to 1, "shot" to 1
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
mkdir -p "app/src/main/res/drawable-nodpi"
base64 -d > "app/src/main/res/drawable-nodpi/elaina.jpg" <<'__XH_B64__'
/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwMDAgQDAwMEBAQFBgoGBgUFBgwICQcKDgwPDg4M
DQ0PERYTDxAVEQ0NExoTFRcYGRkZDxIbHRsYHRYYGRj/2wBDAQQEBAYFBgsGBgsYEA0QGBgYGBgY
GBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBj/wAARCAIAAgADASIA
AhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQA
AAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3
ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWm
p6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEA
AwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSEx
BhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElK
U1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3
uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD6qtoY
rezS3jT5I1CAY9BTmwWOU/KnYG8YwG5pjkgZOD7GvRbJjG2gw7VUKuMj9adxgFcD2xQZAFIAOeen
pTMjf16H9KQNXJo9rHoBznOKtFEPUfkKz0JDgnI9s/59KvJMGXDEdMcfWh6AgaJcZyMfTpTDIiIQ
B0GenellY7AoNQsh5bB+maa10E1YcsiEAgAjPAPpRlW54PFNIxkdqMk/XPU9qYWuMK9OBnpkjtVh
AuQcDHXpUZQ7gefr0qQAkEDB9DmheYKNtSRMBRwBgelZPiXV7TR/DV3qVwyhIYyeQPStIuAuTn61
4J+0P4uaz0iLw9bS4knOZQD/AAjt2rpwlF1aqicONrqlScurPN7TVm1jxDeaiw2meVnCjoBVnUGP
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
__XH_B64__
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
mkdir -p "."
cat > "build.gradle.kts" <<'__XH_EOF__'
plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
__XH_EOF__
mkdir -p "."
cat > "gradle.properties" <<'__XH_EOF__'
org.gradle.jvmargs=-Xmx2048m
android.useAndroidX=false
kotlin.code.style=official
__XH_EOF__
mkdir -p "gradle/wrapper"
cat > "gradle/wrapper/gradle-wrapper.properties" <<'__XH_EOF__'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
__XH_EOF__
mkdir -p "."
cat > "settings.gradle.kts" <<'__XH_EOF__'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "CrosshairPro"
include(":app")
__XH_EOF__
