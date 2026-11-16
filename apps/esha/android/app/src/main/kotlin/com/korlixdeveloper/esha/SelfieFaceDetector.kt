package com.korlixdeveloper.esha

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.PointF
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceContour
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean

/** Local geometry only; photo bytes and landmarks are never stored or uploaded here. */
internal class SelfieFaceDetector {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)

    fun detectFaces(arguments: Any?, result: MethodChannel.Result) {
        val bytes = (arguments as? Map<*, *>)?.get("bytes") as? ByteArray
        if (bytes == null || bytes.isEmpty()) {
            fail(result, "invalid_arguments", "Choose a photo to preview.")
            return
        }
        if (bytes.size > MAXIMUM_ENCODED_BYTES) {
            fail(result, "image_too_large", "This photo is too large to process.")
            return
        }
        if (closed.get()) {
            fail(result, "selfie_unavailable", "Photo preview is unavailable.")
            return
        }
        if (!busy.compareAndSet(false, true)) {
            fail(result, "selfie_busy", "A photo is already being processed.")
            return
        }
        val deadline = SystemClock.elapsedRealtime() + REQUEST_BUDGET_MILLIS
        try {
            worker.execute {
                try {
                    val response = detect(bytes, deadline)
                    main.post {
                        busy.set(false)
                        if (closed.get()) {
                            result.error("selfie_unavailable", "Photo preview is unavailable.", null)
                        } else {
                            result.success(response)
                        }
                    }
                } catch (error: PreviewException) {
                    completeFailure(result, error.code, error.message ?: "Photo preview is unavailable.")
                } catch (_: TimeoutException) {
                    completeFailure(result, "detection_failed", "The photo took too long to analyze. Please try again.")
                } catch (_: Exception) {
                    // SDK exception messages can contain image details. Return only fixed text.
                    completeFailure(result, "detection_failed", "The photo could not be analyzed. Please try another photo.")
                }
            }
        } catch (_: RejectedExecutionException) {
            busy.set(false)
            fail(result, "selfie_unavailable", "Photo preview is unavailable.")
        }
    }

    fun close() {
        closed.set(true)
        // Let a bounded in-flight task finish; its detector clients close in finally.
        worker.shutdown()
    }

    private fun detect(bytes: ByteArray, deadline: Long): Map<String, Any> {
        remainingMillis(deadline)
        if (bytes.size < PNG_SIGNATURE.size || !PNG_SIGNATURE.indices.all { bytes[it] == PNG_SIGNATURE[it] }) {
            throw invalidImage()
        }
        val metadata = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, metadata)
        val width = metadata.outWidth
        val height = metadata.outHeight
        if (width <= 0 || height <= 0 || metadata.outMimeType != "image/png") {
            throw invalidImage()
        }
        if (maxOf(width, height) > MAXIMUM_IMAGE_SIDE) {
            throw PreviewException("image_too_large", "This photo is too large to process.")
        }
        val bitmap = BitmapFactory.decodeByteArray(
            bytes, 0, bytes.size,
            BitmapFactory.Options().apply {
                inScaled = false
                inPreferredConfig = Bitmap.Config.ARGB_8888
            },
        ) ?: throw invalidImage()
        if (bitmap.width != width || bitmap.height != height) throw invalidImage()
        // Flutter has normalized EXIF and mirroring into these exact PNG pixels.
        val image = InputImage.fromBitmap(bitmap, 0)
        var countDetector: FaceDetector? = null
        var contourDetector: FaceDetector? = null
        try {
            countDetector = FaceDetection.getClient(
                FaceDetectorOptions.Builder()
                    .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
                    .setContourMode(FaceDetectorOptions.CONTOUR_MODE_NONE)
                    .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
                    .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
                    .setMinFaceSize(0.05f)
                    .build(),
            )
            // Contour mode only finds the most prominent face. Count faces without it first.
            val countBudget = remainingMillis(deadline)
            val counted = Tasks.await(countDetector.process(image), countBudget, TimeUnit.MILLISECONDS)
            val response = mutableMapOf<String, Any>(
                "imageWidth" to width,
                "imageHeight" to height,
                "faceCount" to counted.size,
                "faces" to emptyList<Map<String, Any?>>(),
            )
            if (counted.size != 1) return response
            if (closed.get()) throw PreviewException("selfie_unavailable", "Photo preview is unavailable.")

            contourDetector = FaceDetection.getClient(
                FaceDetectorOptions.Builder()
                    .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
                    .setContourMode(FaceDetectorOptions.CONTOUR_MODE_ALL)
                    .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
                    .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
                    .setMinFaceSize(0.05f)
                    .build(),
            )
            val contourBudget = remainingMillis(deadline)
            val face = Tasks.await(contourDetector.process(image), contourBudget, TimeUnit.MILLISECONDS).singleOrNull()
                ?: throw invalidLandmarks()
            remainingMillis(deadline)
            response["faces"] = listOf(serialize(face, width, height))
            return response
        } finally {
            countDetector?.close()
            contourDetector?.close()
            // Do not recycle while a timed-out SDK task might still hold the bitmap.
            // It is ephemeral and can be collected when the SDK releases its reference.
        }
    }

    private fun serialize(face: Face, width: Int, height: Int): Map<String, Any?> {
        val box = face.boundingBox
        val left = unit(box.left.toDouble() / width)
        val top = unit(box.top.toDouble() / height)
        val right = unit(box.right.toDouble() / width)
        val bottom = unit(box.bottom.toDouble() / height)
        if (right <= left || bottom <= top) throw invalidLandmarks()
        return mapOf(
            "bounds" to mapOf("left" to left, "top" to top, "width" to right - left, "height" to bottom - top),
            "outerLips" to polygon(joinArcs(
                contour(face, FaceContour.UPPER_LIP_TOP),
                contour(face, FaceContour.LOWER_LIP_BOTTOM),
            ), width, height),
            "innerLips" to polygon(joinArcs(
                contour(face, FaceContour.UPPER_LIP_BOTTOM),
                contour(face, FaceContour.LOWER_LIP_TOP),
            ), width, height),
            "leftEye" to polygon(contour(face, FaceContour.LEFT_EYE), width, height),
            "rightEye" to polygon(contour(face, FaceContour.RIGHT_EYE), width, height),
            "yaw" to face.headEulerAngleY.toDouble().takeIf { it.isFinite() },
            "pitch" to face.headEulerAngleX.toDouble().takeIf { it.isFinite() },
        )
    }

    private fun contour(face: Face, type: Int): List<PointF> {
        val points = face.getContour(type)?.points ?: throw invalidLandmarks()
        if (points.size !in 2..128 || points.any { !it.x.isFinite() || !it.y.isFinite() }) {
            throw invalidLandmarks()
        }
        return points
    }

    /** Join the two lip arcs at their nearest corresponding corners, never by guessed indices. */
    private fun joinArcs(top: List<PointF>, bottom: List<PointF>): List<PointF> {
        val direct = distance(top.last(), bottom.first()) + distance(bottom.last(), top.first())
        val reversed = distance(top.last(), bottom.last()) + distance(bottom.first(), top.first())
        return top + if (direct <= reversed) bottom else bottom.asReversed()
    }

    private fun distance(a: PointF, b: PointF): Double {
        val x = a.x.toDouble() - b.x
        val y = a.y.toDouble() - b.y
        return x * x + y * y
    }

    private fun polygon(source: List<PointF>, width: Int, height: Int): List<List<Double>> {
        val points = source.map { listOf(unit(it.x.toDouble() / width), unit(it.y.toDouble() / height)) }
            .fold(mutableListOf<List<Double>>()) { output, point ->
                if (output.lastOrNull() != point) output.add(point)
                output
            }
        if (points.firstOrNull() == points.lastOrNull() && points.size > 1) points.removeAt(points.lastIndex)
        if (points.size !in 3..128) throw invalidLandmarks()
        val signedArea = points.indices.sumOf { index ->
            val next = points[(index + 1) % points.size]
            points[index][0] * next[1] - next[0] * points[index][1]
        }
        // Implicitly closed clockwise polygons in full-image upper-left coordinates.
        if (signedArea < 0) points.reverse()
        return points
    }

    private fun unit(value: Double): Double {
        if (!value.isFinite() || value < -0.000001 || value > 1.000001) throw invalidLandmarks()
        return value.coerceIn(0.0, 1.0)
    }

    private fun remainingMillis(deadline: Long): Long {
        val remaining = deadline - SystemClock.elapsedRealtime()
        if (remaining <= 0) throw TimeoutException()
        return remaining
    }

    private fun completeFailure(result: MethodChannel.Result, code: String, message: String) {
        main.post {
            busy.set(false)
            result.error(code, message, null)
        }
    }

    private fun fail(result: MethodChannel.Result, code: String, message: String) {
        main.post { result.error(code, message, null) }
    }

    private fun invalidImage() = PreviewException("invalid_image", "This photo could not be read. Choose another photo.")
    private fun invalidLandmarks() = PreviewException(
        "invalid_landmarks", "Use a clear, front-facing photo with your eyes and lips visible.",
    )

    private class PreviewException(val code: String, message: String) : Exception(message)

    private companion object {
        const val MAXIMUM_ENCODED_BYTES = 12 * 1024 * 1024
        const val MAXIMUM_IMAGE_SIDE = 1600
        const val REQUEST_BUDGET_MILLIS = 15_000L
        val PNG_SIGNATURE = byteArrayOf(137.toByte(), 80, 78, 71, 13, 10, 26, 10)
    }
}
