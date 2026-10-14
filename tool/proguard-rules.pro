# ML Kit (lecture de texte) : classes retrouvees par leur nom au demarrage
# (registres de composants). Sans ces regles, R8 les renomme ou les supprime
# et la lecture echoue uniquement dans l'APK « release ».
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar
-keep class * extends com.google.mlkit.common.sdkinternal.ModelResource { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_**
