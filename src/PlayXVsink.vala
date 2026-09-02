public class PlayXVsink : Gst.Video.Sink, Gdk.Paintable {
    public signal void resize_changed (int width, int height);
    public signal void osd_changed ();
    public Gdk.RGBA background_color { get; set; default = Gdk.RGBA () { alpha = 1f }; }
    public GLib.GenericArray<FrameTexture>? cached_textures = null;
    public SubtitleOverlay subtitle_overlay { get; set; }
    private GLib.HashTable<size_t?, Gdk.Texture> texture_cache;
    private Gee.HashSet<size_t?> used_texture_keys;
    private GLib.Mutex frame_lock;
    private Gst.Buffer? pending_buffer = null;
    private Gst.Caps? pending_caps = null;
    private Pango.Context? pango_ctx = null;
    private Gdk.Texture? old_texture = null;
    private OsdIconPaintable[] osd_icons;
    private MediaInfo media_info;
    public bool force_aspect_ratio { get; set; default = true; }
    public bool auto_rotation { get; set; default = false; }
    public bool subtitle_toggle { get; set; default = true; }
    public bool avisual_toggle { get; set; default = true; }
    public bool video_render { get; set; default = false; }
    public bool outline_mode { get; set; default = false; }
    public int display_width = 0;
    public int display_height = 0;
    public double brightness { get; set; default = 0.0; }
    public double contrast { get; set; default = 0.0; }
    public double saturation { get; set; default = 0.0; }
    public double hue { get; set; default = 0.0; }
    public double gamma { get; set; default = 1.0; }
    private double seek_pos = 0.0;
    private double seek_anim = 0.0;
    private double seek_buf = 0.0;
    private double vol_osd = 0.0;
    private double osd_op = 0.0;
    private double rms_l = 0.0;
    private double peak_l = 0.0;
    private double rms_a = 0.0;
    private double peak_a = 0.0;
    private double vis_angle = 0.0;
    private double toast_op = 0.0;
    private double[] vis_history;
    private int crop_x = 0;
    private int crop_y = 0;
    private int crop_w = 0;
    private int crop_h = 0;
    private int cache_clean_counter = 0;
    private int pending_invoke = 0;
    private int vis_hist_idx = 0;
    private bool osd_fading = false;
    private bool osd_sfading = false;
    private bool seek_anim_active = false;
    private bool volume_vis = false;
    private bool osd_anim_active = false;
    private bool toast_fading = false;
    private uint toast_hold = 0;
    private uint idle_skip = 0;
    private uint vis_timer = 0;
    private uint osd_seek = 0;
    private uint osd_hold = 0;
    private uint master_tid = 0;
    private string toast_text = "";
    private const int CACHE_CLEAN_INTERVAL = 15;
    private bool media_info_visible = false;
    private double info_op = 0.0;
    private bool info_fading = false;
    private uint info_hold = 0;

    private Gdk.Texture? _cover_texture = null;
    public Gdk.Texture? cover_texture {
        get {
            return _cover_texture;
        }
        set {
            _cover_texture = value;
            if (old_texture != _cover_texture) {
                old_texture = _cover_texture;
                video_render = false;
                if (_cover_texture != null) {
                    display_width = _cover_texture.width;
                    display_height = _cover_texture.height;
                    safe_invalidate_size ();
                    stop_vis_timer ();
                } else {
                    display_width = 0;
                    display_height = 0;
                    safe_invalidate_size ();
                }
                safe_invalidate_contents ();
            }
        }
    }

    private OsdParam[] osd = {
        { 0.0, 0.0 },
        { 0.0, 0.0 },
        { 0.0, 0.0 },
        { 0.0, 0.0 },
        { 1.0, 1.0 }
    };

    private struct OsdParam {
        public double val;
        public double anim;
    }

    public double seek_position {
        get {
            return seek_pos;
        }
        set {
            volume_vis = false;
            seek_pos = value.clamp (0.0, 1.0);
            seek_start_anim ();
            seek_show ();
        }
    }

    public double seek_buffered {
        get {
            return seek_buf;
        }
        set {
            seek_buf = value.clamp (0.0, 1.0);
            safe_invalidate_contents ();
        }
    }

    public double volume_changed {
        get {
            return vol_osd;
        }
        set {
            volume_vis = true;
            vol_osd = value.clamp (0.0, 1.0);
            seek_start_anim ();
            seek_show ();
        }
    }

    private int64 _subtitle_position_ms = 0;
    public int64 subtitle_position_ms {
        get {
            return _subtitle_position_ms;
        }
        set {
            _subtitle_position_ms = value;
            if (!video_render) {
                safe_invalidate_contents ();
            }
        }
    }

    private int _rotation = 0;
    public int rotation {
        get {
            return _rotation;
        }
        set {
            _rotation = ((value % 360) + 360) % 360;
            _rotation = (int)(Math.round (_rotation / 90.0) * 90) % 360;
            safe_invalidate_size ();
            safe_invalidate_contents ();
        }
    }

    private void safe_invalidate_contents () {
        if (GLib.MainContext.default ().is_owner ()) {   
            invalidate_contents ();
            osd_changed ();
        } else {
            GLib.MainContext.default ().invoke (() => {
                invalidate_contents ();
                osd_changed ();
                return GLib.Source.REMOVE;
            });
        }
    }

    private void safe_invalidate_size () {
        if (GLib.MainContext.default ().is_owner ()) {
            invalidate_size ();
            osd_changed ();
        } else {
            GLib.MainContext.default ().invoke (() => {
                invalidate_size ();
                osd_changed ();
                return GLib.Source.REMOVE;
            });
        }
    }

    static construct {
        var dmabuf_caps = Gst.Caps.from_string (
            "video/x-raw(memory:DMABuf), "
            + "format = (string) DMA_DRM, "
            + "width = (int) [ 1, 2147483647 ], "
            + "height = (int) [ 1, 2147483647 ], "
            + "framerate = (fraction) [ 0/1, 2147483647/1 ]");

        var sys_caps = Gst.Caps.from_string (
            "video/x-raw, "
            + "format = (string) { BGRx, BGRA, RGBx, RGBA, ARGB, ABGR, RGB, BGR }, "
            + "width = (int) [ 1, 2147483647 ], "
            + "height = (int) [ 1, 2147483647 ], "
            + "framerate = (fraction) [ 0/1, 2147483647/1 ]");

        var merged = dmabuf_caps.merge (sys_caps);
        add_pad_template (new Gst.PadTemplate ("sink", Gst.PadDirection.SINK, Gst.PadPresence.ALWAYS, merged));
    }

    construct {
        frame_lock = GLib.Mutex ();
        texture_cache = new GLib.HashTable<size_t?, Gdk.Texture> (null, null);
        used_texture_keys = new Gee.HashSet<size_t?> (null, null);
        subtitle_overlay = new SubtitleOverlay ();
        throttle_time = Gst.NSECOND;
        max_lateness = -1;
        vis_history = new double[64];
        notify["brightness"].connect (safe_invalidate_contents);
        notify["contrast"].connect (safe_invalidate_contents);
        notify["saturation"].connect (safe_invalidate_contents);
        notify["hue"].connect (safe_invalidate_contents);
        notify["gamma"].connect (safe_invalidate_contents);
        osd_icons = {
            new OsdIconPaintable (OsdIconKind.BRIGHTNESS),
            new OsdIconPaintable (OsdIconKind.CONTRAST),
            new OsdIconPaintable (OsdIconKind.SATURATION),
            new OsdIconPaintable (OsdIconKind.HUE),
            new OsdIconPaintable (OsdIconKind.GAMMA)
        };
    }

    private bool is_color_identity () {
        return brightness == 0.0 && contrast == 0.0 && saturation == 0.0 && hue == 0.0 && gamma == 1.0;
    }

    private Pango.Context get_pango_context () {
        if (pango_ctx == null) {
            var font_map = Pango.CairoFontMap.@new ();
            pango_ctx = font_map.create_context ();
        }
        return pango_ctx;
    }

    public override bool event (Gst.Event event) {
        if (auto_rotation && event.type == Gst.EventType.TAG) {
            Gst.TagList? tags;
            event.parse_tag (out tags);
            if (tags != null) {
                string? orientation = null;
                if (tags.get_string ("image-orientation", out orientation) && orientation != null) {
                    rotation = parse_orientation_tag (orientation);
                }
            }
        }
        return base.event (event);
    }

    private int parse_orientation_tag (string tag) {
        switch (tag) {
            case "rotate-90": return 90;
            case "rotate-180": return 180;
            case "rotate-270": return 270;
            default: return 0;
        }
    }

    public override Gst.FlowReturn show_frame (Gst.Buffer buffer) {
        video_render = true;
        var caps = get_static_pad ("sink").get_current_caps ();
        if (caps == null) {
            return Gst.FlowReturn.OK;
        }
        frame_lock.lock ();
        pending_buffer = buffer;
        pending_caps = caps;
        frame_lock.unlock ();
        if (pending_invoke == 0) {
            if (GLib.AtomicInt.compare_and_exchange (ref pending_invoke, 0, 1)) {
                GLib.MainContext.default ().invoke_full (GLib.Priority.DEFAULT, () => {
                    GLib.AtomicInt.set (ref pending_invoke, 0);
                    pending_invoke = 0;
                    handle_frame_changed ();
                    return GLib.Source.REMOVE;
                });
            }
        }
        return Gst.FlowReturn.OK;
    }

    private void handle_frame_changed () {
        Gst.Buffer? buf;
        Gst.Caps? caps;
        frame_lock.lock ();
        buf = (owned) pending_buffer;
        caps = pending_caps;
        pending_buffer = null;
        pending_caps = null;
        frame_lock.unlock ();
        if (buf == null || caps == null) {
            return;
        }
        int w, h;
        unowned Gst.Structure st = caps.get_structure (0);
        st.get_int ("width", out w);
        st.get_int ("height", out h);

        cache_clean_counter++;
        bool do_cleanup = (cache_clean_counter >= CACHE_CLEAN_INTERVAL);
        if (do_cleanup) {
            used_texture_keys.clear ();
            cache_clean_counter = 0;
        }
        var vf = new VideoFrame (buf, caps, texture_cache, used_texture_keys);
        var new_textures = vf.into_textures ();
        if (do_cleanup) {
            texture_cache.foreach_remove ((key, _) => !used_texture_keys.contains (key));
        }
        if (new_textures != null && new_textures.length > 0) {
            cached_textures = null;
            bool size_changed = (display_width != w || display_height != h);
            display_width = w;
            display_height = h;
            cached_textures = new_textures;
            if (size_changed) {
                resize_changed (w, h);
                safe_invalidate_size ();
            }
            safe_invalidate_contents ();
        }
    }

    public bool has_crop () {
        return crop_w > 0 && crop_h > 0;
    }

    private void build_color_matrix (out Graphene.Matrix mat, out Graphene.Vec4 offset) {
        float c = (float)(contrast + 1.0);
        float s = (float)(saturation + 1.0);
        float b = (float) brightness;
        float angle = (float)(hue * Math.PI);
        float cos_h = (float) Math.cos (angle);
        float sin_h = (float) Math.sin (angle);
        float h00 = 0.299f + 0.701f*cos_h + 0.168f*sin_h;
        float h01 = 0.587f - 0.587f*cos_h + 0.330f*sin_h;
        float h02 = 0.114f - 0.114f*cos_h - 0.497f*sin_h;
        float h10 = 0.299f - 0.299f*cos_h - 0.328f*sin_h;
        float h11 = 0.587f + 0.413f*cos_h + 0.035f*sin_h;
        float h12 = 0.114f - 0.114f*cos_h + 0.292f*sin_h;
        float h20 = 0.299f - 0.300f*cos_h + 1.250f*sin_h;
        float h21 = 0.587f - 0.588f*cos_h - 1.050f*sin_h;
        float h22 = 0.114f + 0.886f*cos_h - 0.203f*sin_h;
        float Wr = 0.299f, Wg = 0.587f, Wb = 0.114f;
        float m00 = s*h00 + (1f-s)*Wr;
        float m01 = s*h01 + (1f-s)*Wg;
        float m02 = s*h02 + (1f-s)*Wb;
        float m10 = s*h10 + (1f-s)*Wr;
        float m11 = s*h11 + (1f-s)*Wg;
        float m12 = s*h12 + (1f-s)*Wb;
        float m20 = s*h20 + (1f-s)*Wr;
        float m21 = s*h21 + (1f-s)*Wg;
        float m22 = s*h22 + (1f-s)*Wb;
        float[] values = {
            c*m00, c*m10, c*m20, 0f,
            c*m01, c*m11, c*m21, 0f,
            c*m02, c*m12, c*m22, 0f,
            0f, 0f, 0f, 1f
        };
        mat = Graphene.Matrix ();
        mat.init_from_float (values);
        float ov = b + (1f - c) * 0.5f;
        double g = gamma.clamp (0.1, 10.0);
        float gslope = (float)((1.0 / g) * Math.pow (0.5, 1.0 / g - 1.0));
        float goff = (float)(Math.pow (0.5, 1.0 / g) - gslope * 0.5);
        float[] gv = {
            gslope*c*m00, gslope*c*m10, gslope*c*m20, 0f,
            gslope*c*m01, gslope*c*m11, gslope*c*m21, 0f,
            gslope*c*m02, gslope*c*m12, gslope*c*m22, 0f,
            0f, 0f, 0f, 1f
        };
        mat = Graphene.Matrix ();
        mat.init_from_float (gv);
        ov = gslope * ov + goff;
        offset = Graphene.Vec4 ();
        offset.init (ov, ov, ov, 0f);
    }

    private void seek_start_anim () {
        seek_anim_active = true;
        ensure_master_timer ();
    }

    public void show_color_osd (double br, double co, double sa, double hu, double ga = 1.0) {
        osd[0].val = br;
        osd[1].val = co;
        osd[2].val = sa;
        osd[3].val = hu;
        osd[4].val = ga;
        osd_op = 1.0;
        osd_fading = false;
        osd_anim_active = true;
        if (osd_hold != 0) {
            GLib.Source.remove (osd_hold);
        }
        osd_hold = GLib.Timeout.add (2500, () => {
            osd_fading = true;
            osd_hold = 0;
            return GLib.Source.REMOVE;
        });
        ensure_master_timer ();
    }

    private void ensure_master_timer () {
        if (master_tid != 0) {
            return;
        }
        master_tid = GLib.Timeout.add (16, _master_tick);
    }

    private bool _master_tick () {
        bool keep_running = false;
        bool keep = false;
        if (seek_anim_active) {
            seek_anim += (seek_pos - seek_anim) * 0.22;
            if (Math.fabs (seek_anim - seek_pos) > 0.001) {
                keep_running = true;
            } else {
                seek_anim = seek_pos;
                seek_anim_active = false;
            }
        }
        if (osd_anim_active) {
            for (int i = 0; i < 5; i++) {
                osd[i].anim += (osd[i].val - osd[i].anim) * 0.22;
                if (Math.fabs (osd[i].anim - osd[i].val) < 0.002) {
                    osd[i].anim = osd[i].val;
                }
            }
            if (osd_fading) {
                osd_op -= 0.035;
                if (osd_op <= 0.0) {
                    osd_op = 0.0;
                    osd_anim_active = false;
                } else {
                    keep_running = true;
                }
            } else {
                keep_running = true;
            }
        }
        if (media_info_visible) {
            if (!info_fading && info_op < 1.0) {
                info_op = (info_op + 0.07).clamp (0.0, 1.0);
                keep_running = true;
            } else if (info_fading) {
                info_op -= 0.04;
                if (info_op <= 0.0) {
                    info_op = 0.0;
                    media_info_visible = false;
                    info_fading = false;
                } else {
                    keep_running = true;
                }
            } else {
                keep_running = true;
            }
        }
        if (toast_fading && toast_op > 0.0) {
            toast_op -= 0.04;
            if (toast_op <= 0.0) {
                toast_op = 0.0;
                toast_fading = false;
            } else {
                keep = true;
            }
        } else if (!toast_fading && toast_op > 0.0) {
            keep = true;
        }
        safe_invalidate_contents ();
        if (!keep_running && !keep) {
            master_tid = 0;
            return GLib.Source.REMOVE;
        }
        return GLib.Source.CONTINUE;
    }

    public void toggle_media_info_osd () {
        if (media_info_visible) {
            info_fading = true;
        } else {
            media_info_visible = true;
            info_op = 0.0;
            info_fading = false;
            if (info_hold != 0) {
                GLib.Source.remove (info_hold);
                info_hold = 0;
            }
            info_hold = GLib.Timeout.add (3000, () => {
                info_fading = true;
                info_hold = 0;
                return GLib.Source.REMOVE;
            });
            ensure_master_timer ();
        }
    }

    public void snapshot (Gdk.Snapshot snap, double width, double height) {
        var gtk_snap = snap as Gtk.Snapshot;
        if (gtk_snap == null) {
            return;
        }
        gtk_snap.append_color (background_color, Graphene.Rect ().init (0, 0, (float) width, (float) height));
        bool apply_color = !is_color_identity ();
        if (apply_color) {
            Graphene.Matrix mat;
            Graphene.Vec4 col_offset;
            build_color_matrix (out mat, out col_offset);
            gtk_snap.push_color_matrix (mat, col_offset);
        }
        if (video_render) {
            render_video_frames_rotated (gtk_snap, width, height);
        } else {
            if (avisual_toggle) {
                if (_cover_texture != null) {
                    render_cover (gtk_snap, width, height);
                } else {
                    start_vis_timer ();
                }
            }
        }
        if (apply_color) {
            gtk_snap.pop ();
        }
    }

    public void seek_show () {
        osd_sfading = true;
        if (osd_seek != 0) {
            GLib.Source.remove (osd_seek);
        }
        osd_seek = GLib.Timeout.add (1500, ()=> {
            osd_sfading = false;
            osd_seek = 0;
            return GLib.Source.REMOVE;
        });
    }

    public void update_level (double rms_ll, double rms_r, double peak_ll, double peak_rr) {
        rms_l = _db_to_linear (rms_ll);
        var rms_rr = _db_to_linear (rms_r);
        peak_l = _db_to_linear (peak_ll);
        vis_history[vis_hist_idx] = (rms_l + rms_rr) / 2.0;
        vis_hist_idx = (vis_hist_idx + 1) % vis_history.length;
    }

    private double _db_to_linear (double db) {
        if (db <= -60.0) {
            return 0.0;
        }
        return ((db + 60.0) / 60.0).clamp (0.0, 1.0);
    }

    public void start_vis_timer () {
        if (!avisual_toggle) {
            return;
        }
        if (vis_timer == 0) {
            vis_timer = GLib.Timeout.add (100, vis_tick);
        }
    }

    private bool vis_tick () {
        if (video_render || _cover_texture != null) {
            vis_timer = 0;
            return GLib.Source.REMOVE;
        }
        vis_angle = (vis_angle + 0.016) % (2.0 * Math.PI);
        rms_a += (rms_l - rms_a) * 0.25;
        peak_a += (peak_l - peak_a) * 0.30;
        bool has_activity = rms_a > 0.008;
        if (!has_activity) {
            idle_skip = (idle_skip + 1) % 5;
            if (idle_skip != 0) {
                return GLib.Source.CONTINUE;
            }
        } else {
            idle_skip = 0;
        }
        safe_invalidate_contents ();
        return GLib.Source.CONTINUE;
    }

    public void stop_vis_timer () {
        if (vis_timer == 0) {
            return;
        }
        GLib.Source.remove (vis_timer);
        vis_timer = 0;
    }

    public void render_audio_visualizer (Gtk.Snapshot snap, double width, double height) {
        double W = width, H = height;
        double cx = W / 2.0, cy = H / 2.0;
        double ra = rms_a, pa = peak_a;
        double base_r = double.min (cx, cy) * 0.15;
        snap.append_color (Gdk.RGBA () {alpha = 0f}, Graphene.Rect ().init (0, 0, (float) W, (float) H));
        float outer_r = (float)(base_r * 1.8 + ra * base_r * 1.2);
        gpu_ring (snap, cx, cy, outer_r, Gdk.RGBA () { red=0.55f, green=0.39f, blue=1.0f, alpha=(float)(0.15 + ra * 0.25) }, (float)(outer_r * 0.15));
        float mid_r = (float)(base_r * 1.3 + ra * base_r * 0.6);
        gpu_ring (snap, cx, cy, mid_r, Gdk.RGBA () { red=0.71f, green=0.55f, blue=1.0f, alpha=(float)(0.3 + ra * 0.4) }, 3.0f);
        float core_r = (float)(base_r + pa * base_r * 0.5);
        gpu_circle (snap, cx, cy, core_r, Gdk.RGBA () { red=0.65f, green=0.45f, blue=1.0f, alpha=(float)(0.7 + pa * 0.3) });
        float orbit_r_f = (float)(base_r * 2.2 + ra * 18.0);
        for (int k = 0; k < 3; k++) {
            double a = vis_angle * 2.0 + k * (2.0 * Math.PI / 3.0);
            float dot = (float)(2.5 + ra * 3.5);
            double hk = (0.61 + k * 0.11) % 1.0;
            gpu_circle (snap, cx + Math.cos (a) * orbit_r_f, cy + Math.sin (a) * orbit_r_f, dot, Gdk.RGBA () { red   = (float) _hsl_r (hk, 0.9, 0.75), green = (float) _hsl_g (hk, 0.9, 0.75), blue = (float) _hsl_b (hk, 0.9, 0.75), alpha = (float)(0.6 + ra * 0.4)});
        }
        if (ra > 0.015) {
            var cr = snap.append_cairo (Graphene.Rect ().init (0, 0, (float) W, (float) H));
            int N = vis_history.length;
            double min_dim = double.min (cx, cy);
            double arc_r = min_dim * 0.38;
            double bar_max = (min_dim - arc_r - 20.0).clamp (30.0, 150.0);
            double bar_min = min_dim * 0.025;
            int groups = 8;
            int per_grp = N / groups;
            cr.set_line_width (2.0);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            for (int g = 0; g < groups; g++) {
                double hue = (200.0 + g / (double) groups * 120.0) / 360.0;
                double avg = 0.0;
                cr.new_path ();
                for (int j = 0; j < per_grp; j++) {
                    int idx = (vis_hist_idx + g * per_grp + j) % N;
                    double v = vis_history[idx];
                    double angle = ((g * per_grp + j) / (double) N) * 2.0 * Math.PI + vis_angle;
                    double bl = bar_min + v * bar_max;
                    avg += v;
                    cr.move_to (cx + Math.cos (angle) * arc_r, cy + Math.sin (angle) * arc_r);
                    cr.line_to (cx + Math.cos (angle) * (arc_r + bl), cy + Math.sin (angle) * (arc_r + bl));
                }
                avg /= per_grp;
                cr.set_source_rgba (_hsl_r (hue, 0.8, 0.65), _hsl_g (hue, 0.8, 0.65), _hsl_b (hue, 0.8, 0.65), 0.35 + avg * 0.65);
                cr.stroke ();
            }
        }
    }

    private void gpu_circle (Gtk.Snapshot snap, double cx, double cy, float r, Gdk.RGBA color) {
        float x = (float)(cx - r), y = (float)(cy - r);
        var rr = Gsk.RoundedRect ();
        rr.init_from_rect (Graphene.Rect ().init (x, y, r * 2, r * 2), r);
        snap.push_rounded_clip (rr);
        snap.append_color (color, Graphene.Rect ().init (x, y, r * 2, r * 2));
        snap.pop ();
    }

    private void gpu_ring (Gtk.Snapshot snap, double cx, double cy, float r, Gdk.RGBA color, float border_w) {
        float x = (float)(cx - r), y = (float)(cy - r);
        var rr = Gsk.RoundedRect ();
        rr.init_from_rect (Graphene.Rect ().init (x, y, r * 2, r * 2), r);
        float[] bw = { border_w, border_w, border_w, border_w };
        Gdk.RGBA[] bc = { color, color, color, color };
        snap.append_border (rr, bw, bc);
    }

    private double hsl_component (double p, double q, double t) {
        if (t < 0) {
            t += 1;
        }
        if (t > 1) {
            t -= 1;
        }
        if (t < 1.0/6) {
            return p + (q - p) * 6.0 * t;
        }
        if (t < 0.5) {
            return q;
        }
        if (t < 2.0/3) {
            return p + (q - p) * (2.0/3 - t) * 6.0;
        }
        return p;
    }

    private double hsl_q (double h, double s, double l) {
        return l < 0.5 ? l * (1 + s) : l + s - l * s;
    }

    private double _hsl_p (double h, double s, double l) {
        return 2.0 * l - hsl_q (h, s, l);
    }

    private double _hsl_r (double h, double s, double l) {
        return hsl_component (_hsl_p(h,s,l), hsl_q(h,s,l), h + 1.0/3);
    }

    private double _hsl_g (double h, double s, double l) {
        return hsl_component (_hsl_p(h,s,l), hsl_q(h,s,l), h);
    }

    private double _hsl_b (double h, double s, double l) {
        return hsl_component (_hsl_p(h,s,l), hsl_q(h,s,l), h - 1.0/3);
    }

    public void render_seeker_osd (Gtk.Snapshot snap, double width, double height) {
        if (!osd_sfading) {
            return;
        }
        const float BH = 3.0f;
        float by = (float) height - BH;
        var track_rr = Gsk.RoundedRect ();
        track_rr.init_from_rect (Graphene.Rect ().init (0, by, (float) width, BH), BH / 2.0f);
        snap.push_rounded_clip (track_rr);
        snap.append_color (Gdk.RGBA () { red=1f, green=1f, blue=1f, alpha=0.15f }, Graphene.Rect ().init (0, by, (float) width, BH));
        snap.pop ();
        if (seek_buf > 0.001) {
            float bw = (float)(seek_buf * width);
            var buf_rr = Gsk.RoundedRect ();
            buf_rr.init_from_rect (Graphene.Rect ().init (0, by, bw, BH), BH / 2.0f);
            snap.push_rounded_clip (buf_rr);
            snap.append_color (Gdk.RGBA () { red=1f, green=1f, blue=1f, alpha=0.22f }, Graphene.Rect ().init (0, by, bw, BH));
            snap.pop ();
        }
        if (volume_vis && vol_osd > 0.001) {
            float pw = (float)(vol_osd * width);
            var pos_rr = Gsk.RoundedRect ();
            pos_rr.init_from_rect (Graphene.Rect ().init (0, by, pw, BH), BH / 2.0f);
            snap.push_rounded_clip (pos_rr);
            snap.append_color (Gdk.RGBA () { red=0.12f, green=0.9f, blue=0.12f, alpha=1.0f }, Graphene.Rect ().init (0, by, pw, BH));
            snap.pop ();
            return;
        } else if (seek_anim > 0.001) {
            float pw = (float)(seek_anim * width);
            var pos_rr = Gsk.RoundedRect ();
            pos_rr.init_from_rect (Graphene.Rect ().init (0, by, pw, BH), BH / 2.0f);
            snap.push_rounded_clip (pos_rr);
            snap.append_color (Gdk.RGBA () { red=0.9f, green=0.12f, blue=0.12f, alpha=1.0f }, Graphene.Rect ().init (0, by, pw, BH));
            snap.pop ();
        }
    }

    public void render_color_osd (Gtk.Snapshot snap, double width, double height) {
        if (osd_op < 0.01) {
            return;
        }
        float scale = (float)((height / 500.0).clamp (0.2, 1.5));
        float PW = 215.0f * scale;
        float RH = 27.0f * scale;
        float GAP = 5.0f * scale;
        float PADX = 12.0f * scale;
        float PADY = 10.0f * scale;
        float VW = 40.0f * scale;
        float icon_size = RH * 0.72f;
        float actual_lw = icon_size + 6.0f * scale;
        float ph = 5.0f * RH + 4.0f * GAP + 2.0f * PADY;
        float px = ((float) width - PW) / 2.0f;
        float py = ((float) height - ph) / 2.0f;
        snap.push_opacity (osd_op);
        var panel_rr = Gsk.RoundedRect ();
        panel_rr.init_from_rect (Graphene.Rect ().init (px, py, PW, ph), 10.0f * scale);
        snap.push_rounded_clip (panel_rr);
        snap.append_color (Gdk.RGBA () { red=0.0f, green=0.0f, blue=0.0f, alpha=0.72f }, Graphene.Rect ().init (px, py, PW, ph));
        snap.pop ();
        int font_pt = ((int)(height * 0.026)).clamp (6, 14);
        for (int i = 0; i < osd_icons.length; i++) {
            float ry = py + PADY + i * (RH + GAP);
            float bx = px + PADX + actual_lw;
            float by2 = ry + (RH - 6.0f * scale) / 2.0f;
            float bw = PW - PADX * 2.0f - actual_lw - VW - 8.0f * scale;
            float cx = bx + bw / 2.0f;
            var tr_rr = Gsk.RoundedRect ();
            tr_rr.init_from_rect (Graphene.Rect ().init (bx, by2, bw, 6.0f * scale), 3.0f * scale);
            snap.push_rounded_clip (tr_rr);
            snap.append_color (Gdk.RGBA () { red=1f, green=1f, blue=1f, alpha=0.12f }, Graphene.Rect ().init (bx, by2, bw, 6.0f * scale));
            snap.pop ();
            snap.append_color (Gdk.RGBA () { red=1f, green=1f, blue=1f, alpha=0.45f }, Graphene.Rect ().init (cx - 0.75f, by2 - 3.0f * scale, 1.5f, 12.0f * scale));
            double v = (i == 4) ? (osd[i].anim - 1.0).clamp (-1.0, 1.0) : osd[i].anim;
            float tx = cx + (float)(v * bw / 2.0);
            float fw = tx - cx;
            if (Math.fabsf (fw) > 0.5f) {
                var fl_rr = Gsk.RoundedRect ();
                fl_rr.init_from_rect (Graphene.Rect ().init (float.min (tx, cx), by2, Math.fabsf (fw), 6.0f * scale), 3.0f * scale);
                snap.push_rounded_clip (fl_rr);
                snap.append_color (v > 0 ? Gdk.RGBA () { red=0.95f, green=0.43f, blue=0.07f, alpha=1.0f } : Gdk.RGBA () { red=0.22f, green=0.52f, blue=0.97f, alpha=1.0f }, Graphene.Rect ().init (float.min (tx, cx), by2, Math.fabsf (fw), 6.0f * scale));
                snap.pop ();
            }
            float icon_x = px + PADX;
            float icon_y = ry + (RH - icon_size) / 2.0f;
            snap.save ();
            snap.translate (Graphene.Point () { x = icon_x, y = icon_y });
            osd_icons[i].snapshot (snap, (double) icon_size, (double) icon_size);
            snap.restore ();
            string vs = (i == 4) ? "%.2f".printf (osd[i].val) : "%+.2f".printf (osd[i].val);
            var val_layout = new Pango.Layout (get_pango_context ());
            val_layout.set_text (vs, -1);
            var val_font = new Pango.FontDescription ();
            val_font.set_family ("Sans");
            val_font.set_size (font_pt * Pango.SCALE);
            val_font.set_weight (Pango.Weight.BOLD);
            val_layout.set_font_description (val_font);
            int vw_px, vh_px;
            val_layout.get_pixel_size (out vw_px, out vh_px);
            snap.save ();
            snap.translate (Graphene.Point () {
                x = px + PW - PADX - vw_px,
                y = ry + (RH - vh_px) / 2.0f
            });
            snap.append_layout (val_layout, Gdk.RGBA () { red=1f, green=1f, blue=1f, alpha=0.9f });
            snap.restore ();
        }
        snap.pop ();
    }

    private void render_video_frames_rotated (Gtk.Snapshot snap, double width, double height) {
        if (cached_textures == null || cached_textures.length == 0) {
            return;
        }
        if (_rotation == 0) {
            render_video_frames (snap, width, height);
            return;
        }
        double render_w = width;
        double render_h = height;
        float cx = (float)(width / 2.0);
        float cy = (float)(height / 2.0);
        var transform = new Gsk.Transform ();
        transform = transform.translate (Graphene.Point () { x = cx, y = cy });
        transform = transform.rotate ((float) _rotation);
        if (_rotation == 90 || _rotation == 270) {
            render_w = height;
            render_h = width;
            transform = transform.translate (Graphene.Point () { x = -(float)(render_w / 2.0), y = -(float)(render_h / 2.0)});
        } else {
            transform = transform.translate (Graphene.Point () { x = -(float)(render_w / 2.0), y = -(float)(render_h / 2.0)});
        }
        snap.save ();
        snap.transform (transform);
        render_video_frames (snap, render_w, render_h);
        snap.restore ();
    }

    private void render_video_frames (Gtk.Snapshot snap, double width, double height) {
        if (cached_textures == null || cached_textures.length == 0) {
            return;
        }
        unowned FrameTexture main = cached_textures.get (0);
        if (main == null) {
            return;
        }
        Gsk.ScalingFilter filter = resolution_sacaled (display_width, display_height);
        double src_w = has_crop () ? crop_w : (double) main.width;
        double src_h = has_crop () ? crop_h : (double) main.height;
        double sx = width / src_w;
        double sy = height / src_h;
        double ox = 0, oy = 0;
        if (force_aspect_ratio) {
            double scale = double.min (sx, sy);
            ox = (width - src_w * scale) / 2.0;
            oy = (height - src_h * scale) / 2.0;
            sx = sy = scale;
        }
        if (has_crop ()) {
            snap.push_clip (Graphene.Rect ().init ((float) ox, (float) oy, (float)(src_w * sx), (float)(src_h * sy)));
        }
        for (uint i = 0; i < cached_textures.length; i++) {
            unowned FrameTexture ft = cached_textures.get (i);
            bool need_opacity = ft.global_alpha < 0.9999f;
            if (need_opacity) {
                snap.push_opacity (ft.global_alpha);
            }
            float bx, by, bw, bh;
            if (i == 0) {
                if (has_crop ()) {
                    bx = (float)(ox - crop_x * sx);
                    by = (float)(oy - crop_y * sy);
                    bw = (float)(main.width * sx);
                    bh = (float)(main.height * sy);
                } else {
                    bx = force_aspect_ratio ? (float) ox : 0f;
                    by = force_aspect_ratio ? (float) oy : 0f;
                    bw = force_aspect_ratio ? (float)(main.width * sx) : (float) width;
                    bh = force_aspect_ratio ? (float)(main.height * sy) : (float) height;
                }
            } else {
                bx = (float)(ox + (ft.x - (has_crop () ? crop_x : 0)) * sx);
                by = (float)(oy + (ft.y - (has_crop () ? crop_y : 0)) * sy);
                bw = (float) double.min (ft.width * sx, width - bx);
                bh = (float) double.min (ft.height * sy, height - by);
            }
            snap.append_scaled_texture ( ft.texture, filter, Graphene.Rect ().init (bx, by, bw, bh));
            if (need_opacity) {
                snap.pop ();
            }
        }
        if (has_crop ()) {
            snap.pop ();
        }
    }

    private Gsk.ScalingFilter resolution_sacaled (int widt, int heigh) {
        int res = int.max (widt, heigh);
        if (res >= 1280) {
            return Gsk.ScalingFilter.LINEAR;
        } else {
            return Gsk.ScalingFilter.TRILINEAR;
        }
    }

    private void render_cover (Gtk.Snapshot snap, double width, double height) {
        double tw = (double) _cover_texture.width;
        double th = (double) _cover_texture.height;
        double scale = double.min (width / tw, height / th);
        float cw = (float)(tw * scale);
        float ch = (float)(th * scale);
        float cx = (float)((width - cw) / 2.0);
        float cy = (float)((height - ch) / 2.0);
        snap.append_texture (_cover_texture, Graphene.Rect ().init (cx, cy, cw, ch));
    }

    public void show_toast (string text) {
        toast_text = text;
        toast_op = 1.0;
        toast_fading = false;
        if (toast_hold != 0) {
            GLib.Source.remove (toast_hold);
        }
        toast_hold = GLib.Timeout.add (2000, () => {
            toast_fading = true;
            toast_hold = 0;
            return GLib.Source.REMOVE;
        });
        ensure_master_timer ();
    }

    public void render_toast (Gtk.Snapshot snap, double width, double height) {
        if (toast_op < 0.01 || toast_text == "") {
            return;
        }
        var pango_ctx = get_pango_context ();
        var layout = new Pango.Layout (pango_ctx);
        var font = new Pango.FontDescription ();
        font.set_family ("Sans");
        int font_pt = ((int)(height * 0.028)).clamp (2, 14);
        font.set_size (font_pt * Pango.SCALE);
        font.set_weight (Pango.Weight.SEMIBOLD);
        layout.set_font_description (font);
        const double MAX_RATIO = 0.75;
        float max_w = (float)(width * MAX_RATIO);
        layout.set_text (toast_text, -1);
        layout.set_alignment (Pango.Alignment.CENTER);
        int tw_single, th_single;
        layout.get_pixel_size (out tw_single, out th_single);
        if (tw_single > (int) max_w) {
            layout.set_width ((int)(max_w * Pango.SCALE));
            layout.set_wrap (Pango.WrapMode.WORD_CHAR);
        }
        int tw, th;
        layout.get_pixel_size (out tw, out th);
        float scale = (float)(height / 400.0).clamp (0.6, 2.0);
        float PADX = 18.0f * scale;
        float PADY = 10.0f * scale;
        float bw = float.min ((float) tw, max_w) + PADX * 2;
        float bh = (float) th + PADY * 2;
        float bx = ((float) width - bw) / 2.0f;
        float by = (float)(height * 0.12f);
        snap.push_opacity (toast_op);
        float corner = float.min (bh / 2.0f, 16.0f);
        var rr = Gsk.RoundedRect ();
        rr.init_from_rect (Graphene.Rect ().init (bx, by, bw, bh), corner);
        if (outline_mode) {
            snap.push_rounded_clip (rr);
            snap.append_color (Gdk.RGBA () { red=0.1f, green=0.1f, blue=0.12f, alpha=0.55f }, Graphene.Rect ().init (bx, by, bw, bh));
            snap.pop ();
            float[] bwidths = { 1.0f, 1.0f, 1.0f, 1.0f };
            Gdk.RGBA border = { 1.0f, 1.0f, 1.0f, 0.2f };
            Gdk.RGBA[] bcols = { border, border, border, border };
            snap.append_border (rr, bwidths, bcols);
        }
        float text_x = bx + PADX;
        float text_y = by + PADY;
        float outline = outline_mode? 0f : (1.0f * scale);
        float[] dx = { 0f, 1f, 1f, 1f, 0f, -1f, -1f, -1f };
        float[] dy = {-1f, -1f, 0f, 1f, 1f, 1f, 0f, -1f };
        for (int d = 0; d < 8; d++) {
            snap.save ();
            snap.translate (Graphene.Point () {
                x = text_x + dx[d] * outline,
                y = text_y + dy[d] * outline
            });
            snap.append_layout (layout, Gdk.RGBA () { red=0f, green=0f, blue=0f, alpha=0.75f });
            snap.restore ();
        }
        snap.save ();
        snap.translate (Graphene.Point () { x = text_x, y = text_y });
        snap.append_layout (layout, Gdk.RGBA () { red=1f, green=1f, blue=1f, alpha=1f });
        snap.restore ();
        snap.pop ();
    }

    public void show_media_info (MediaInfo info) {
        media_info = info;
    }

    public void render_media_info_osd (Gtk.Snapshot snap, double width, double height) {
        if (!media_info_visible || info_op < 0.01) {
            return;
        }
        var rows = media_info.to_rows ();
        int n_rows = rows.length[0];
        var pango_ctx = get_pango_context ();
        int visible = 0;
        for (int i = 0; i < n_rows; i++) {
            bool is_sep = rows[i, 0].has_prefix ("─");
            if (is_sep || (rows[i, 1] != "" && rows[i, 1] != null)) {
                visible++;
            }
        }
        if (visible == 0) {
            return;
        }
        float PADX = 14.0f;
        float PADY = 8.0f;
        float GAP = 1.0f;
        float SEP_W = 8.0f;
        float PW = ((float) width * 0.35f).clamp (90.0f, 450.0f);
        float inner = PW - PADX * 2.0f;
        float LW = (inner - SEP_W) * 0.25f;
        float max_ph = (float)(height * 0.90f);
        float avail = max_ph - PADY * 2.0f - (visible - 1) * GAP;
        float RH = (avail / visible).clamp (4.0f, 18.0f);
        int font_pt = ((int)(RH * 0.60f)).clamp (4, 18);
        float PH = PADY * 2.0f + visible * RH + (visible - 1) * GAP;
        float px = 16.0f;
        float py = ((float) height - PH) / 2.0f;
        float sep_x_abs = px + PADX + LW + 4.0f;
        var panel_rr = Gsk.RoundedRect ();
        panel_rr.init_from_rect (Graphene.Rect ().init (px, py, PW, PH), 8.0f);
        snap.push_opacity (info_op);
        if (!outline_mode) {
            snap.push_rounded_clip (panel_rr);
            snap.append_color (Gdk.RGBA () { alpha=0f }, Graphene.Rect ().init (px, py, PW, PH));
            snap.pop ();
            float[] bwidths = { 1.0f, 1.0f, 1.0f, 1.0f };
            Gdk.RGBA bc = { 1.0f, 1.0f, 1.0f, 0.2f };
            Gdk.RGBA[] bcols = { bc, bc, bc, bc };
            snap.append_border (panel_rr, bwidths, bcols);
        } else {
            snap.push_rounded_clip (panel_rr);
            snap.append_color (Gdk.RGBA () { red=0.1f, green=0.1f, blue=0.12f, alpha=0.55f }, Graphene.Rect ().init (px, py, PW, PH));
            snap.pop ();
            float[] bwidths = { 1.0f, 1.0f, 1.0f, 1.0f };
            Gdk.RGBA bc = { 1.0f, 1.0f, 1.0f, 0.12f };
            Gdk.RGBA[] bcols = { bc, bc, bc, bc };
            snap.append_border (panel_rr, bwidths, bcols);
        }
        snap.append_color (Gdk.RGBA () { red=1f, green=1f, blue=1f, alpha=0.1f }, Graphene.Rect ().init (sep_x_abs, py + PADY, 1.0f, PH - PADY * 2.0f));
        float outline_px = outline_mode ? 0.0f : 1.0f;
        float[] dx = { 0f, 1f, 1f, 1f, 0f, -1f, -1f, -1f };
        float[] dy = { -1f, -1f, 0f, 1f, 1f, 1f, 0f, -1f };
        int vi = 0;
        for (int i = 0; i < n_rows; i++) {
            string label = rows[i, 0];
            string val = rows[i, 1] ?? "";
            bool is_sep = label.has_prefix ("─");
            if (!is_sep && val == "") {
                continue;
            }
            float ry = py + PADY + vi * (RH + GAP);
            vi++;
            if (is_sep) {
                snap.append_color (Gdk.RGBA () { red=1f, green=1f, blue=1f, alpha=0.12f }, Graphene.Rect ().init (px + PADX, ry + RH * 0.5f, PW - PADX * 2.0f, 1.0f));

                string hdr = label.replace ("─", "").strip ();
                if (hdr != "") {
                    var h_layout = new Pango.Layout (pango_ctx);
                    var h_font = new Pango.FontDescription ();
                    h_font.set_family ("Sans");
                    h_font.set_size ((font_pt - 1).clamp (5, 12) * Pango.SCALE);
                    h_font.set_weight (Pango.Weight.BOLD);
                    h_layout.set_font_description (h_font);
                    h_layout.set_text (hdr, -1);
                    int hw, hh;
                    h_layout.get_pixel_size (out hw, out hh);
                    float hx = px + (PW - hw) / 2.0f;
                    float hy = ry + (RH - hh) / 2.0f;
                    snap.append_color (Gdk.RGBA () { red=0.05f, green=0.05f, blue=0.1f, alpha=0.82f }, Graphene.Rect ().init (hx - 4, hy, hw + 8, (float) hh));
                    draw_text (snap, h_layout, hx, hy, Gdk.RGBA () { red=0.55f, green=0.75f, blue=1.0f, alpha=0.9f }, outline_px, dx, dy);
                }
                continue;
            }
            var lbl_layout = new Pango.Layout (pango_ctx);
            var lbl_font = new Pango.FontDescription ();
            lbl_font.set_family ("Sans");
            lbl_font.set_size (font_pt * Pango.SCALE);
            lbl_font.set_weight (Pango.Weight.NORMAL);
            lbl_layout.set_font_description (lbl_font);
            lbl_layout.set_text (label, -1);
            lbl_layout.set_width ((int)(LW * Pango.SCALE));
            lbl_layout.set_ellipsize (Pango.EllipsizeMode.END);
            int lw_px, lh_px;
            lbl_layout.get_pixel_size (out lw_px, out lh_px);
            draw_text (snap, lbl_layout, px + PADX, ry + (RH - lh_px) / 2.0f, Gdk.RGBA () { red=0.65f, green=0.65f, blue=0.7f, alpha=1.0f }, outline_px, dx, dy);
            var val_layout = new Pango.Layout (pango_ctx);
            var val_font = new Pango.FontDescription ();
            val_font.set_family ("Sans");
            val_font.set_size (font_pt * Pango.SCALE);
            val_font.set_weight (Pango.Weight.SEMIBOLD);
            val_layout.set_font_description (val_font);
            val_layout.set_text (val, -1);
            float val_x = sep_x_abs + 6.0f;
            float val_max = (px + PW - PADX) - val_x;
            val_layout.set_width ((int)(val_max * Pango.SCALE));
            val_layout.set_ellipsize (Pango.EllipsizeMode.END);
            int vw_px, vh_px;
            val_layout.get_pixel_size (out vw_px, out vh_px);
            draw_text (snap, val_layout,val_x, ry + (RH - vh_px) / 2.0f, Gdk.RGBA () { red=1f, green=1f, blue=1f, alpha=0.95f }, outline_px, dx, dy);
        }
        snap.pop ();
    }

    private void draw_text (Gtk.Snapshot snap, Pango.Layout layout, float tx, float ty, Gdk.RGBA color, float outline_px, float[] dx, float[] dy) {
        if (outline_px > 0) {
            for (int d = 0; d < 8; d++) {
                snap.save ();
                snap.translate (Graphene.Point () {
                    x = tx + dx[d] * outline_px,
                    y = ty + dy[d] * outline_px
                });
                snap.append_layout (layout, Gdk.RGBA () { red=0f, green=0f, blue=0f, alpha=0.75f });
                snap.restore ();
            }
        }
        snap.save ();
        snap.translate (Graphene.Point () { x = tx, y = ty });
        snap.append_layout (layout, color);
        snap.restore ();
    }

    public void set_crop (int x, int y, int w, int h) {
        crop_x = x;
        crop_y = y;
        crop_w = w;
        crop_h = h;
        safe_invalidate_size ();
        safe_invalidate_contents ();
    }

    public void reset_crop () {
        crop_x = 0;
        crop_y = 0;
        crop_w = 0;
        crop_h = 0;
        safe_invalidate_size ();
        safe_invalidate_contents ();
    }

    public int get_intrinsic_width () {
        int w = has_crop () ? crop_w : display_width;
        int h = has_crop () ? crop_h : display_height;
        return (_rotation == 90 || _rotation == 270) ? h : w;
    }

    public int get_intrinsic_height () {
        int w = has_crop () ? crop_w : display_width;
        int h = has_crop () ? crop_h : display_height;
        return (_rotation == 90 || _rotation == 270) ? w : h;
    }

    public double get_intrinsic_aspect_ratio () {
        int w = get_intrinsic_width ();
        int h = get_intrinsic_height ();
        return (h > 0) ? (double) w / h : 0.0;
    }

    public Gdk.PaintableFlags get_flags () {
        return (Gdk.PaintableFlags) 0;
    }
}