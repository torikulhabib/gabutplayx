
private string channel_mode_label (ChannelMode m) {
    switch (m) {
        case ChannelMode.STEREO: return "Stereo";
        case ChannelMode.MONO_L: return "Mono L";
        case ChannelMode.MONO_R: return "Mono R";
        case ChannelMode.MONO_MIX: return "Mono Mix";
        default: return "?";
    }
}

private string dolby_label (DolbyMode m) {
    switch (m) {
        case DolbyMode.STEREO: return "Stereo";
        case DolbyMode.PROLOGIC: return "Pro Logic";
        case DolbyMode.PROLOGIC2: return "Pro Logic II";
        case DolbyMode.SURROUND: return "Virtual Surround";
        case DolbyMode.BYPASS: return "Bypass";
        default: return "?";
    }
}

private string noise_label (NoiseMode m) {
    switch (m) {
        case NoiseMode.OFF: return "Off";
        case NoiseMode.LIGHT: return "Light";
        case NoiseMode.MEDIUM: return "Medium";
        case NoiseMode.AGGRESSIVE: return "Aggressive";
        case NoiseMode.ADAPTIVE: return "Adaptive";
        default: return "?";
    }
}

private static Gdk.MemoryFormat video_format_to_gdk_enum (Gst.Video.Format fmt) {
    switch (fmt) {
        case Gst.Video.Format.BGRA: return Gdk.MemoryFormat.B8G8R8A8;
        case Gst.Video.Format.RGBX: return Gdk.MemoryFormat.R8G8B8X8;
        case Gst.Video.Format.RGBA: return Gdk.MemoryFormat.R8G8B8A8;
        case Gst.Video.Format.ARGB: return Gdk.MemoryFormat.A8R8G8B8;
        case Gst.Video.Format.ABGR: return Gdk.MemoryFormat.A8B8G8R8;
        case Gst.Video.Format.RGB: return Gdk.MemoryFormat.R8G8B8;
        case Gst.Video.Format.BGR: return Gdk.MemoryFormat.B8G8R8;
        default: return Gdk.MemoryFormat.B8G8R8X8;
    }
}

private PulseAudio.SampleFormat map_gst_to_pulse (Gst.Audio.Format fmt) {
    switch (fmt) {
        case Gst.Audio.Format.S16LE: return PulseAudio.SampleFormat.S16LE;
        case Gst.Audio.Format.S24LE: return PulseAudio.SampleFormat.S24_32LE;
        case Gst.Audio.Format.S32LE: return PulseAudio.SampleFormat.S32LE;
        case Gst.Audio.Format.F32LE: return PulseAudio.SampleFormat.FLOAT32LE;
        default: return PulseAudio.SampleFormat.S16LE;
    }
}

private Alsa.PcmFormat map_gst_to_alsa (Gst.Audio.Format fmt) {
    switch (fmt) {
        case Gst.Audio.Format.S16LE: return Alsa.PcmFormat.S16_LE;
        case Gst.Audio.Format.S24LE: return Alsa.PcmFormat.S24_LE;
        case Gst.Audio.Format.S32LE: return Alsa.PcmFormat.S32_LE;
        case Gst.Audio.Format.F32LE: return Alsa.PcmFormat.FLOAT_LE;
        case Gst.Audio.Format.F64LE: return Alsa.PcmFormat.FLOAT64_LE;
        default: return Alsa.PcmFormat.S16_LE;
    }
}

private static string seconds_to_time (double secs, bool need = true) {
    uint seconds = (uint) (secs);
    uint sign = 1;
    if (seconds < 0 && need) {
        seconds = -seconds;
        sign = -1;
    }
    uint hours = seconds / 3600;
    uint min = (seconds % 3600) / 60;
    uint sec = (seconds % 60);
    if (hours > 0 || !need) {
        return ("%u:%02u:%02u".printf (sign * hours, min, sec));
    } else {
        return ("%02u:%02u".printf (sign * min, sec));
    }
}

