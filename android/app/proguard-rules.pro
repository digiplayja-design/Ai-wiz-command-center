
# WorkManager + Room (prevent R8 from stripping generated implementations)
-keep class androidx.work.** { *; }
-keep class androidx.work.impl.** { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase { *; }
-keep class * extends androidx.room.Room { *; }
-keepattributes *Annotation*, Signature, InnerClasses
-dontwarn androidx.work.**
-dontwarn androidx.room.**
