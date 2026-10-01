# HydroCap keeps release builds unminified for now; rules kept for protobuf lite.
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
