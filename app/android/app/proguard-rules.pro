# R8 rules for the release build. Flutter's Gradle plugin adds this file to
# the release build type's ProGuard files when it exists.

# ONNX Runtime's native library finds its Java classes by name over JNI
# (ai.onnxruntime.TensorInfo, OnnxTensor, ...). R8 renamed them, and the first
# Supertonic synthesis crashed the release app with a ClassNotFoundException
# (#152). flutter_onnxruntime ships no consumer rules of its own.
-keep class ai.onnxruntime.** { *; }

# ML Kit's text recognition (#1229): Latin only, its model bundled. The
# plugin refers to the other scripts' options, whose models aren't added.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
# R8 renamed what ML Kit's text recognition finds by name, and the first
# read in a release build failed with an NPE in its pipeline (#1229).
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
