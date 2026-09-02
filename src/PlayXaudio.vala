public class PlayXaudio : Gst.Bin {
    public signal void level_updated (double rms_l, double rms_r, double peak_l, double peak_r);
    public PlayXAsink audio_sink;
    private Gst.Element queue;
    private Gst.Element vol_elem;
    private Gst.Element level_elem;
    private Gst.Element convert;
    private Gst.Element resample;
    private uint anim_id = 0;
    private double[] bands = new double[10];
    private double[] anim_bands = new double[10];
    private double vol_anim = 1.0;

    private double _vol = 1.0;
    public double volume {
        get {
            return _vol;
        }
        set {
            _vol = value.clamp (0.0, 2.0);
            _start_anim ();
        }
    }

    public SinkBackend backend {
        get {
            return audio_sink.backend;
        }
        set {
            audio_sink.backend = value;
        }
    }

    public ChannelMode channel_mode {
        get {
            return audio_sink.channel_mode;
        }
        set {
            audio_sink.channel_mode = value;
        }
    }

    private static double[,] PRESET_VALS = {
        { 0,  0, 0, 0,  0,  0,  0,  0,  0,  0 },
        { 8,  7, 5, 3,  1,  0, -1, -1, -1, -1 },
        {-2, -1, 0, 0,  1,  2,  4,  5,  6,  7 },
        {-2, -2, 0, 2,  4,  4,  3,  2,  1,  0 },
        { 5,  4, 3, 1,  0, -1,  1,  3,  4,  4 },
        { 4,  3, 2, 0, -1, -1,  0,  2,  3,  4 },
        { 5,  4, 3, 2,  0, -1, -2, -2, -1,  1 },
        {-1, -1, 0, 2,  4,  3,  1,  0, -1, -1 },
        { 6,  5, 1, 0, -1,  1,  2,  3,  4,  5 },
        { 3,  2, 1, 0, -1, -1,  0,  1,  2,  3 },
        { 3,  2, 1, 0, -0.5, 0,  1,  2, 2.5, 3 },
        { 5,  3, 0,-1, -2, -1,  0,  2,  3,  4 },
    };

    construct {
        queue = Gst.ElementFactory.make ("queue2", "aq");
        vol_elem = Gst.ElementFactory.make ("volume", "vol");
        level_elem = Gst.ElementFactory.make ("level", "lvl");
        convert = Gst.ElementFactory.make ("audioconvert", "aconv");
        resample = Gst.ElementFactory.make ("audioresample", "ares");
        audio_sink = (PlayXAsink) GLib.Object.new(typeof(PlayXAsink));
        queue.set ("max-size-time", (uint64)(5 * Gst.SECOND));
        queue.set ("max-size-bytes", (uint)(32 * 1024 * 1024));
        queue.set ("max-size-buffers", (uint) 0);
        level_elem.set ("post-messages", true);
        level_elem.set ("interval", (uint64)(50 * Gst.MSECOND));
        resample.set ("quality", 10);
        add_many (queue, vol_elem, level_elem, convert, resample, audio_sink);
        queue.link_many ( vol_elem, level_elem, convert, resample, audio_sink);
        add_pad (new Gst.GhostPad ("sink", queue.get_static_pad ("sink")));
        for (int i = 0; i < 10; i++) {
            bands[i] = 0.0;
            anim_bands[i] = 0.0;
        }
    }

    public void set_band (int index, double db) {
        if (index < 0 || index >= 10) {
            return;
        }
        bands[index] = db.clamp (-12.0, 12.0);
        _start_anim ();
    }

    public double get_band (int index) {
        return (index >= 0 && index < 10) ? bands[index] : 0.0;
    }

    public void apply_preset (Preset preset) {
        int p = (int) preset;
        for (int i = 0; i < 10; i++) {
            set_band (i, PRESET_VALS[p, i]);
        }
    }

    public void reset () {
        for (int i = 0; i < 10; i++) {
            set_band (i, 0.0);
        }
        volume = 1.0;
    }

    private void _start_anim () {
        if (anim_id != 0) {
            return;
        }
        anim_id = GLib.Timeout.add (16, _anim_tick);
    }

    private bool _anim_tick () {
        bool still = false;
        for (int i = 0; i < 10; i++) {
            anim_bands[i] += (bands[i] - anim_bands[i]) * 0.22;
            if (Math.fabs (anim_bands[i] - bands[i]) > 0.05) {
                still = true;
            } else {
                anim_bands[i] = bands[i];
            }
            audio_sink.set_eq_band (i, anim_bands[i]);
        }
        vol_anim += (_vol - vol_anim) * 0.22;
        if (Math.fabs (vol_anim - _vol) > 0.001) {
            still = true;
        } else {
            vol_anim = _vol;
        }
        vol_elem.set ("volume", vol_anim);
        if (!still) {
            anim_id = 0;
            return GLib.Source.REMOVE;
        }
        return GLib.Source.CONTINUE;
    }

    public void handle_bus_message (Gst.Message msg) {
        unowned Gst.Structure? s = msg.get_structure ();
        if (s == null || s.get_name () != "level") {
            return;
        }
        double rms_l = -100, rms_r = -100;
        double peak_l = -100, peak_r = -100;
        _parse_level_array (s, "rms",  ref rms_l,  ref rms_r);
        _parse_level_array (s, "peak", ref peak_l, ref peak_r);
        level_updated (rms_l, rms_r, peak_l, peak_r);
    }

    private void _parse_level_array (Gst.Structure s, string field, ref double left, ref double right) {
        var val = s.get_value (field);
        if (val == null) {
            return;
        }
        if (!val.holds (typeof (GLib.ValueArray))) {
            if (Gst.ValueList.get_size (val) > 0) {
                left = Gst.ValueList.get_value (val, 0).get_double ();
                if (Gst.ValueList.get_size (val) >= 2) {
                    right = Gst.ValueList.get_value (val, 1).get_double ();
                } else {
                    right = left;
                }
            }
            return;
        }
        if (((GLib.ValueArray?) val.get_boxed ()).n_values > 0) {
            left = ((GLib.ValueArray?) val.get_boxed ()).values[0].get_double ();
            right = ((GLib.ValueArray?) val.get_boxed ()).n_values >= 2 ? ((GLib.ValueArray?) val.get_boxed ()).values[1].get_double () : left;
        }
    }
}