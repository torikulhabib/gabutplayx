public class PlayXAsink : Gst.Audio.Sink {
    private Alsa.PcmDevice? pcm_handle = null;
    private NoiseCanceller? noise_canceller = null;
    private DolbySurround? dolby_proc = null;
    private HiFiEqualizer? equalizer = null;
    private Limiter? limiter = null;
    private Gst.Audio.Format _fmt = Gst.Audio.Format.S16LE;
    private PulseAudio.Simple? pa_handle = null;
    private int channels = 2;
    private int rate = 48000;
    private int buffer_size = 4096;
    private int noise_frames = 0;
    private int fmt_width = 16;
    private int fmt_bytes = 2;
    private float[] noise_floor = new float[0];
    private double[] eq_bands;
    private bool noise_learned = false;
    private bool prepared = false;
    private bool fmt_is_float = false;
    private const int ERR_EBADFD = 77;
    private const int ERR_ESTRPIPE = 86;
    private const int ERR_EPIPE = 32;
    private const int ERR_EAGAIN = 11;

    private string _device = "default";
    public string device {
        get {
            return _device;
        }
        set {
            _device = value;
        }
    }

    private double _gain = 1.0;
    public double gain {
        get {
            return _gain;
        }
        set {
            _gain = value.clamp (0.0, 4.0);
        }
    }

    private bool _mute = false;
    public bool mute {
        get {
            return _mute;
        }
        set {
            _mute = value;
        }
    }

    private DolbyMode _dolby = DolbyMode.STEREO;
    public DolbyMode dolby_mode {
        get {
            return _dolby;
        }
        set {
            _dolby = value;
            configure_dolby ();
        }
    }

    private NoiseMode _noise = NoiseMode.OFF;
    public NoiseMode noise_cancellation {
        get {
            return _noise;
        }
        set {
            _noise = value;
            configure_noise ();
        }
    }

    private bool _eq_enabled = false;
    public bool equalizer_enabled {
        get {
            return _eq_enabled;
        }
        set {
            _eq_enabled = value;
        }
    }

    private SinkBackend _backend = SinkBackend.ALSA;
    public SinkBackend backend {
        get {
            return _backend;
        }
        set {
            _backend = value;
        }
    }

    private ChannelMode _channel_mode = ChannelMode.STEREO;
    public ChannelMode channel_mode {
        get {
            return _channel_mode;
        }
        set {
            _channel_mode = value;
        }
    }

    static construct {
        Gst.Caps caps = Gst.Caps.from_string (
            "audio/x-raw, "
            + "format=(string){ S16LE, S24LE, S24_32LE, S32LE, F32LE, F64LE }, "
            + "layout=(string)interleaved, "
            + "rate=(int)[8000,192000], "
            + "channels=(int)[1,8]"
        );
        add_pad_template (new Gst.PadTemplate ( "sink", Gst.PadDirection.SINK, Gst.PadPresence.ALWAYS, caps));
    }

    construct {
        eq_bands = new double[10];
        noise_canceller = new NoiseCanceller ();
        dolby_proc = new DolbySurround ();
        equalizer = new HiFiEqualizer ();
        limiter = new Limiter (-0.3);
    }

    protected override bool open () {
        if (_backend == SinkBackend.PULSE) {
            return true;
        }
        int err = Alsa.PcmDevice.open (out pcm_handle, _device, Alsa.PcmStream.PLAYBACK, 0);
        if (err < 0) {
            return false;
        }
        return true;
    }

    public void set_eq_band (int band, double gain_db) requires (band >= 0 && band < 10) {
        eq_bands[band] = gain_db.clamp (-12.0, 12.0);
        if (prepared && equalizer != null) {
            equalizer.set_bands (eq_bands);
        }
    }

    private int alsa_format_bytes (Alsa.PcmFormat fmt) {
        switch (fmt) {
            case Alsa.PcmFormat.S16_LE:
                return 2;
            case Alsa.PcmFormat.S24_3LE:
                return 3;
            case Alsa.PcmFormat.S24_LE:
                return 4;
            case Alsa.PcmFormat.S32_LE:
                return 4;
            case Alsa.PcmFormat.FLOAT_LE:
                return 4;
            case Alsa.PcmFormat.FLOAT64_LE:
                return 8;
            default:
                return -1;
        }
    }

    private void resolve_format_info (Gst.Audio.Format fmt) {
        switch (fmt) {
            case Gst.Audio.Format.S16LE:
                fmt_width = 16;
                fmt_bytes = 2;
                fmt_is_float = false;
                break;
            case Gst.Audio.Format.S24LE:
                fmt_width = 24;
                fmt_bytes = 3;
                fmt_is_float = false;
                break;
            case Gst.Audio.Format.S24_32LE:
                fmt_width = 24;
                fmt_bytes = 4;
                fmt_is_float = false;
                break;
            case Gst.Audio.Format.S32LE:
                fmt_width = 32;
                fmt_bytes = 4;
                fmt_is_float = false;
                break;
            case Gst.Audio.Format.F32LE:
                fmt_width = 32;
                fmt_bytes = 4;
                fmt_is_float = true;
                break;
            case Gst.Audio.Format.F64LE:
                fmt_width = 64;
                fmt_bytes = 8;
                fmt_is_float = true;
                break;
            default:
                fmt_width = 16;
                fmt_bytes = 2;
                fmt_is_float = false;
                break;
        }
    }

    protected override bool prepare (Gst.Audio.RingBufferSpec spec) {
        unowned Gst.Structure? s = spec.caps.get_structure (0);
        if (s == null) {
            return false;
        }
        s.get_int ("rate", out rate);
        s.get_int ("channels", out channels);
        if (rate <= 0) {
            rate = 48000;
        }
        if (channels <= 0) {
            channels = 2;
        }
        unowned string? fmt_str = s.get_string ("format");
        _fmt = Gst.Audio.Format.from_string (fmt_str ?? "S16LE");
        resolve_format_info (_fmt);
        if (_backend == SinkBackend.ALSA) {
            Alsa.PcmFormat alsa_fmt = map_gst_to_alsa (_fmt);
            int expected_bytes = alsa_format_bytes (alsa_fmt);
            if (expected_bytes > 0 && expected_bytes != fmt_bytes) {
                warning (
                    "PlayXAsink: format byte-width mismatch — GStreamer %s implies %d bytes/sample but mapped ALSA format implies %d bytes/sample. Check map_gst_to_alsa().",
                    _fmt.to_string (), fmt_bytes, expected_bytes
                );
                fmt_bytes = expected_bytes;
            }
        }
        int bpf = channels * fmt_bytes;
        buffer_size = spec.segtotal * spec.segsize;
        if (bpf > 0) {
            buffer_size /= bpf;
        }
        if (buffer_size < 128) {
            buffer_size = 4096;
        }
        if (_backend == SinkBackend.ALSA) {
            int err = pcm_handle.set_params (map_gst_to_alsa (_fmt), Alsa.PcmAccess.RW_INTERLEAVED, (uint) channels, (uint) rate, 1, 100000);
            if (err < 0) {
                return false;
            }
        } else {
            var ss = PulseAudio.SampleSpec () {
                format = map_gst_to_pulse (_fmt),
                rate = (uint32) rate,
                channels = (uint8) channels
            };
            int pa_err = 0;
            pa_handle = new PulseAudio.Simple (null, "PlayXAsink", PulseAudio.Stream.Direction.PLAYBACK, null, "playback", ss, null, null, out pa_err);
            if (pa_handle == null) {
                return false;
            }
        }
        noise_canceller.init (channels, rate, buffer_size);
        dolby_proc.init (channels, rate);
        equalizer.init (channels, rate);
        limiter.init (channels, rate);
        noise_floor = new float[buffer_size * channels];
        noise_frames = 0;
        noise_learned = false;
        prepared = true;
        configure_noise ();
        configure_dolby ();
        equalizer.set_bands (eq_bands);
        return true;
    }

    private uint write_to_backend (uint8[] data) {
        if (_backend == SinkBackend.PULSE) {
            return write_to_pulse (data);
        }
        return write_to_alsa (data);
    }

    private uint write_to_pulse (uint8[] data) {
        if (pa_handle == null) {
            return 0;
        }
        int pa_err = 0;
        if (pa_handle.write (data, data.length, out pa_err) < 0) {
            pa_handle = null;
            return 0;
        }
        return (uint) data.length;
    }

    private void apply_channel_mode (ref float[] samples) {
        if (_channel_mode == ChannelMode.STEREO || channels < 2) {
            return;
        }
        int nframes = samples.length / channels;
        for (int i = 0; i < nframes; i++) {
            float l = samples[i * channels];
            float r = samples[i * channels + 1];
            float val;
            switch (_channel_mode) {
                case ChannelMode.MONO_L:
                    val = l;
                    break;
                case ChannelMode.MONO_R:
                    val = r;
                    break;
                case ChannelMode.MONO_MIX:
                    val = (l + r) * 0.5f;
                    break;
                default:
                    continue;
            }
            samples[i * channels] = val;
            samples[i * channels + 1] = val;
        }
    }

    protected override int write (uint8[] data) {
        if (_mute) {
            return (int) write_silence (data.length);
        }
        float[] samples = bytes_to_float32 (data);
        int nframes = (channels > 0) ? samples.length / channels : 0;
        int dsp_ch = channels;
        apply_channel_mode (ref samples);
        apply_gain (ref samples, _gain);
        if (_eq_enabled) {
            equalizer.process (ref samples, nframes, channels);
        }
        if (_dolby != DolbyMode.BYPASS && _dolby != DolbyMode.STEREO) {
            dolby_proc.process (ref samples, nframes, ref dsp_ch);
        }
        if (dsp_ch != channels) {
            samples = downmix_to_stereo (samples, nframes, dsp_ch);
        }
        if (_noise != NoiseMode.OFF) {
            if (!noise_learned && noise_frames < 10) {
                accumulate_noise_floor (samples);
                noise_frames++;
            } else {
                if (!noise_learned) {
                    finalize_noise_floor ();
                    noise_learned = true;
                }
                noise_canceller.process (ref samples, nframes, channels);
            }
        }
        limiter.process (ref samples);
        if (!fmt_is_float) {
            apply_dither (ref samples, fmt_width);
        }
        uint8[] out_bytes = float32_to_bytes (samples);
        return (int) write_to_backend (out_bytes);
    }

    private float[] downmix_to_stereo (float[] src, int nframes, int src_ch) {
        if (src_ch == channels) {
            return src;
        }
        float[] aout = new float[nframes * channels];
        if (src_ch == 4) {
            for (int i = 0; i < nframes; i++) {
                float l = src[i * 4];
                float c = src[i * 4 + 1];
                float r = src[i * 4 + 2];
                float s = src[i * 4 + 3];
                aout[i * 2] = (l + 0.7071f * c + 0.75f * s).clamp (-1f, 1f);
                aout[i * 2 + 1] = (r + 0.7071f * c - 0.75f * s).clamp (-1f, 1f);
            }
        } else if (src_ch == 6) {
            for (int i = 0; i < nframes; i++) {
                float l = src[i * 6];
                float c = src[i * 6 + 1];
                float r = src[i * 6 + 2];
                float ls = src[i * 6 + 3];
                float rs = src[i * 6 + 4];
                float lfe = src[i * 6 + 5];
                aout[i * 2] = (l + 0.15f * c + 0.55f * ls + 0.20f * lfe).clamp (-1f, 1f);
                aout[i * 2 + 1] = (r + 0.15f * c + 0.55f * rs + 0.20f * lfe).clamp (-1f, 1f);
            }
        } else {
            for (int i = 0; i < nframes; i++) {
                aout[i * 2] = src[i * src_ch];
                aout[i * 2 + 1] = src[i * src_ch + 1];
            }
        }
        return aout;
    }

    protected override bool unprepare () {
        prepared = false;
        if (_backend == SinkBackend.PULSE) {
            if (pa_handle != null) {
                int err = 0;
                pa_handle.drain (out err);
                pa_handle = null;
            }
        } else {
            if (pcm_handle != null) {
                pcm_handle.drain ();
            }
        }
        return true;
    }

    protected override bool close () {
        prepared = false;
        if (_backend == SinkBackend.PULSE) {
            pa_handle = null;
        } else {
            if (pcm_handle != null) {
                pcm_handle.close ();
                pcm_handle = null;
            }
        }
        return true;
    }

    protected override void reset () {
        if (_backend == SinkBackend.ALSA) {
            if (pcm_handle != null) {
                pcm_handle.drop ();
            }
        }
    }

    protected override uint delay () {
        if (_backend == SinkBackend.PULSE && pa_handle != null) {
            int err = 0;
            uint64 us = pa_handle.get_latency (out err);
            if (err == 0 && us > 0) {
                return (uint)((us * (uint64) rate) / 1000000ULL);
            }
        }
        if (rate > 0) {
            return (uint)((uint64) rate * 100 / 1000);
        }
        return 0;
    }

    private void apply_gain (ref float[] samples, double gain) {
        float g = (float) gain;
        if (gain > 1.0) {
            for (int i = 0; i < samples.length; i++) {
                samples[i] = soft_clip (samples[i] * g);
            }
        } else {
            for (int i = 0; i < samples.length; i++) {
                samples[i] *= g;
            }
        }
    }

    private inline float soft_clip (float x) {
        if (x >= 1.0f) {
            return 0.6667f;
        }
        if (x <= -1.0f) {
            return -0.6667f;
        }
        return x - (x * x * x) / 3.0f;
    }

    private void apply_dither (ref float[] samples, int bits) {
        if (bits < 2) {
            bits = 16;
        }
        float amp = 1.0f / (float) (1 << (bits - 1));
        for (int i = 0; i < samples.length; i++) {
            float r1 = (float) GLib.Random.double_range (-1.0, 1.0);
            float r2 = (float) GLib.Random.double_range (-1.0, 1.0);
            samples[i] += amp * (r1 + r2) * 0.5f;
        }
    }

    private void accumulate_noise_floor (float[] samples) {
        int len = (samples.length < noise_floor.length ? samples.length : noise_floor.length);
        for (int i = 0; i < len; i++) {
            noise_floor[i] += GLib.Math.fabsf (samples[i]);
        }
    }

    private void finalize_noise_floor () {
        float inv = 1.0f / (float) noise_frames;
        for (int i = 0; i < noise_floor.length; i++) {
            noise_floor[i] *= inv;
        }
        noise_canceller.set_noise_profile (noise_floor);
    }

    private void configure_noise () {
        if (noise_canceller == null) {
            return;
        }
        switch (_noise) {
            case NoiseMode.LIGHT:
                noise_canceller.configure (0.4, 4.0, 0.02);
                noise_canceller.set_adaptive (false);
                break;
            case NoiseMode.MEDIUM:
                noise_canceller.configure (0.55, 8.0, 0.03);
                noise_canceller.set_adaptive (false);
                break;
            case NoiseMode.AGGRESSIVE:
                noise_canceller.configure (0.75, 12.0, 0.04);
                noise_canceller.set_adaptive (false);
                break;
            case NoiseMode.ADAPTIVE:
                noise_canceller.configure (0.60, 9.0, 0.02);
                noise_canceller.set_adaptive (true);
                break;
            default:
                break;
        }
    }

    private void configure_dolby () {
        if (dolby_proc == null) {
            return;
        }
        dolby_proc.set_mode (_dolby);
    }

    private float[] bytes_to_float32 (uint8[] data) {
        int bytes = fmt_bytes;
        if (bytes <= 0) {
            bytes = 2;
        }
        int n = data.length / bytes;
        float[] aout = new float[n];

        switch (_fmt) {
            case Gst.Audio.Format.S16LE:
                for (int i = 0; i < n; i++) {
                    int off = i * 2;
                    int16 sv = (int16) ((uint16) data[off] | ((uint16) data[off + 1] << 8));
                    aout[i] = (float) sv / 32768.0f;
                }
                break;

            case Gst.Audio.Format.S24LE:
                for (int i = 0; i < n; i++) {
                    int off = i * 3;
                    int32 sv = (int32) data[off]
                        | ((int32) data[off + 1] << 8)
                        | ((int32) data[off + 2] << 16);
                    if ((sv & 0x00800000) != 0) {
                        sv |= (int32) 0xFF000000;
                    }
                    aout[i] = (float) sv / 8388608.0f;
                }
                break;
            case Gst.Audio.Format.S24_32LE:
                for (int i = 0; i < n; i++) {
                    int off = i * 4;
                    int32 sv = (int32) ((uint32) data[off]
                        | ((uint32) data[off + 1] << 8)
                        | ((uint32) data[off + 2] << 16)
                        | ((uint32) data[off + 3] << 24));
                    aout[i] = (float) sv / 8388608.0f; // 2^23
                }
                break;
            case Gst.Audio.Format.S32LE:
                for (int i = 0; i < n; i++) {
                    int off = i * 4;
                    int32 sv = (int32) ((uint32) data[off] | ((uint32) data[off + 1] << 8) | ((uint32) data[off + 2] << 16) | ((uint32) data[off + 3] << 24));
                    aout[i] = (float) sv / 2147483648.0f;
                }
                break;

            case Gst.Audio.Format.F32LE:
                for (int i = 0; i < n; i++) {
                    int off = i * 4;
                    uint32 bits = (uint32) data[off] | ((uint32) data[off + 1] << 8) | ((uint32) data[off + 2] << 16) | ((uint32) data[off + 3] << 24);
                    aout[i] = *((float*) &bits);
                }
                break;

            case Gst.Audio.Format.F64LE:
                for (int i = 0; i < n; i++) {
                    int off = i * 8;
                    uint64 bits = 0;
                    for (int b = 0; b < 8; b++) {
                        bits |= ((uint64) data[off + b]) << (8 * b);
                    }
                    double dv = *((double*) &bits);
                    aout[i] = (float) dv;
                }
                break;

            default:
                for (int i = 0; i < n; i++) {
                    aout[i] = 0.0f;
                }
                break;
        }
        return aout;
    }

    private uint8[] float32_to_bytes (float[] samples) {
        int bytes = fmt_bytes;
        if (bytes <= 0) {
            bytes = 2;
        }
        uint8[] aout = new uint8[samples.length * bytes];

        switch (_fmt) {
            case Gst.Audio.Format.S16LE:
                for (int i = 0; i < samples.length; i++) {
                    float s = samples[i].clamp (-1.0f, 1.0f);
                    int16 v = (int16) (s * 32767.0f);
                    int off = i * 2;
                    aout[off] = (uint8) (v & 0xFF);
                    aout[off + 1] = (uint8) ((v >> 8) & 0xFF);
                }
                break;

            case Gst.Audio.Format.S24LE:
                for (int i = 0; i < samples.length; i++) {
                    float s = samples[i].clamp (-1.0f, 1.0f);
                    int32 v = (int32) (s * 8388607.0f); // 2^23 - 1
                    int off = i * 3;
                    aout[off] = (uint8) (v & 0xFF);
                    aout[off + 1] = (uint8) ((v >> 8) & 0xFF);
                    aout[off + 2] = (uint8) ((v >> 16) & 0xFF);
                }
                break;

            case Gst.Audio.Format.S24_32LE:
                for (int i = 0; i < samples.length; i++) {
                    float s = samples[i].clamp (-1.0f, 1.0f);
                    int32 v = (int32) (s * 8388607.0f);
                    int off = i * 4;
                    aout[off] = (uint8) (v & 0xFF);
                    aout[off + 1] = (uint8) ((v >> 8) & 0xFF);
                    aout[off + 2] = (uint8) ((v >> 16) & 0xFF);
                    aout[off + 3] = (uint8) ((v >> 24) & 0xFF);
                }
                break;

            case Gst.Audio.Format.S32LE:
                for (int i = 0; i < samples.length; i++) {
                    float s = samples[i].clamp (-1.0f, 1.0f);
                    int64 v64 = (int64) (s * 2147483647.0f);
                    int32 v = (int32) v64;
                    int off = i * 4;
                    aout[off] = (uint8) (v & 0xFF);
                    aout[off + 1] = (uint8) ((v >> 8) & 0xFF);
                    aout[off + 2] = (uint8) ((v >> 16) & 0xFF);
                    aout[off + 3] = (uint8) ((v >> 24) & 0xFF);
                }
                break;

            case Gst.Audio.Format.F32LE:
                for (int i = 0; i < samples.length; i++) {
                    float s = samples[i];
                    uint32 bits = *((uint32*) &s);
                    int off = i * 4;
                    aout[off] = (uint8) (bits & 0xFF);
                    aout[off + 1] = (uint8) ((bits >> 8) & 0xFF);
                    aout[off + 2] = (uint8) ((bits >> 16) & 0xFF);
                    aout[off + 3] = (uint8) ((bits >> 24) & 0xFF);
                }
                break;

            case Gst.Audio.Format.F64LE:
                for (int i = 0; i < samples.length; i++) {
                    double d = (double) samples[i];
                    uint64 bits = *((uint64*) &d);
                    int off = i * 8;
                    for (int b = 0; b < 8; b++) {
                        aout[off + b] = (uint8) ((bits >> (8 * b)) & 0xFF);
                    }
                }
                break;

            default:
                break;
        }
        return aout;
    }

    private uint write_to_alsa (uint8[] data) {
        if (pcm_handle == null) {
            return 0;
        }
        int bpf = channels * fmt_bytes;

        if (bpf <= 0) {
            return 0;
        }
        long frames = data.length / bpf;
        if (frames <= 0) {
            return 0;
        }
        Alsa.PcmSignedFrames written = pcm_handle.writei (data, (Alsa.PcmUnsignedFrames) frames);
        long wr = (long) written;
        if (wr == -ERR_EPIPE) {
            pcm_handle.prepare ();
            written = pcm_handle.writei (data, (Alsa.PcmUnsignedFrames) frames);
            wr = (long) written;
        } else if (wr == -ERR_EBADFD) {
            pcm_handle.prepare ();
            return 0;
        } else if (wr == -ERR_ESTRPIPE) {
            while ((wr = pcm_handle.resume ()) == -ERR_EAGAIN) {
                Posix.usleep (1000);
            }
            if (wr < 0) {
                pcm_handle.prepare ();
            }
            return 0;
        } else if (wr < 0) {
            pcm_handle.prepare ();
            return 0;
        }
        return (uint) (wr * bpf);
    }

    private uint write_silence (int length) {
        uint8[] silence = new uint8[length];
        GLib.Memory.set (silence, 0, length);
        return write_to_backend (silence);
    }
}