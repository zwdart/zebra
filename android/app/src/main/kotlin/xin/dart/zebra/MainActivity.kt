package xin.dart.zebra

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "xin.dart.zebra/receive_file"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    "openDownloadsFolder" -> openDownloadsFolder(result)
                    else -> result.notImplemented()
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
