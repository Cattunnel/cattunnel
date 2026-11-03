# CatTunnel release minification (task 88). The engine AAR keeps
# com.adguard.trusttunnel.** as a whole (this app's own channels, services
# and activities live in that package and the native side binds parts of it
# by name); Flutter and each plugin carry their consumer rules; AGP keeps
# the manifest components itself. What crosses the method channels are
# primitives and string-keyed maps, so no extra keeps are needed here.
#
# Line numbers stay for readable crash traces (family workflow).
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
