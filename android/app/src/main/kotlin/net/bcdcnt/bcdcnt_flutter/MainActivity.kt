package net.bcdcnt.bcdcnt_flutter

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (a FlutterActivity) shares its engine with the
// audio_service foreground service, so playback survives backgrounding.
class MainActivity : AudioServiceActivity()
