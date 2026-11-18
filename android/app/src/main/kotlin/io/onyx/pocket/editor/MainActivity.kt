package io.onyx.pocket.editor

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var enableResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.onyx.pocket.editor/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "androidSdk" -> result.success(Build.VERSION.SDK_INT)
                    "requestBluetoothPermissions" -> requestBlePermissions(result)
                    "enableBluetooth" -> enableBluetooth(result)
                    "openAppSettings" -> {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestBlePermissions(result: MethodChannel.Result) {
        if (permissionResult != null) { result.error("IN_PROGRESS", "권한 요청이 진행 중입니다.", null); return }
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) { result.success(true); return }
        permissionResult = result
        requestPermissions(missing.toTypedArray(), 4601)
    }

    @Suppress("DEPRECATION")
    private fun enableBluetooth(result: MethodChannel.Result) {
        if (enableResult != null) { result.error("IN_PROGRESS", "Bluetooth 요청이 진행 중입니다.", null); return }
        val adapter = (getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        if (adapter == null) { result.success(false); return }
        if (adapter.isEnabled) { result.success(true); return }
        enableResult = result
        startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), 4602)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4601) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
            permissionResult = null
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 4602) { enableResult?.success(resultCode == RESULT_OK); enableResult = null }
    }

    override fun onDestroy() {
        permissionResult?.success(false); permissionResult = null
        enableResult?.success(false); enableResult = null
        super.onDestroy()
    }
}
