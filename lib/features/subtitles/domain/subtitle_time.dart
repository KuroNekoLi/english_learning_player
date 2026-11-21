/// Positive offsets delay cues relative to the original audio clock.
int subtitleToAudioMs(int subtitleMs, int offsetMs) => subtitleMs + offsetMs;

int audioToSubtitleMs(int audioMs, int offsetMs) => audioMs - offsetMs;