private Gee.ArrayList<string> get_tags (Gst.Element pipeline, string property_name, string action_signal) {
    Gee.ArrayList<string> list_tags = new Gee.ArrayList<string> ();
    int n_text;
    pipeline.get (property_name, out n_text);
    if (n_text == 0) {
        return list_tags;
    }
    for (int i = 0; i < n_text; i++) {
        Gst.TagList tags;
        string value;
        GLib.Signal.emit_by_name (pipeline, action_signal, i, out tags);
        if (tags != null) {
            if (tags.get_string ("language-name", out value)) {
                value = @"$(value)";
            } else if (tags.get_string ("language-code", out value)) {
                value = @"$(value)";
            } else {
                value = @"$(i+1)";
            }
        } else {
            value = _("External");
        }
        list_tags.add  (value);
    }
    return list_tags;
}

private Gst.Sample? get_cover_sample (Gst.TagList tag_list, Gst.Tag.ImageType type) {
    Gst.Sample sample;
    for (uint i = 0; tag_list.get_sample_index (Gst.Tags.IMAGE, i, out sample); i++) {
        unowned Gst.Structure caps_struct = sample.get_info ();
        int image_type = Gst.Tag.ImageType.UNDEFINED;
        caps_struct.get_enum ("image-type", typeof (Gst.Tag.ImageType), out image_type);
        if (image_type == type) {
            return sample;
        }
    }
    return sample;
}

private string? subtitle_for_path (string uri) {
    string without_ext;
    int last_dot = uri.last_index_of (".", 0);
    int last_slash = uri.last_index_of ("/", 0);
    if (last_dot < last_slash) {
        without_ext = uri;
    } else {
        without_ext = uri.slice (0, last_dot);
    }
    string[] subtitle_ext = {"sub", "srt", "smi", "ssa", "ass", "asc", "sm", "lrc"};
    foreach (string ext in subtitle_ext) {
        string sub_uri = @"$(without_ext).$(ext)";
        if (GLib.FileUtils.test (sub_uri, GLib.FileTest.EXISTS)) {
            return sub_uri;
        }
    }
    return null;
}

private bool match_keycode (uint keyval, uint code) {
    Gdk.KeymapKey [] keys;
    if (Gdk.Display.get_default ().map_keyval (keyval, out keys)) {
        foreach (var key in keys) {
            if (code == key.keycode) {
                return true;
            }
        }
    }
    return false;
}

private bool is_media_file (string name) {
    string[] exts = {".mp4", ".webm", ".mpg", ".avi", ".chk", ".flv", ".mp3", ".mkv", ".mov", ".vob"};
    foreach (var ext in exts) {
        if (name.has_suffix (ext) || name.has_suffix (ext.up ())) {
            return true;
        }
    }
    return false;
}

private static uint32 drm_name_to_fourcc (string name) {
    if (name.length < 4) {
        return 0;
    }
    uint8[] b = name.data;
    return (uint32) b[0] | ((uint32) b[1] << 8) | ((uint32) b[2] << 16) | ((uint32) b[3] << 24);
}

private static uint drm_format_n_planes (string drm_name) {
    switch (drm_name) {
        case "NV12":
        case "NV21":
        case "NV16":
        case "NV61":
        case "NV24":
        case "NV42":
        case "P010":
        case "P012":
        case "P016":
        case "P030":
            return 2;
        case "YU12":
        case "YV12":
        case "YU16":
        case "YV16":
        case "YU24":
        case "YV24":
        case "YUV9":
        case "YVU9":
        case "YU11":
        case "YV11":
            return 3;
        default:
            return 1;
    }
}

private static bool has_alpha_from_format (Gst.Video.Info info) {
    var finfo = info.finfo;
   if (finfo == null) {
        return false;
    }
    if (finfo.name.contains ("A")) {
        return true;
    } else {
        return false;
    }
}