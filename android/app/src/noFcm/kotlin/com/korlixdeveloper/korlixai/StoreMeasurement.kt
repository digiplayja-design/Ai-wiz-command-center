package com.korlixdeveloper.korlixai

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** A client without Firebase configuration can still purchase and restore normally. */
object StoreMeasurement {
    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) = result.success(null)
}
