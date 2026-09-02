public struct MediaInfo {
    public int64 file_size;
    public int64 duration_ms;
    public uint video_width;
    public uint video_height;
    public uint video_fps_n;
    public uint video_fps_d;
    public uint video_bitrate;
    public uint video_max_bitrate;
    public uint video_depth;
    public uint audio_channels;
    public uint audio_sample_rate;
    public uint audio_bitrate;
    public uint audio_max_bitrate;
    public uint audio_depth;
    public string audio_codec;
    public string video_codec;
    public string file_name;
    public string container;
    public string subtitle_lang;
    public string video_lang;
    public string audio_lang;
    public string title;
    public string artist;
    public string album;
    public string video_format;
    public string video_profile;
    public string video_level;
    public string audio_format;
    public string profile_name;
    public string profile_desc;
    public string audio_raw_format;
    public string video_stream_fmt;
    public string video_chroma;
    public string video_colorimetry;
    public string audio_profile;
    public string audio_stream_fmt;
    public int audio_mpegversion;
    public bool video_interlaced;

    public string duration_str () {
        return seconds_to_time(duration_ms);
    }

    public string fps_str () {
        if (video_fps_d == 0) {
            return "";
        }
        double fps = (double) video_fps_n / video_fps_d;
        return "%.4g fps".printf (fps);
    }

    public string file_size_str () {
        if (file_size <= 0) {
            return "";
        }
        return GLib.format_size (file_size);
    }

    private static string br (uint bps) {
        if (bps == 0) {
            return "?";
        }
        return GLib.format_size (bps);
    }

    private static string ch_label (uint n) {
        switch (n) {
            case 1: return "1 (Mono)";
            case 2: return "2 (Stereo)";
            case 6: return "6 (5.1)";
            case 8: return "8 (7.1)";
            default: return "%u ch".printf (n);
        }
    }

    public string[,] to_rows () {
        string res_str = (video_width > 0) ? "%ux%u %s%s".printf (video_width, video_height, fps_str (), video_interlaced ? " ⚡" : "") : "";
        string audio_profile_str = audio_profile ?? "";
        string video_profile_str = (video_profile != "" && video_profile != null && video_level != "" && video_level != null) ? "%s / L%s".printf (video_profile, video_level) : video_profile ?? "";
        string mpeg_str = (audio_mpegversion > 0) ? "MPEG-%d".printf (audio_mpegversion) : "";
        string[,] rows = {
            { "File", file_name ?? "" },
            { "Size", file_size_str () },
            { "Duration", duration_str () },
            { "Container", container ?? "" },
            { "─ Video ─", "" },
            { "Codec", video_codec ?? "" },
            { "Resolution", res_str },
            { "Bitrate", (video_bitrate > 0) ? br (video_bitrate) : "" },
            { "Stream Fmt", video_stream_fmt ?? "" },
            { "Profile", video_profile_str },
            { "Chroma", video_chroma ?? "" },
            { "Colorimetry", video_colorimetry ?? "" },
            { "Px Format", video_format ?? "" },
            { "─ Audio ─", "" },
            { "Codec", audio_codec ?? "" },
            { "MPEG", mpeg_str },
            { "Profile", audio_profile_str },
            { "Stream Fmt", audio_stream_fmt ?? "" },
            { "Channels", (audio_channels > 0) ? ch_label (audio_channels) : "" },
            { "Samplerate", (audio_sample_rate > 0) ? "%u Hz".printf (audio_sample_rate) : "" },
            { "Bitrate", (audio_bitrate > 0) ? br (audio_bitrate) : "" },
            { "Depth", (audio_depth > 0) ? "%u-bit".printf (audio_depth) : "" },
            { "Format", audio_format ?? "" },
            { "─ Tags ─", "" },
            { "Title", title ?? "" },
            { "Artist", artist ?? "" },
            { "Album", album ?? "" },
            { "Subtitle", subtitle_lang ?? "" },
            { "Video", video_lang ?? "" },
            { "Audio", audio_lang ?? "" }
        };
        return rows;
    }
}