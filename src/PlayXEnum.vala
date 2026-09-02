public enum DolbyMode {
    STEREO = 0,
    PROLOGIC = 1,
    PROLOGIC2 = 2,
    SURROUND = 3,
    BYPASS = 4
}
public enum SinkBackend {
    ALSA,
    PULSE
}
public enum Preset {
    FLAT, BASS_BOOST, TREBLE_BOOST, VOCAL, ROCK, JAZZ, CLASSICAL, POP, ELECTRONIC, LOUNGE, HIFI, CINEMA
}
public enum NoiseMode {
    OFF = 0,
    LIGHT = 1,
    MEDIUM = 2,
    AGGRESSIVE = 3,
    ADAPTIVE = 4
}
public enum OsdIconKind {
    BRIGHTNESS,
    CONTRAST,
    SATURATION,
    HUE,
    GAMMA
}
public enum ChannelMode {
    STEREO,
    MONO_L,
    MONO_R,
    MONO_MIX
}