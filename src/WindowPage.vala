public class WindowPage : Gtk.Window {
    private Gtk.Picture video_embed;
    private Gtk.Button prev_button;
    private Gtk.Button next_button;
    private Gtk.Revealer control_revealer;
    private Gst.Element pipeline;
    private PlayXVsink video_sink;
    private PeakBar peak_bar;
    private TransparentHeader ctr_bottom;
    private LabelOutline name_label;
    private LabelOutline position_lbl;
    private LabelOutline duration_lbl;
    private LabelOutline title_lbl;
    private LabelOutline spd_lbl;
    private Gtk.Revealer header_revealer;
    private Gdk.Paintable? background_source = null;
    private VideoWithCrop video_with_crop;
    private Gdk.Cursor default_cursor;
    private Gdk.Cursor blank_cursor;
    private Gee.ArrayList<string> vide_list;
    private Gdk.Texture? cached_cover = null;
    private PlayXaudio audio_sink_bin;
    public bool is_playing {get; set; default = false;}
    public bool black_blur {get; set; default = true;}
    public bool seeked {get; set; default = false;}
    private bool initbitor = false;
    private bool controls_hovered = false;
    private bool head_hovered = false;
    private uint hide_controls_timeout = 0;
    private uint hide_header_timeout = 0;
    private uint last_press_time = 0;
    private uint gtk_cookie = 0;
    private double duration;
    private double pos_sec = 0.0;
    private double playback_rate = 1.0;
    private int current_preset = 0;
    private int current_index = -1;
    private int current_audio = 0;
    private int current_video = 0;
    private int current_subt = 0;
    private int speed_index = 5;
    private string[] preset_names = {"Flat", "Bass Boost", "Treble Boost", "Vocal", "Rock", "Jazz", "Classical", "Pop", "Electronic", "Lounge", "Hifi", "Cinema"};
    private string[] video_files;
    private double[] speed_steps = { 0.2, 0.4, 0.6, 0.7, 0.8, 1.0, 1.2, 1.4, 1.6, 1.7, 1.8, 2.0 };
    private string? cached_cover_uri = null;

    public WindowPage (Gtk.Application app) {
        Object (application: app);
    }

    construct {
        set_default_size (500, 280);
        default_cursor = new Gdk.Cursor.from_name ("default", null);
        blank_cursor = new Gdk.Cursor.from_name ("none", null);
        vide_list = new Gee.ArrayList<string> ();

        video_embed = new Gtk.Picture () {
            content_fit = Gtk.ContentFit.CONTAIN,
            hexpand = true,
            vexpand = true,
            can_shrink = true
        };

        var overlay = new Gtk.Overlay () {
            hexpand = true,
            vexpand = true,
            child = video_embed
        };
        move_window (this, video_embed);
        title_lbl = new LabelOutline () {
            fontsize = 12,
            label = _("PlayX")
        };
        var iconext = new IconOutline () {
            icon_name = "media-skip-forward-symbolic",
            icon_size = 16,
            outline_width = 0.6,
            icon_color = { 1f, 1f, 1f, 1f },
            outline_color = { 0f, 0f, 0f, 0.85f }
        };
        next_button = new Gtk.Button () {
            has_frame = false,
            child = iconext
        };

        var icoprev = new IconOutline () {
            icon_name = "media-skip-backward-symbolic",
            icon_size = 16,
            outline_width = 0.6,
            icon_color = { 1f, 1f, 1f, 1f },
            outline_color = { 0f, 0f, 0f, 0.85f }
        };
        prev_button = new Gtk.Button () {
            has_frame = false,
            child = icoprev
        };
        var navwidg = new Gtk.CenterBox () {
            start_widget = prev_button,
            end_widget = next_button,
            center_widget = title_lbl
        };
        var win_controls = new Gtk.HeaderBar () {
            decoration_layout = ":close",
            hexpand = true,
            title_widget = navwidg
        };

        var icoopen = new IconOutline () {
            icon_name = "document-open-symbolic",
            icon_size = 16,
            outline_width = 0.6,
            icon_color = { 1f, 1f, 1f, 1f },
            outline_color = { 0f, 0f, 0f, 0.85f }
        };
        var open_button = new Gtk.Button () {
            tooltip_text = _("Open Image"),
            has_frame = false,
            child = icoopen
        };
        open_button.clicked.connect (()=> {
            on_open_clicked.begin ((obj, res)=> {
                try {
                    on_open_clicked.end (res);
                } catch {}
            });
        });
        win_controls.pack_start (open_button);

        var header = new TransparentHeader (Gtk.Orientation.HORIZONTAL, 0);
        header.append (win_controls);
        title_lbl.notify["label"].connect (header.queue_draw);
        header_revealer = new Gtk.Revealer () {
            transition_type = Gtk.RevealerTransitionType.CROSSFADE,
            transition_duration = 300,
            child = header,
            reveal_child = false,
            halign = Gtk.Align.FILL,
            valign = Gtk.Align.START
        };
        overlay.add_overlay (header_revealer);
        next_button.clicked.connect (() => {
            nav_video (1);
            header.queue_draw();
        });
        prev_button.clicked.connect (() => {
            nav_video (-1);
            header.queue_draw();
        });
        var motionroller = new Gtk.EventControllerMotion ();
        motionroller.enter.connect (() => {
            head_hovered = true;
            header_controls ();
        });
        motionroller.leave.connect (() => {
            head_hovered = false;
            schedule_hide_header ();
        });
        header_revealer.add_controller (motionroller);

        var center_ctr = new TransparentHeader (Gtk.Orientation.HORIZONTAL, 0) {
            halign = Gtk.Align.FILL,
            hexpand = true,
            margin_start = 8,
            margin_end = 8
        };

        var icoplay = new IconOutline () {
            icon_name = "media-playback-start-symbolic",
            icon_size = 16,
            outline_width = 0.6,
            icon_color = { 1f, 1f, 1f, 1f },
            outline_color = { 0f, 0f, 0f, 0.85f }
        };
        var play_button = new Gtk.Button () {
            has_frame = false,
            child = icoplay
        };
        play_button.clicked.connect (() => {
            is_playing = !is_playing;
        });

        notify["is-playing"].connect (()=> {
            if (!is_playing) {
                icoplay.icon_name = "media-playback-start-symbolic";
                pause_video();
                video_sink.stop_vis_timer ();
                uninhibit ();
            } else {
                play_video();
                video_sink.start_vis_timer ();
                icoplay.icon_name = "media-playback-pause-symbolic";
                inhibit ();
            }
            ctr_bottom.queue_draw();
        });

        spd_lbl = new LabelOutline () {
            fontsize = 12,
            label = _("1.0")
        };
        var settings_button = new Gtk.Button () {
            has_frame = false,
            child = spd_lbl
        };
        settings_button.clicked.connect (() => {
            if (speed_steps[speed_index] == 2.0) {
                speed_index = -1;
            }
            speed_up ();
            center_ctr.queue_draw();
        });
        position_lbl = new LabelOutline () {
            fontsize = 12
        };

        duration_lbl = new LabelOutline () {
            fontsize = 12
        };

        var start_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        start_box.append (play_button);
        start_box.append (position_lbl);

        var end_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        end_box.append (duration_lbl);
        end_box.append (settings_button);

        name_label = new LabelOutline () {
            fontsize = 14,
            ellipsize = true,
            hexpand = true
        };
        var centerbox = new Gtk.CenterBox () {
            start_widget = start_box,
            center_widget = name_label,
            end_widget = end_box
        };

        peak_bar = new PeakBar() {
            hexpand = true,
            bar_height = 15,
            margin_start = 8,
            margin_end = 8
        };

        ctr_bottom = new TransparentHeader (Gtk.Orientation.VERTICAL, 0) {
            halign = Gtk.Align.FILL,
            valign = Gtk.Align.CENTER,
            hexpand = true
        };

        peak_bar.seek_requested.connect (seek_to_position);

        ctr_bottom.append (peak_bar);
        ctr_bottom.append (centerbox);

        control_revealer = new Gtk.Revealer () {
            transition_type = Gtk.RevealerTransitionType.CROSSFADE,
            transition_duration = 300,
            child = ctr_bottom,
            reveal_child = false,
            halign = Gtk.Align.FILL,
            valign = Gtk.Align.END
        };

        var headerbar = new Gtk.HeaderBar () {
            visible = false
        };
        set_titlebar (headerbar);
        child = overlay;

        var motion_controller = new Gtk.EventControllerMotion ();
        motion_controller.enter.connect (() => {
            controls_hovered = true;
            controls_show ();
        });
        motion_controller.leave.connect (() => {
            controls_hovered = false;
            schedule_hide_controls ();
        });
        control_revealer.add_controller (motion_controller);

        setup_gstreamer();
        video_with_crop = new VideoWithCrop (overlay, video_sink);

        bool initial_size_set = false;
        video_sink.resize_changed.connect((w, h) => {
            if (!initial_size_set) {
                set_default_size(w, h);
                initial_size_set = true;
            }
        });
        traverse_widget (this);
        apply_settings ();
        var osd_widget = new OsdOverlayWidget (this, video_sink);
        overlay.add_overlay (osd_widget);
        video_sink.osd_changed.connect (osd_widget.queue_draw);
        overlay.add_overlay (control_revealer);
    }

    private void traverse_widget (Gtk.Widget widget) {
        if (widget != null) {
            if (widget.get_data<Gtk.EventControllerKey> ("key-controller") == null) {
                var keypress = new Gtk.EventControllerKey ();
                widget.add_controller (keypress);
                keypress.key_pressed.connect (keyvalwd);
                widget.set_data ("key-controller", keypress);
            }
        }
        Gtk.Widget? child = widget.get_first_child ();
        while (child != null) {
            traverse_widget (child);
            child = child.get_next_sibling ();
        }
    }

    private bool keyvalwd (uint keyval, uint keycode, Gdk.ModifierType state) {
        double step = 0.05;
        double vstep = 0.01;
        if (match_keycode (Gdk.Key.f, keycode)) {
            if (is_fullscreen ()) {
                unfullscreen ();
            } else {
                fullscreen ();
            }
        } else if (match_keycode (Gdk.Key.q, keycode)) {
            close ();
        } else if (match_keycode (Gdk.Key.h, keycode)) {
            if (is_maximized ()) {
                unmaximize ();
            } else {
                maximize ();
            }
        } else if (match_keycode (Gdk.Key.plus, keycode) && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            video_sink.subtitle_overlay.offset_ms += 1000;
            video_sink.show_toast ("Subtitle offset: %+.1f s".printf (video_sink.subtitle_overlay.offset_ms / 1000.0));
        } else if (match_keycode (Gdk.Key.minus, keycode) && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            video_sink.subtitle_overlay.offset_ms -= 1000;
            video_sink.show_toast ("Subtitle offset: %+.1f s".printf (video_sink.subtitle_overlay.offset_ms / 1000.0));
        } else if (match_keycode (Gdk.Key.j, keycode)) {
            speed_up ();
        } else if (match_keycode (Gdk.Key.z, keycode)) {
            speed_down ();
        } else if (match_keycode (Gdk.Key.g, keycode)) {
            var s = PlayXSettings.get_default ();
            s.video_sink_mode = (s.video_sink_mode + 1) % 4;
            string[] mode_names = { "GPU Accelerator", "VA-API GPU Accelerator", "VA-API Memory Accelerator", "Software Accelerator" };
            video_sink.show_toast ("Video: %s (Restart required)".printf (mode_names[s.video_sink_mode]));
        } else if (match_keycode (Gdk.Key.l, keycode)) {
            video_sink.outline_mode = !video_sink.outline_mode;
            video_sink.show_toast ("Outline: %s".printf (!video_sink.outline_mode ? "ON" : "OFF"));
        } else if (match_keycode (Gdk.Key.k, keycode)) {
            cycle_channel_mode ();
        } else if (match_keycode (Gdk.Key.d, keycode)) {
            cycle_dolby ();
        } else if (match_keycode (Gdk.Key.n, keycode)) {
            cycle_noise ();
        } else if (match_keycode (Gdk.Key.w, keycode)) {
            toggle_eq ();
        } else if (match_keycode (Gdk.Key.x, keycode)) {
            toggle_backend ();
        } else if (match_keycode (Gdk.Key.m, keycode)) {
            audio_sink_bin.audio_sink.mute = !audio_sink_bin.audio_sink.mute;
            video_sink.show_toast ("%s".printf (audio_sink_bin.audio_sink.mute? _("Muted"):_("Sound")));
        } else if (match_keycode (Gdk.Key.v, keycode)) {
            video_sink.avisual_toggle = !video_sink.avisual_toggle;
            video_sink.show_toast ("Audio Visualizer: %s".printf (video_sink.avisual_toggle ? "ON" : "OFF"));
        } else if (match_keycode (Gdk.Key.b, keycode)) {
            black_blur = !black_blur;
            video_sink.show_toast ("Background Blur: %s".printf (black_blur ? "ON" : "OFF"));
        } else if (match_keycode (Gdk.Key.s, keycode)) {
            video_sink.subtitle_toggle = !video_sink.subtitle_toggle;
            video_sink.show_toast ("Subtitle: %s".printf (video_sink.subtitle_toggle ? "ON" : "OFF"));
        } else if (match_keycode (Gdk.Key.a, keycode)) {
            video_sink.auto_rotation = !video_sink.auto_rotation;
            video_sink.show_toast ("Auto Rotation: %s".printf (video_sink.auto_rotation ? "ON" : "OFF"));
        } else if (match_keycode (Gdk.Key.i, keycode)) {
            video_sink.toggle_media_info_osd ();
        } else if (match_keycode (Gdk.Key.c, keycode)) {
            video_with_crop.start_crop_mode ();
            video_sink.show_toast ("Start Crop Press ESC to Stop - R for Reset");
        } else if (match_keycode (Gdk.Key.e, keycode)) {
            current_preset = (current_preset + 1) % preset_names.length;
            audio_sink_bin.apply_preset ((Preset) current_preset);
            video_sink.show_toast ("EQ: %s".printf (preset_names[current_preset]));
        } else if (match_keycode (Gdk.Key.r, keycode)) {
            if (!video_with_crop.crop_active && video_sink.has_crop ()) {
                video_with_crop.reset_crop ();
                video_sink.show_toast ("Reset Crop");
            }
            var stprt = speed_steps[speed_index];
            if (stprt != 1.0) {
                speed_reset ();
                video_sink.show_toast ("Reset Speed");
            }
        } else if (match_keycode (Gdk.Key.p, keycode)) {
            video_sink.rotation = (video_sink.rotation + 90) % 360;
            video_sink.show_toast ("Rotate Right");
        } else if (match_keycode (Gdk.Key.o, keycode)) {
            video_sink.rotation = (video_sink.rotation + 270) % 360;
            video_sink.show_toast ("Rotate Left");
        } else if (match_keycode (Gdk.Key.@1, keycode)) {
            video_sink.brightness = (video_sink.brightness - step).clamp (-1.0, 1.0);
            video_sink.show_color_osd (video_sink.brightness, video_sink.contrast, video_sink.saturation, video_sink.hue, video_sink.gamma);
        } else if (match_keycode (Gdk.Key.@2, keycode)) {
            video_sink.brightness = (video_sink.brightness + step).clamp (-1.0, 1.0);
            video_sink.show_color_osd (video_sink.brightness, video_sink.contrast, video_sink.saturation, video_sink.hue, video_sink.gamma);
        } else if (match_keycode (Gdk.Key.@3, keycode)) {
            video_sink.contrast = (video_sink.contrast - step).clamp (-1.0, 1.0);
            video_sink.show_color_osd (video_sink.brightness, video_sink.contrast, video_sink.saturation, video_sink.hue, video_sink.gamma);
        } else if (match_keycode (Gdk.Key.@4, keycode)) {
            video_sink.contrast = (video_sink.contrast + step).clamp (-1.0, 1.0);
            video_sink.show_color_osd (video_sink.brightness, video_sink.contrast, video_sink.saturation, video_sink.hue, video_sink.gamma);
        } else if (match_keycode (Gdk.Key.@5, keycode)) {
            video_sink.saturation = (video_sink.saturation - step).clamp (-1.0, 1.0);
            video_sink.show_color_osd (video_sink.brightness, video_sink.contrast, video_sink.saturation, video_sink.hue, video_sink.gamma);
        } else if (match_keycode (Gdk.Key.@6, keycode)) {
            video_sink.saturation = (video_sink.saturation + step).clamp (-1.0, 1.0);
            video_sink.show_color_osd (video_sink.brightness, video_sink.contrast, video_sink.saturation, video_sink.hue, video_sink.gamma);
        } else if (match_keycode (Gdk.Key.@7, keycode)) {
            video_sink.hue = (video_sink.hue - step).clamp (-1.0, 1.0);
            video_sink.show_color_osd (video_sink.brightness, video_sink.contrast, video_sink.saturation, video_sink.hue, video_sink.gamma);
        } else if (match_keycode (Gdk.Key.@8, keycode)) {
            video_sink.hue = (video_sink.hue + step).clamp (-1.0, 1.0);
            video_sink.show_color_osd (video_sink.brightness, video_sink.contrast, video_sink.saturation, video_sink.hue, video_sink.gamma);
        } else if (match_keycode (Gdk.Key.@9, keycode)) {
            video_sink.gamma = (video_sink.gamma - step).clamp (-0.10, 2.0);
            video_sink.show_color_osd (video_sink.brightness, video_sink.contrast, video_sink.saturation, video_sink.hue, video_sink.gamma);
        } else if (match_keycode (Gdk.Key.@0, keycode)) {
            video_sink.gamma = (video_sink.gamma + step).clamp (-0.10, 2.0);
            video_sink.show_color_osd (video_sink.brightness, video_sink.contrast, video_sink.saturation, video_sink.hue, video_sink.gamma);
        } else if (match_keycode (Gdk.Key.plus, keycode)) {
            audio_sink_bin.volume = (audio_sink_bin.volume + vstep).clamp (0.0, 2.0);
            video_sink.volume_changed = (audio_sink_bin.volume / 2);
            video_sink.show_toast ("Volume: %d".printf ((int)(video_sink.volume_changed * 100)));
        } else if (match_keycode (Gdk.Key.minus, keycode)) {
            audio_sink_bin.volume = (audio_sink_bin.volume - vstep).clamp (0.0, 2.0);
            video_sink.volume_changed = (audio_sink_bin.volume / 2);
            video_sink.show_toast ("Volume: %d".printf ((int)(video_sink.volume_changed * 100)));
        } else if (match_keycode (Gdk.Key.t, keycode)) {
            int n_text = 0;
            pipeline.get ("n-text", out n_text);
            if (n_text > 0) {
                pipeline.get ("current-text", out current_subt);
                current_subt = (current_subt + 1) % n_text;
                pipeline.set ("current-text", current_subt);
                video_sink.subtitle_overlay.clear ();
                string info = get_subtitle_tracks ()[current_subt];
                video_sink.show_toast ("Sub [%d/%d]: %s".printf (current_subt + 1, n_text, info));
            } else {
                video_sink.show_toast ("No embedded subtitle");
            }
        } else if (match_keycode (Gdk.Key.y, keycode)) {
            int n_audio = 0;
            pipeline.get ("n-audio", out n_audio);
            if (n_audio > 1) {
                current_audio = (current_audio + 1) % n_audio;
                pipeline.set ("current-audio", current_audio);
                string info = get_audio_tracks()[current_audio];
                video_sink.show_toast ("Audio [%d/%d]: %s".printf (current_audio + 1, n_audio, info));
            } else {
                video_sink.show_toast ("No multiple audio track");
            }
        } else if (match_keycode (Gdk.Key.u, keycode)) {
            int n_video = 0;
            pipeline.get ("n-video", out n_video);
            if (n_video > 1) {
                current_video = (current_video + 1) % n_video;
                pipeline.set ("current-video", current_video);
                string info = get_video_tracks ()[current_video];
                video_sink.show_toast ("Video [%d/%d]: %s".printf (current_video + 1, n_video, info));
            } else {
                video_sink.show_toast ("No multiple video track");
            }
        }
        switch (keyval) {
            case Gdk.Key.Escape:
                if (video_with_crop.crop_active) {
                    video_with_crop.stop_crop_mode ();
                } else {
                    if (is_fullscreen ()) {
                        unfullscreen ();
                        return true;
                    }
                    if (is_maximized ()) {
                        unmaximize ();
                    }
                }
                break;
            case Gdk.Key.space:
                is_playing = !is_playing;
                break;
            case Gdk.Key.BackSpace:
                if (current_index > 0) {
                    nav_video (-1);
                }
                break;
            case Gdk.Key.Return:
                if (current_index < video_files.length - 1) {
                    nav_video (1);
                }
                break;
            case Gdk.Key.Left:
                key_seeker (pos_sec - 5.0);
                break;
            case Gdk.Key.Right:
                key_seeker (pos_sec + 5.0);
                break;
            case Gdk.Key.Up:
                key_seeker (pos_sec + 10.0);
                break;
            case Gdk.Key.Down:
                key_seeker (pos_sec - 10.0);
                break;
        }
        return true;
    }

    private void key_seeker (double position) {
        seek_to_position (position);
        video_sink.seek_position = position / duration;
        video_sink.show_toast ("%s / %s".printf (seconds_to_time (position < 0? 0.0 : position), duration_lbl.label));
    }

    private void move_window (Gtk.Window window, Gtk.Widget widget) {
        Gtk.GestureClick secges = new Gtk.GestureClick () {
            button = Gdk.BUTTON_SECONDARY
        };
        secges.pressed.connect((n_press, x, y)=> {
            is_playing = !is_playing;
        });
        Gtk.GestureClick click = new Gtk.GestureClick () {
            button = Gdk.BUTTON_PRIMARY
        };
        double start_x = 0;
        double start_y = 0;
        click.pressed.connect((n, x, y) => {
            if (n == 2) {
                if (is_fullscreen()) {
                    unfullscreen();
                } else {
                    fullscreen();
                }
            }
            start_x = x;
            start_y = y;
        });
        Gtk.GestureDrag drag = new Gtk.GestureDrag();
        drag.drag_begin.connect((x, y) => {
            start_x = x;
            start_y = y;
        });
        drag.drag_update.connect((offset_x, offset_y) => {
            Gdk.Surface surface = window.get_surface();
            if (surface != null) {
                Gdk.Toplevel toplevel = (Gdk.Toplevel) surface;
                toplevel.begin_move (Gdk.Display.get_default ().get_default_seat().get_pointer (), 1, (int)(start_x + offset_x), (int)(start_y + offset_y), Gdk.CURRENT_TIME);
            }
        });
        widget.add_controller(click);
        widget.add_controller(drag);
        widget.add_controller(secges);
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        var win_w = (float) get_width ();
        var win_h = (float) get_height ();
        snapshot.append_color (Gdk.RGBA () { alpha = 1f }, Graphene.Rect ().init (0, 0, win_w,  win_h));
        if (black_blur && background_source != null) {
            var src_w = (float) background_source.get_intrinsic_width ();
            var src_h = (float) background_source.get_intrinsic_height ();
            float scale = 1.0f;
            if (src_w > 0 && src_h > 0) {
                scale = float.max (win_w / src_w, win_h / src_h);
            }
            float draw_w = src_w * scale;
            float draw_h = src_h * scale;
            float offset_x = (win_w - draw_w) / 2.0f;
            float offset_y = (win_h - draw_h) / 2.0f;
            var clip_rect = Graphene.Rect ().init (0, 0, win_w, win_h);
            snapshot.push_clip (clip_rect);
            snapshot.save ();
            snapshot.translate (Graphene.Point ().init (offset_x, offset_y));
            snapshot.push_blur (15);
            background_source.snapshot (snapshot, draw_w, draw_h);
            snapshot.pop ();
            snapshot.restore ();
            snapshot.pop ();
        }
        base.snapshot (snapshot);
    }

    private void setup_gstreamer () {
        pipeline = Gst.ElementFactory.make("playbin", "playbin");
        video_sink = (PlayXVsink) GLib.Object.new(typeof(PlayXVsink));
        var video_bin = new Gst.Bin("video-sink-bin");
        audio_sink_bin = (PlayXaudio) GLib.Object.new(typeof(PlayXaudio));
        audio_sink_bin.backend = SinkBackend.ALSA;
        var dmabuf_upload = (DmaBufUpload) GLib.Object.new(typeof(DmaBufUpload));
        var cpuvideopassthrough = (CpuVideoPassthrough) GLib.Object.new(typeof(CpuVideoPassthrough));
        switch (PlayXSettings.get_default ().video_sink_mode) {
            case 1: {
                var va_postproc = Gst.ElementFactory.make ("vapostproc", "vapostproc");
                video_bin.add_many (va_postproc, dmabuf_upload, video_sink);
                va_postproc.link_many (dmabuf_upload, video_sink);
                video_bin.add_pad (new Gst.GhostPad("sink", va_postproc.get_static_pad("sink")));
                break;
            }
            case 2: {
                var vaapi_postproc = Gst.ElementFactory.make("vaapipostproc", "vaapipostproc");
                video_bin.add_many (vaapi_postproc, cpuvideopassthrough, video_sink);
                vaapi_postproc.link_many (cpuvideopassthrough, video_sink);
                video_bin.add_pad (new Gst.GhostPad("sink", vaapi_postproc.get_static_pad("sink")));
                break;
            }
            case 3: {
                video_bin.add_many (cpuvideopassthrough, video_sink);
                cpuvideopassthrough.link_many (video_sink);
                video_bin.add_pad (new Gst.GhostPad("sink", cpuvideopassthrough.get_static_pad("sink")));
                break;
            }
            default: {
                video_bin.add_many(dmabuf_upload, video_sink);
                dmabuf_upload.link_many (video_sink);
                video_bin.add_pad(new Gst.GhostPad("sink", dmabuf_upload.get_static_pad("sink")));
                break;
            }
        }
        pipeline.set ("video-sink", video_bin);
        pipeline.set ("audio-sink", audio_sink_bin);
        var subtitle_sink = (PlayXSsink) GLib.Object.new (typeof (PlayXSsink));
        subtitle_sink.text_received.connect ((text, pts_ms, dur_ms, mime) => {
            GLib.MainContext.default ().invoke (() => {
                if (mime.has_prefix ("application/x-ass") || mime.has_prefix ("application/x-ssa")) {
                    video_sink.subtitle_overlay.push_embedded_ass (text, pts_ms, dur_ms);
                } else {
                    video_sink.subtitle_overlay.push_embedded_raw (text, pts_ms, dur_ms);
                }
                return GLib.Source.REMOVE;
            });
        });
        pipeline.set ("text-sink", subtitle_sink);
        int flags;
        pipeline.get ("flags", out flags);
        flags |= 0x00000004;
        flags |= 0x00000040;
        pipeline.set ("flags", flags);
        var bus = pipeline.get_bus ();
        bus.add_signal_watch ();
        bus.message.connect (bus_callback);
        audio_sink_bin.level_updated.connect (video_sink.update_level);
        background_source = video_embed.paintable = video_sink;
    }

    private void bus_callback (Gst.Message msg) {
        if (msg.type == Gst.MessageType.ERROR) {
            stop_video ();
        } else if (msg.type == Gst.MessageType.EOS) {
            if (current_index < video_files.length - 1) {
                nav_video (1);
            } else {
                stop_video ();
                video_sink.stop_vis_timer ();
                uninhibit ();
                close ();
            }
        } else if (msg.type == Gst.MessageType.ELEMENT) {
            time_display ();
            audio_sink_bin.handle_bus_message (msg);
        } else if (msg.type == Gst.MessageType.BUFFERING) {
            int percent = 0;
            msg.parse_buffering (out percent);
            video_sink.seek_buffered = percent / 100.0;
        } else if (msg.type == Gst.MessageType.TAG) {
            Gst.TagList tag_list;
            msg.parse_tag (out tag_list);
            if (tag_list != null) {
                video_sink.cover_texture = paintable_from_tag (tag_list, Gst.Tag.ImageType.FRONT_COVER);
            }
        } else if (msg.type == Gst.MessageType.STATE_CHANGED) {
            Gst.State old, newstate, pending;
            msg.parse_state_changed (out old, out newstate, out pending);
            if (msg.src == pipeline && newstate == Gst.State.PLAYING && old == Gst.State.PAUSED) {
                string? cur_uri = null;
                pipeline.get ("current-uri", out cur_uri);
                if (cur_uri != null) {
                    collect_media_info_from_pipeline (cur_uri);
                }
            }
        }
    }

    private void extract_waveform_async() {
        if (pipeline == null) {
            peak_bar.generate_random_waveform ();
            return;
        }
        int64 duration_ns = 0;
        if (!pipeline.query_duration(Gst.Format.TIME, out duration_ns)) {
            peak_bar.generate_random_waveform ();
            return;
        }
        peak_bar.generate_random_waveform ();
    }

    private void seek_to_position(double position) {
        if (pipeline == null) {
            return;
        }
        time_display ();
        pipeline.set_state (Gst.State.PAUSED);
        if (position < 0) {
            position = 0;
        }
        if (position > duration) {
            position = duration;
        }
        int64 seek_pos = (int64)(position * Gst.SECOND);
        seeked = pipeline.seek_simple (Gst.Format.TIME, Gst.SeekFlags.FLUSH, seek_pos);
        if (last_press_time != 0) {
            GLib.Source.remove(last_press_time);
            last_press_time = 0;
        }
        if (last_press_time == 0) {
            last_press_time = GLib.Timeout.add (50, () => {
                time_display ();
                seeked = false;
                if (is_playing) {
                    pipeline.set_state (Gst.State.PLAYING);
                }
                last_press_time = 0;
                var stprt = speed_steps[speed_index];
                if (stprt != 1.0) {
                    setplayback_rate (stprt);
                }
                return false;
            });
        }
    }

    private void time_display () {
        int64 position_ns = 0;
        int64 duration_ns = 0;
        if (pipeline.query_position(Gst.Format.TIME, out position_ns) && pipeline.query_duration (Gst.Format.TIME, out duration_ns)) {
            if (duration_ns > 0) {
                pos_sec = position_ns / (double)Gst.SECOND;
                duration = duration_ns / (double)Gst.SECOND;
                video_sink.subtitle_position_ms = position_ns / Gst.MSECOND;
                peak_bar.set_position(pos_sec, duration);
                position_lbl.label = _("%s").printf (seconds_to_time (pos_sec));
                duration_lbl.label = _("%s").printf ( seconds_to_time (duration));
                ctr_bottom.queue_draw ();
            }
        }
    }

    private void cycle_dolby () {
        var cur = audio_sink_bin.audio_sink.dolby_mode;
        var next = (DolbyMode)(((int) cur + 1) % 5);
        audio_sink_bin.audio_sink.dolby_mode = next;
        video_sink.show_toast ("Dolby: %s".printf (dolby_label (next)));
    }

    private void cycle_noise () {
        var cur = audio_sink_bin.audio_sink.noise_cancellation;
        var next = (NoiseMode)(((int) cur + 1) % 5);
        audio_sink_bin.audio_sink.noise_cancellation = next;
        video_sink.show_toast ("Noise: %s".printf (noise_label (next)));
    }

    private void toggle_eq () {
        bool ena = !audio_sink_bin.audio_sink.equalizer_enabled;
        audio_sink_bin.audio_sink.equalizer_enabled = ena;
        video_sink.show_toast ("EQ: %s".printf (ena ? "ON" : "OFF"));
    }

    private void toggle_backend () {
        pipeline.set_state (Gst.State.READY);
        bool is_alsa = (audio_sink_bin.backend == SinkBackend.ALSA);
        audio_sink_bin.backend = is_alsa ? SinkBackend.PULSE : SinkBackend.ALSA;
        video_sink.show_toast ("Audio Backend: %s".printf (is_alsa ? "PulseAudio" : "ALSA"));
        pipeline.set_state (Gst.State.PLAYING);
    }

    private void cycle_channel_mode () {
        var cur = audio_sink_bin.channel_mode;
        var next = (ChannelMode)(((int) cur + 1) % 4);
        audio_sink_bin.channel_mode = next;
        video_sink.show_toast ("Chanel: %s".printf (channel_mode_label (next)));
    }

    private void play_video () {
        pipeline.set_state(Gst.State.PLAYING);
        is_playing = true;
    }
    
    private void pause_video () {
        pipeline.set_state(Gst.State.PAUSED);
        is_playing = false;
    }
    
    private void stop_video() {
        pipeline.set_state(Gst.State.NULL);
        is_playing = false;
    }

    private Gdk.Texture? paintable_from_buffer (Gst.Buffer buffer) {
        Gst.MapInfo map_info;
        if (!buffer.map (out map_info, Gst.MapFlags.READ)) {
            return null;
        }
        var bytes = new GLib.Bytes (map_info.data);
        buffer.unmap (map_info);
        try {
            return Gdk.Texture.from_bytes (bytes);
        } catch {
            return null;
        }
    }

    private Gdk.Texture? paintable_from_tag (Gst.TagList tag_list, Gst.Tag.ImageType type) {
        string? current_uri = null;
        pipeline.get ("current-uri", out current_uri);
        if (cached_cover != null && cached_cover_uri == current_uri) {
            return cached_cover;
        }
        var sample = get_cover_sample (tag_list, type);
        if (sample == null) {
            tag_list.get_sample (Gst.Tags.IMAGE, out sample);
        }
        if (sample == null) {
            return null;
        }
        var buffer = sample.get_buffer ();
        if (buffer == null) {
            return null;
        }
        var result = paintable_from_buffer (buffer);
        if (result != null) {
            cached_cover = result;
            cached_cover_uri = current_uri;
        }
        return result;
    }

    private async void on_open_clicked () throws Error {
        current_index = -1;
        video_files = {};
        vide_list.clear ();
        var filter = new Gtk.FileFilter ();
        filter.set_filter_name ("Audio Video");
        filter.add_mime_type("video/*");
        filter.add_mime_type("audio/*");
        var lstore = new GLib.ListStore (typeof (Gtk.FileFilter));
        lstore.append (filter);
        var filechooser = new Gtk.FileDialog () {
            title = _("Open Video"),
            accept_label = _("Open"),
            filters = lstore
        };
        var listmodel = yield filechooser.open_multiple (this, null);
        for (int i = 0; i < listmodel.get_n_items (); i++) {
            vide_list.add (((File) listmodel.get_item (i)).get_uri ());
        }
        video_files = vide_list.to_array ();
        nav_video (1);
    }

    public void files_uris (File[] files) {
        current_index = -1;
        video_files = {};
        vide_list.clear ();
        foreach (var item in files) {
            if (is_media_file (item.get_basename ())) {
                vide_list.add (item.get_uri ());
            }
        }
        video_files = vide_list.to_array ();
        nav_video (1);
    }

    public void load_uri_video (File path) {
        video_sink.subtitle_overlay.clear ();
        name_label.label = path.get_basename ();
        var subt = subtitle_for_path (path.get_path ());
        if (subt != null) {
            video_sink.subtitle_overlay.load_file (subt);
        }
        load_video (path.get_uri ());
        update_navigation_buttons ();
        extract_waveform_async ();
        video_sink.start_vis_timer ();
        speed_index = 5;
        playback_rate = 1.0;
    }

    public void load_video (string uri) {
        pipeline.set_state (Gst.State.READY);
        pipeline.get_state (null, null, Gst.CLOCK_TIME_NONE);
        pipeline.set ("uri", uri);
        pipeline.set_state (Gst.State.PLAYING);
        if (!is_playing) {
            is_playing = true;
        }
        video_sink.seek_position = 0.0;
        video_sink.subtitle_overlay.offset_ms = 0;
    }

    private void collect_media_info_from_pipeline (string uri) {
        var mi = MediaInfo ();
        var file = File.new_for_uri (uri);
        mi.file_name = file.get_basename ();
        try {
            var finfo = file.query_info ("standard::size", FileQueryInfoFlags.NONE);
            mi.file_size = (int64) finfo.get_size ();
        } catch {
            mi.file_size = 0;
        }
        int64 dur_ns = 0;
        if (pipeline.query_duration (Gst.Format.TIME, out dur_ns) && dur_ns > 0) {
            mi.duration_ms = dur_ns / Gst.SECOND;
        }
        int n_video = 0, n_audio = 0, n_text = 0;
        pipeline.get ("n-video", out n_video);
        pipeline.get ("n-audio", out n_audio);
        pipeline.get ("n-text", out n_text);
        var video_pad = video_sink.get_static_pad ("sink");
        if (video_pad != null) {
            var caps = video_pad.get_current_caps ();
            if (caps != null) {
                unowned Gst.Structure st = caps.get_structure (0);
                st.get_int ("width", out mi.video_width);
                st.get_int ("height", out mi.video_height);
                st.get_fraction ("framerate", out mi.video_fps_n, out mi.video_fps_d);
                mi.video_profile = st.get_string ("profile") ?? "";
                mi.video_level = st.get_string ("level") ?? "";
                mi.video_stream_fmt = st.get_string ("stream-format") ?? "";
                mi.video_chroma = st.get_string ("chroma-format") ?? "";
                mi.video_colorimetry = st.get_string ("colorimetry") ?? "";
                mi.video_format = st.get_string ("drm-format") != null? st.get_string ("drm-format")?? "" : st.get_string ("format");
            }
        }
        Gst.TagList tags = null;
        GLib.Signal.emit_by_name (pipeline, "get-video-tags", 0, out tags);
        if (tags != null) {
            tags.get_string (Gst.Tags.VIDEO_CODEC, out mi.video_codec);
            tags.get_uint (Gst.Tags.BITRATE, out mi.video_bitrate);
        }
        var audio_pad = audio_sink_bin.get_static_pad ("sink");
        if (audio_pad != null) {
            var caps = audio_pad.get_current_caps ();
            if (caps != null) {
                unowned Gst.Structure st = caps.get_structure (0);
                st.get_int ("rate", out mi.audio_sample_rate);
                st.get_int ("channels", out mi.audio_sample_rate);
                mi.audio_format = st.get_string ("format") ?? "";
                st.get_int ("mpegversion", out mi.audio_mpegversion);
            }
        }
        GLib.Signal.emit_by_name (pipeline, "get-audio-tags", 0, out tags);
        if (tags != null) {
            tags.get_string (Gst.Tags.AUDIO_CODEC, out mi.audio_codec);
            tags.get_uint (Gst.Tags.BITRATE, out mi.audio_bitrate);
            tags.get_string (Gst.Tags.TITLE, out mi.title);
            tags.get_string (Gst.Tags.ARTIST, out mi.artist);
            tags.get_string (Gst.Tags.ALBUM, out mi.album);
        }
        if (n_text > 0) {
            mi.subtitle_lang = "%s (%d track)".printf (get_subtitle_tracks ()[0], n_text);
        }
        if (n_video > 0) {
            mi.video_lang = "%s (%d track)".printf (get_video_tracks ()[current_video], n_video);
        }
        if (n_audio > 0) {
            mi.audio_lang = "%s (%d track)".printf (get_audio_tracks ()[current_audio], n_audio);
        }
        video_sink.show_media_info (mi);
    }

    public Gee.ArrayList<string> get_subtitle_tracks () {
        Gee.ArrayList<string> list_tags = new Gee.ArrayList<string> ();
        foreach (var tags in get_tags (pipeline, "n-text", "get-text-tags")) {
            list_tags.add (tags);
        }
        return list_tags;
    }

    public Gee.ArrayList<string> get_video_tracks () {
        Gee.ArrayList<string> list_tags = new Gee.ArrayList<string> ();
        foreach (var tags in get_tags (pipeline, "n-video", "get-video-tags")) {
            list_tags.add (tags);
        }
        return list_tags;
    }

    public Gee.ArrayList<string> get_audio_tracks () {
        Gee.ArrayList<string> list_tags = new Gee.ArrayList<string> ();
        foreach (var tags in get_tags (pipeline, "n-audio", "get-audio-tags")) {
            list_tags.add (tags);
        }
        return list_tags;
    }

    private void nav_video (int direction) {
        if (video_files.length == 0) {
            return;
        }
        current_index = (current_index + direction) % video_files.length;
        if (current_index < 0) {
            current_index = video_files.length - 1;
        }
        load_uri_video (File.new_for_uri (video_files[current_index]));
        title_lbl.label = _("%i / %i").printf (current_index + 1, video_files.length);
    }

    private void update_navigation_buttons () {
        prev_button.sensitive = current_index > 0;
        next_button.sensitive = current_index < video_files.length - 1;
    }

    private void setplayback_rate (double rate) {
        if (rate <= 0) {
            return;
        }
        playback_rate = rate;
        int64 pos_ns = 0;
        pipeline.query_position (Gst.Format.TIME, out pos_ns);
        pipeline.seek (rate, Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE, Gst.SeekType.SET, pos_ns, Gst.SeekType.NONE, -1);
    }

    private void speed_up () {
        if (speed_index < speed_steps.length - 1) {
            speed_index++;
        }
        setplayback_rate (speed_steps[speed_index]);
        video_sink.show_toast ("Speed: %.1fx".printf (speed_steps[speed_index]));
        spd_lbl.label = "%.1f".printf (speed_steps[speed_index]);
    }

    private void speed_down () {
        if (speed_index > 0) {
            speed_index--;
        }
        setplayback_rate (speed_steps[speed_index]);
        video_sink.show_toast ("Speed: %.1fx".printf (speed_steps[speed_index]));
        spd_lbl.label = "%.1f".printf (speed_steps[speed_index]);
    }

    private void speed_reset () {
        speed_index = 5;
        setplayback_rate (1.0);
        spd_lbl.label = "%.1f".printf (speed_steps[speed_index]);
    }

    private void controls_show () {
        if (hide_controls_timeout != 0) {
            Source.remove (hide_controls_timeout);
            hide_controls_timeout = 0;
        }
        if (!control_revealer.get_reveal_child ()) {
            control_revealer.set_reveal_child (true);
            video_embed.set_cursor (default_cursor);
        }
    }

    private void schedule_hide_controls () {
        if (hide_controls_timeout != 0) {
            Source.remove (hide_controls_timeout);
        }
        hide_controls_timeout = Timeout.add (1000, () => {
            if (!controls_hovered) {
                control_revealer.set_reveal_child (false);
                video_embed.set_cursor (blank_cursor);
            }
            hide_controls_timeout = 0;
            return false;
        });
    }

    private void header_controls () {
        if (hide_header_timeout != 0) {
            Source.remove (hide_header_timeout);
            hide_header_timeout = 0;
        }
        if (!header_revealer.get_reveal_child ()) {
            header_revealer.set_reveal_child (true);
            video_embed.set_cursor (default_cursor);
        }
    }

    private void schedule_hide_header () {
        if (hide_header_timeout != 0) {
            Source.remove (hide_header_timeout);
        }
        hide_header_timeout = Timeout.add (1000, () => {
            if (!head_hovered) {
                header_revealer.set_reveal_child (false);
                video_embed.set_cursor (blank_cursor);
            }
            hide_header_timeout = 0;
            return false;
        });
    }

    private void inhibit () {
        if (initbitor) {
            return;
        }
        initbitor = true;
        gtk_cookie = application.inhibit (this, Gtk.ApplicationInhibitFlags.IDLE | Gtk.ApplicationInhibitFlags.SUSPEND, "Video Playing");
    }

    public void uninhibit () {
        if (!initbitor) {
            return;
        }
        initbitor = false;
        if (gtk_cookie != 0) {
            application.uninhibit (gtk_cookie);
            gtk_cookie = 0;
        }
    }

    public override bool close_request () {
        save_settings ();
        uninhibit ();
        return base.close_request ();
    }

    private void apply_settings () {
        var s = PlayXSettings.get_default ();
        video_sink.brightness = s.brightness;
        video_sink.contrast = s.contrast;
        video_sink.saturation = s.saturation;
        video_sink.hue = s.hue;
        video_sink.gamma = s.gamma;
        current_preset = s.audio_preset.clamp (0, preset_names.length - 1);
        audio_sink_bin.apply_preset ((Preset) current_preset);
        audio_sink_bin.backend = (s.audio_backend == "pulse") ? SinkBackend.PULSE : SinkBackend.ALSA;
        audio_sink_bin.audio_sink.mute = s.mute;
        audio_sink_bin.volume = s.volume.clamp (0.0, 2.0);
        video_sink.volume_changed = audio_sink_bin.volume / 2.0;
        video_sink.auto_rotation = s.auto_rotation;
        black_blur = s.background_blur;
        video_sink.outline_mode = s.background_osd;
        video_sink.avisual_toggle = s.audio_visualizer;
        audio_sink_bin.audio_sink.equalizer_enabled = s.equalizer;
    }

    private void save_settings () {
        var s = PlayXSettings.get_default ();
        s.brightness = video_sink.brightness;
        s.contrast = video_sink.contrast;
        s.saturation = video_sink.saturation;
        s.hue = video_sink.hue;
        s.gamma = video_sink.gamma;
        s.audio_preset = current_preset;
        s.audio_backend = (audio_sink_bin.backend == SinkBackend.PULSE) ? "pulse" : "alsa";
        s.mute = audio_sink_bin.audio_sink.mute;
        s.volume = audio_sink_bin.volume;
        s.auto_rotation = video_sink.auto_rotation;
        s.background_blur = black_blur;
        s.background_osd = video_sink.outline_mode;
        s.audio_visualizer = video_sink.avisual_toggle;
        s.equalizer = audio_sink_bin.audio_sink.equalizer_enabled;
        s.save ();
    }
}