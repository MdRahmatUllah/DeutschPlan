# R8 rules for the release build. Flutter's Gradle plugin adds this file to
# the release build type's ProGuard files when it exists.

# ONNX Runtime's native library finds its Java classes by name over JNI
# (ai.onnxruntime.TensorInfo, OnnxTensor, ...). R8 renamed them, and the first
# Supertonic synthesis crashed the release app with a ClassNotFoundException
# (#152). flutter_onnxruntime ships no consumer rules of its own.
-keep class ai.onnxruntime.** { *; }

# pdfbox-android (#1228, ADR 31) names its optional JPEG 2000 decoder, which
# isn't on the classpath: R8 would fail on the missing class. A PDF's text
# layer never needs it.
-dontwarn com.gemalto.jp2.JP2Decoder
