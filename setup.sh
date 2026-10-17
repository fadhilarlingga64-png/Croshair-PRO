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
        minSdk = 26
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
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <application
        android:label="Crosshair Pro"
        android:icon="@drawable/ic_launcher"
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
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="crosshair overlay" />
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
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.widget.*
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : Activity() {
    private lateinit var s: Spec
    private lateinit var preview: CrosshairView
    private lateinit var pick: PickView
    private lateinit var btn: Button
    private var cbUse: CheckBox? = null
    private var on = false
    private val ex = Executors.newSingleThreadExecutor()

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        s = Spec(this)
        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(dp(16), dp(24), dp(16), dp(32))

        root.addView(TextView(this).apply { text = "Crosshair Pro"; textSize = 22f })

        val box = FrameLayout(this)
        box.setBackgroundColor(0xFF222B33.toInt())
        preview = CrosshairView(this, s)
        preview.photo = Store.cut(this)
        box.addView(preview, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        root.addView(box, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(240)).apply { topMargin = dp(8) })

        btn = Button(this)
        btn.setOnClickListener { toggle() }
        root.addView(btn)
        setBtn(false)

        root.addView(head("Bentuk"))
        root.addView(spin("Bentuk", "shape", listOf("Plus", "T", "X", "Lingkaran", "Lingkaran + plus", "Titik")))
        root.addView(head("Warna"))
        root.addView(colors())
        root.addView(seek("Panjang", "len", 2, 60))
        root.addView(seek("Tebal", "th", 1, 14))
        root.addView(seek("Celah tengah", "gap", 0, 40))
        root.addView(seek("Radius cincin", "ring", 6, 60))
        root.addView(seek("Rotasi", "rot", 0, 360))
        root.addView(seek("Opasitas", "op", 10, 100))
        root.addView(seek("Ukuran titik", "dotSize", 1, 16))
        root.addView(check("Garis tepi hitam", "outline"))
        root.addView(check("Titik tengah", "dot"))

        root.addView(head("Posisi di layar (dp dari tengah)"))
        root.addView(seek("Geser X", "offX", -200, 200))
        root.addView(seek("Geser Y", "offY", -300, 300))

        root.addView(head("Foto jadi crosshair"))
        val pickBtn = Button(this)
        pickBtn.text = "Pilih foto (latar dihapus otomatis)"
        pickBtn.setOnClickListener {
            val i = Intent(Intent.ACTION_GET_CONTENT)
            i.type = "image/*"
            startActivityForResult(i, 9)
        }
        root.addView(pickBtn)
        root.addView(TextView(this).apply { text = "Ketuk bagian latar pada pratinjau untuk memilih warna latar yang dihapus." })
        pick = PickView(this)
        pick.onPick = { x, y -> pickBg(x, y) }
        root.addView(pick, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(220)))
        root.addView(spin("Mode hapus latar", "mode", listOf("Dari tepi", "Seluruh gambar"), true))
        root.addView(seek("Toleransi warna", "tol", 5, 150, true))
        root.addView(seek("Haluskan tepi", "feather", 0, 6, true))
        root.addView(seek("Ukuran foto", "pSize", 10, 280))
        root.addView(seek("Opasitas foto", "pOp", 10, 100))
        cbUse = check("Pakai foto sebagai crosshair", "usePhoto")
        root.addView(cbUse)
        root.addView(check("Satu warna (siluet)", "tint"))

        val reset = Button(this)
        reset.text = "Reset semua"
        reset.setOnClickListener {
            s.reset()
            File(filesDir, "cut.png").delete()
            File(filesDir, "src.png").delete()
            apply()
            recreate()
        }
        root.addView(reset)

        setContentView(ScrollView(this).apply { addView(root) })
        if (File(filesDir, "src.png").exists()) reprocess()
    }

    override fun onResume() {
        super.onResume()
        setBtn(OverlayService.instance != null)
    }

    private fun setBtn(v: Boolean) {
        on = v
        btn.text = if (v) "Matikan crosshair" else "Nyalakan crosshair di atas aplikasi lain"
    }

    private fun toggle() {
        if (on) {
            stopService(Intent(this, OverlayService::class.java))
            setBtn(false)
            return
        }
        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "Aktifkan izin 'Tampil di atas aplikasi lain' untuk Crosshair Pro, lalu kembali.", Toast.LENGTH_LONG).show()
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
            return
        }
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        startForegroundService(Intent(this, OverlayService::class.java))
        setBtn(true)
    }

    private fun apply() {
        preview.invalidate()
        OverlayService.instance?.refresh()
    }

    private fun head(t: String) = TextView(this).apply {
        text = t; textSize = 16f; setPadding(0, dp(18), 0, dp(4))
    }

    private fun seek(label: String, key: String, lo: Int, hi: Int, reproc: Boolean = false): View {
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        val tv = TextView(this)
        fun upd() { tv.text = "$label: ${s.i(key)}" }
        upd()
        val sb = SeekBar(this)
        sb.max = hi - lo
        sb.progress = (s.i(key) - lo).coerceIn(0, hi - lo)
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

    private fun check(label: String, key: String): CheckBox {
        val c = CheckBox(this)
        c.text = label
        c.isChecked = s.b(key)
        c.setOnCheckedChangeListener { _, v -> s.set(key, if (v) 1 else 0); apply() }
        return c
    }

    private fun spin(label: String, key: String, items: List<String>, reproc: Boolean = false): View {
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.addView(TextView(this).apply { text = label })
        val sp = Spinner(this)
        sp.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, items)
        sp.setSelection(s.i(key).coerceIn(0, items.size - 1))
        sp.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(p: AdapterView<*>?, v: View?, pos: Int, id: Long) {
                if (pos != s.i(key)) { s.set(key, pos); if (reproc) reprocess() else apply() }
            }
            override fun onNothingSelected(p: AdapterView<*>?) {}
        }
        col.addView(sp)
        return col
    }

    private fun colors(): View {
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        val row = LinearLayout(this)
        val list = intArrayOf(0xFF39FF88.toInt(), 0xFFFF3B3B.toInt(), 0xFFFFE600.toInt(), 0xFF00E5FF.toInt(),
            0xFFFF4DFF.toInt(), 0xFFFFFFFF.toInt(), 0xFF000000.toInt())
        for (c in list) {
            val v = View(this)
            v.setBackgroundColor(c)
            v.setOnClickListener { s.set("color", c); apply() }
            row.addView(v, LinearLayout.LayoutParams(0, dp(36), 1f).apply { setMargins(dp(3), dp(3), dp(3), dp(3)) })
        }
        col.addView(row)
        col.addView(TextView(this).apply { text = "Geser untuk pilih warna lain" })
        val hue = SeekBar(this)
        hue.max = 360
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

    // ---- foto ----
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(rc: Int, res: Int, d: Intent?) {
        super.onActivityResult(rc, res, d)
        val u = d?.data
        if (rc == 9 && res == RESULT_OK && u != null) loadPhoto(u)
    }

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
                var bmp = contentResolver.openInputStream(u)?.use { BitmapFactory.decodeStream(it, null, o2) }
                    ?: throw Exception("decode")
                val deg = try {
                    contentResolver.openInputStream(u)?.use {
                        when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)) {
                            6 -> 90; 3 -> 180; 8 -> 270; else -> 0
                        }
                    } ?: 0
                } catch (e: Exception) { 0 }
                if (deg != 0) {
                    val m = Matrix(); m.postRotate(deg.toFloat())
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
                runOnUiThread { cbUse?.isChecked = true }
                doProcess()
            } catch (e: Exception) {
                runOnUiThread { Toast.makeText(this, "Foto tidak bisa dibuka. Coba foto JPG atau PNG lain.", Toast.LENGTH_LONG).show() }
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
                pick.bmp = r.first
                pick.invalidate()
                preview.photo = cut
                if (cut == null) Toast.makeText(this, "Semua area terhapus. Turunkan toleransi atau pilih warna latar lain.", Toast.LENGTH_LONG).show()
                apply()
            }
        } catch (e: Exception) {
            runOnUiThread { Toast.makeText(this, "Gagal memproses foto.", Toast.LENGTH_LONG).show() }
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
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.WindowManager
import android.widget.Toast

class OverlayService : Service() {
    companion object { @JvmField var instance: OverlayService? = null }

    private var view: CrosshairView? = null
    private lateinit var wm: WindowManager
    private lateinit var spec: Spec

    override fun onBind(i: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        spec = Spec(this)
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        startFg()
        try {
            val d = resources.displayMetrics.density
            val size = (300 * d).toInt()
            val v = CrosshairView(this, spec)
            v.photo = Store.cut(this)
            val lp = WindowManager.LayoutParams(
                size, size,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            )
            lp.gravity = Gravity.CENTER
            lp.x = (spec.i("offX") * d).toInt()
            lp.y = (spec.i("offY") * d).toInt()
            wm.addView(v, lp)
            view = v
        } catch (e: Exception) {
            Toast.makeText(this, "Gagal menampilkan crosshair: izin tampil di atas aplikasi lain belum aktif.", Toast.LENGTH_LONG).show()
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") { stopSelf(); return START_NOT_STICKY }
        return START_STICKY
    }

    fun refresh() {
        val v = view ?: return
        val d = resources.displayMetrics.density
        v.photo = Store.cut(this)
        val lp = v.layoutParams as WindowManager.LayoutParams
        lp.x = (spec.i("offX") * d).toInt()
        lp.y = (spec.i("offY") * d).toInt()
        try { wm.updateViewLayout(v, lp) } catch (e: Exception) { }
        v.invalidate()
    }

    private fun startFg() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("xh", "Crosshair", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(
            this, 1, Intent(this, OverlayService::class.java).setAction("STOP"), PendingIntent.FLAG_IMMUTABLE
        )
        val n = Notification.Builder(this, "xh")
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("Crosshair aktif")
            .setContentText("Ketuk untuk mengedit")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(Icon.createWithResource(this, R.drawable.ic_stat), "Matikan", stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(1, n)
    }

    override fun onDestroy() {
        try { view?.let { wm.removeView(it) } } catch (e: Exception) { }
        view = null
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
            "feather" to 1, "mode" to 0, "offX" to 0, "offY" to 0, "hasBg" to 0, "bgColor" to 0
        )
    }
    fun i(k: String): Int = p.getInt(k, D[k] ?: 0)
    fun b(k: String): Boolean = i(k) == 1
    fun set(k: String, v: Int) { p.edit().putInt(k, v).apply() }
    fun reset() { p.edit().clear().apply() }
}

object Store {
    fun cut(c: Context): Bitmap? {
        val f = File(c.filesDir, "cut.png")
        return if (f.exists()) BitmapFactory.decodeFile(f.path) else null
    }
}
__XH_EOF__
mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/ic_launcher.xml" <<'__XH_EOF__'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="96dp" android:height="96dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#1C242C" android:pathData="M12,12m-11,0a11,11 0 1,0 22,0a11,11 0 1,0 -22,0" />
    <path android:fillColor="#39FF88" android:pathData="M11,4h2v5h-2z M11,15h2v5h-2z M4,11h5v2h-5z M15,11h5v2h-5z M11.2,11.2h1.6v1.6h-1.6z" />
</vector>
__XH_EOF__
mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/ic_stat.xml" <<'__XH_EOF__'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M11,2h2v7h-2z M11,15h2v7h-2z M2,11h7v2h-7z M15,11h7v2h-7z" />
</vector>
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
