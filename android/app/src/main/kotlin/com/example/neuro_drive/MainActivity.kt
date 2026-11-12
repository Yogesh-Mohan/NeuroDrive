package com.example.neuro_drive

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Telephony
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.neurodrive.app/native_service"
    private val SMS_PERMISSION_CODE = 4492
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingDirectSms: Triple<String, String, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasSmsPermission" -> {
                    val hasPerm = ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
                    result.success(hasPerm)
                }
                "requestSmsPermission" -> {
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.SEND_SMS), SMS_PERMISSION_CODE)
                    }
                }
                "sendDirectSms" -> {
                    val phone = call.argument<String>("phone")
                    val message = call.argument<String>("message")
                    if (phone.isNullOrEmpty() || message.isNullOrEmpty()) {
                        result.error("INVALID_ARGS", "Phone and message required", null)
                        return@setMethodCallHandler
                    }

                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
                        // Request permission and queue this SMS to dispatch as soon as granted
                        pendingDirectSms = Triple(phone, message, result)
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.SEND_SMS), SMS_PERMISSION_CODE)
                        return@setMethodCallHandler
                    }

                    sendSmsInternal(phone, message, result)
                }
                "openDefaultSmsApp" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    openDefaultSmsAppInternal(phone, message, result)
                }
                "savePdfToDownloads" -> {
                    val fileName = call.argument<String>("fileName") ?: "NeuroDrive_TripReport.pdf"
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) {
                        result.error("INVALID_ARGS", "Bytes required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        var savedPath: String
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val values = ContentValues().apply {
                                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                                put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                            }
                            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                ?: throw Exception("Failed to create download URI")
                            contentResolver.openOutputStream(uri)?.use { os ->
                                os.write(bytes)
                                os.flush()
                            }
                            savedPath = "${Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)}/$fileName"
                        } else {
                            val file = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), fileName)
                            file.writeBytes(bytes)
                            savedPath = file.absolutePath
                        }
                        result.success(savedPath)
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_FAILED", e.localizedMessage, null)
                    }
                }
                "openPdfFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("INVALID_ARGS", "File path required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(filePath)
                        if (file.exists()) {
                            val uri = FileProvider.getUriForFile(
                                this,
                                "${applicationContext.packageName}.fileprovider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/pdf")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.error("NOT_FOUND", "File does not exist at $filePath", null)
                        }
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun sendSmsInternal(phone: String, message: String, result: MethodChannel.Result) {
        try {
            val cleanPhone = phone.replace(Regex("[^0-9+]"), "")
            val smsManager: SmsManager = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    applicationContext.getSystemService(SmsManager::class.java)
                        ?: @Suppress("DEPRECATION") SmsManager.getDefault()
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getDefault()
                }
            } catch (_: Exception) {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }

            val parts = smsManager.divideMessage(message)
            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(cleanPhone, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(cleanPhone, null, message, null, null)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("SMS_FAILED", e.localizedMessage, null)
        }
    }

    private fun openDefaultSmsAppInternal(phone: String, message: String, result: MethodChannel.Result) {
        try {
            val cleanPhone = phone.replace(Regex("[^0-9+]"), "")
            val defaultSmsPackage = Telephony.Sms.getDefaultSmsPackage(this)
            val smsUri = Uri.parse("smsto:$cleanPhone")
            val intent = Intent(Intent.ACTION_SENDTO, smsUri).apply {
                putExtra("sms_body", message)
                if (!defaultSmsPackage.isNullOrEmpty()) {
                    setPackage(defaultSmsPackage)
                }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("OPEN_SMS_FAILED", e.localizedMessage, null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED

            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null

            val pendingSms = pendingDirectSms
            pendingDirectSms = null
            if (pendingSms != null) {
                if (granted) {
                    sendSmsInternal(pendingSms.first, pendingSms.second, pendingSms.third)
                } else {
                    openDefaultSmsAppInternal(pendingSms.first, pendingSms.second, pendingSms.third)
                }
            }
        }
    }
}
