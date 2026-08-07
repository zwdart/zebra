package xin.dart.zebra

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "xin.dart.zebra/receive_file"

    // ---- 发送侧 SAF 直读流(不复制到缓存,直接读 content:// 源文件)----
    private val fileChannelName = "xin.dart.zebra/native_file"
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var nextHandle = 1
    private val openStreams = mutableMapOf<Int, InputStream>()
    private var pendingPickResult: MethodChannel.Result? = null
    // 组播锁:Android 不持锁时 Wi-Fi 驱动会丢弃组播帧,joinMulticast 形同虚设,
    // 局域网发现退化为纯广播,两台设备同时搜索时互相收不到心跳(一直转圈)
    private var multicastLock: WifiManager.MulticastLock? = null
    // FlutterActivity 仅继承 Activity,无 registerForActivityResult,使用传统回调
    private val filePickerRequestCode = 0x5A11

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        acquireMulticastLock()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveReceivedFile" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName") ?: "file"
                        if (bytes == null) {
                            result.error("bad_args", "bytes is null", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveReceivedFile(bytes, fileName))
                        } catch (e: Exception) {
                            result.error("save_failed", e.message, null)
                        }
                    }
                    "saveReceivedFileFromPath" -> {
                        val partPath = call.argument<String>("partPath") ?: ""
                        val fileName = call.argument<String>("fileName") ?: "file"
                        if (partPath.isEmpty()) {
                            result.error("bad_args", "partPath is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveReceivedFileFromPath(partPath, fileName))
                        } catch (e: Exception) {
                            result.error("save_failed", e.message, null)
                        }
                    }
                    "openDownloadsFolder" -> openDownloadsFolder(result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFiles" -> pickFiles(result)
                    "openRead" -> openRead(call, result)
                    "readChunk" -> readChunk(call, result)
                    "closeRead" -> closeRead(call, result)
                    "releaseAll" -> releaseAll(result)
                    else -> result.notImplemented()
                }
            }
    }

    /** 获取 Wi-Fi 组播锁,确保能收到局域网发现的组播心跳 */
    private fun acquireMulticastLock() {
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("zebra_lan_discovery").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            // 无权限/不支持时忽略,广播通道仍可用
        }
    }

    override fun onDestroy() {
        multicastLock?.let {
            runCatching { it.release() }
            multicastLock = null
        }
        openStreams.values.forEach { runCatching { it.close() } }
        openStreams.clear()
        ioExecutor.shutdown()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != filePickerRequestCode) return
        val result = pendingPickResult ?: return
        pendingPickResult = null
        if (resultCode != RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        // 多选结果在 clipData,单选在 data
        val uris = if (data.clipData != null) {
            (0 until data.clipData!!.itemCount)
                .map { data.clipData!!.getItemAt(it).uri }
        } else if (data.data != null) {
            listOf(data.data!!)
        } else {
            emptyList()
        }
        if (uris.isEmpty()) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        // 后台查询元信息(名称/大小),避免大目录查询卡 UI
        ioExecutor.execute {
            val items = uris.mapNotNull { uri -> describeUri(uri) }
            mainHandler.post { result.success(items) }
        }
    }

    /** 打开系统文件选择器(单选,仅支持单文件传输)。返回 [{uri, name, size}] 列表,空列表表示用户取消。 */
    private fun pickFiles(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("busy", "picker already open", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        startActivityForResult(intent, filePickerRequestCode)
    }

    /** 查询单个 URI 的名称与大小(后台线程调用)。 */
    private fun describeUri(uri: Uri): Map<String, Any?>? {
        var name: String? = null
        var size: Long = -1L
        runCatching {
            contentResolver.query(uri, null, null, null, null)?.use { cursor: Cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIdx >= 0) name = cursor.getString(nameIdx)
                    if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) size = cursor.getLong(sizeIdx)
                }
            }
        }
        // 部分 provider 不返回 size,退化为打开文件描述符探测
        if (size < 0) {
            runCatching {
                contentResolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
                    size = afd.length
                }
            }
        }
        if (name.isNullOrEmpty()) {
            val lastSeg = uri.lastPathSegment
            name = lastSeg?.substringAfterLast('/') ?: "file"
        }
        // 持久化 URI 读权限,支持跨重启断点续传
        runCatching {
            contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
        return mapOf("uri" to uri.toString(), "name" to name, "size" to size)
    }

    /** 打开 URI 的读取流并跳过 offset 字节,返回句柄。 */
    private fun openRead(call: MethodCall, result: MethodChannel.Result) {
        val uri = Uri.parse(call.argument<String>("uri") ?: "")
        val offset = call.argument<Int>("offset") ?: 0
        ioExecutor.execute {
            try {
                val stream = contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("openInputStream returned null")
                skipFully(stream, offset)
                val handle = nextHandle++
                openStreams[handle] = stream
                mainHandler.post { result.success(handle) }
            } catch (e: Exception) {
                mainHandler.post { result.error("open_failed", e.message, null) }
            }
        }
    }

    /** 从句柄读取最多 count 字节;EOF 返回空数组。 */
    private fun readChunk(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<Int>("handle") ?: -1
        val count = call.argument<Int>("count") ?: 0
        ioExecutor.execute {
            val stream = openStreams[handle]
            if (stream == null) {
                mainHandler.post { result.error("bad_handle", "stream not found", null) }
                return@execute
            }
            try {
                val buf = ByteArray(count.coerceAtLeast(0))
                val n = stream.read(buf)
                val bytes = if (n <= 0) ByteArray(0) else buf.copyOf(n)
                mainHandler.post { result.success(bytes) }
            } catch (e: Exception) {
                mainHandler.post { result.error("read_failed", e.message, null) }
            }
        }
    }

    /** 关闭句柄对应的流。 */
    private fun closeRead(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<Int>("handle") ?: -1
        ioExecutor.execute {
            val stream = openStreams.remove(handle)
            if (stream != null) runCatching { stream.close() }
            mainHandler.post { result.success(true) }
        }
    }

    /** 关闭全部打开流(会话清理兜底)。 */
    private fun releaseAll(result: MethodChannel.Result) {
        ioExecutor.execute {
            openStreams.values.forEach { runCatching { it.close() } }
            openStreams.clear()
            mainHandler.post { result.success(true) }
        }
    }

    /** InputStream.skip 不保证跳过全部字节,循环补齐。 */
    private fun skipFully(stream: InputStream, offset: Int) {
        var remaining = offset
        while (remaining > 0) {
            val skipped = stream.skip(remaining.toLong())
            if (skipped <= 0) {
                if (stream.read() == -1) break // 已到 EOF
                remaining--
            } else {
                remaining -= skipped.toInt()
            }
        }
    }

    /**
     * 保存接收到的文件。
     * 1) Android 10+ 通过 MediaStore 写入系统"下载"目录:无需任何权限,
     *    文件直接出现在下载里,用户可在文件管理器直接访问;返回展示路径。
     * 2) 失败时降级到应用外部目录(/storage/emulated/0/Android/data/<pkg>/files):
     *    同样无需权限;返回真实路径。
     */
    private fun saveReceivedFile(bytes: ByteArray, fileName: String): Map<String, String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                    put(
                        MediaStore.Downloads.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/zebra"
                    )
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val resolver = contentResolver
                val uri: Uri = resolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
                ) ?: throw IllegalStateException("MediaStore insert failed")

                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("openOutputStream failed")

                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)

                return mapOf("path" to "Download/zebra/$fileName")
            } catch (e: Exception) {
                // MediaStore 写入失败,降级到应用外部目录
            }
        }

        val baseDir = getExternalFilesDir(null) ?: filesDir
        val dir = File(baseDir, "zebra_received").apply { mkdirs() }
        val target = uniqueFile(dir, fileName)
        FileOutputStream(target).use { it.write(bytes) }
        return mapOf("path" to target.absolutePath)
    }

    /**
     * 将 .part 临时文件流式写入 MediaStore 下载目录(大文件专用,避免整文件读入内存 OOM)。
     * 与 [saveReceivedFile] 相同:Android 10+ 无需任何权限,文件出现在"下载/zebra"。
     * 文件名冲突时自动追加时间戳;失败时抛出异常,由 Dart 侧降级到文档目录。
     */
    private fun saveReceivedFileFromPath(partPath: String, fileName: String): Map<String, String> {
        val part = File(partPath)
        if (!part.exists()) throw IllegalStateException("part file not found: $partPath")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IllegalStateException("MediaStore requires API 29+")
        }

        val safeName = fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        var targetName = safeName
        // 重名检查:下载/zebra 已有同名文件时加时间戳,避免覆盖用户已有文件
        var i = 0
        while (true) {
            if (!fileExistsInDownloads(targetName)) break
            val dot = safeName.lastIndexOf('.')
            val base = if (dot > 0) safeName.substring(0, dot) else safeName
            val ext = if (dot > 0) safeName.substring(dot) else ""
            targetName = "${base}_${System.currentTimeMillis()}_$i$ext"
            i++
        }

        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, targetName)
            put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
            put(
                MediaStore.Downloads.RELATIVE_PATH,
                Environment.DIRECTORY_DOWNLOADS + "/zebra"
            )
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri: Uri = resolver.insert(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
        ) ?: throw IllegalStateException("MediaStore insert failed")

        try {
            // 流式复制 .part -> MediaStore,避免大文件整读内存
            part.inputStream().use { input ->
                resolver.openOutputStream(uri)?.use { output ->
                    input.copyTo(output)
                } ?: throw IllegalStateException("openOutputStream failed")
            }
        } catch (e: Exception) {
            // 写入失败:清理半成品条目,避免下载目录残留空文件
            runCatching { resolver.delete(uri, null, null) }
            throw e
        }

        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)

        return mapOf("path" to "Download/zebra/$targetName")
    }

    /** 查询 MediaStore 下载/zebra 目录是否已存在同名文件 */
    private fun fileExistsInDownloads(name: String): Boolean {
        return try {
            val projection = arrayOf(MediaStore.Downloads._ID)
            val selection = "${MediaStore.Downloads.DISPLAY_NAME} = ?"
            val selectionArgs = arrayOf(name)
            contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                null
            )?.use { cursor -> cursor.count > 0 } ?: false
        } catch (e: Exception) {
            false
        }
    }

    /** 文件名冲突时自动追加序号 */
    private fun uniqueFile(dir: File, name: String): File {
        val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        var f = File(dir, safe)
        if (!f.exists()) return f
        val dot = safe.lastIndexOf('.')
        val base = if (dot > 0) safe.substring(0, dot) else safe
        val ext = if (dot > 0) safe.substring(dot) else ""
        var i = 1
        while (true) {
            f = File(dir, "${base}_$i$ext")
            if (!f.exists()) return f
            i++
        }
    }

    /** 打开系统"下载"目录(收到文件的默认位置) */
    private fun openDownloadsFolder(result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse(
                    "content://com.android.externalstorage.documents/document/primary%3ADownload"
                )
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }
}
