public class OsdOverlayWidget : Gtk.Widget {
    public PlayXVsink sink { get; construct; }
    public WindowPage wpage { get; construct; }

    public OsdOverlayWidget (WindowPage page, PlayXVsink sin) {
        Object (wpage: page, sink: sin);
    }

    construct {
        can_target = false;
        hexpand = true;
        vexpand = true;
    }

    public override void snapshot (Gtk.Snapshot snap) {
        double w = get_width ();
        double h = get_height ();
        sink.render_seeker_osd (snap, w, h);
        sink.render_color_osd (snap, w, h);
        sink.render_toast (snap, w, h);
        sink.render_media_info_osd (snap, w, h);
        if (sink.subtitle_toggle && !wpage.seeked) {
            sink.subtitle_overlay.render (snap, w, h, sink.subtitle_position_ms, sink.outline_mode);
        }
        if (!sink.video_render && sink.avisual_toggle && sink.cover_texture == null) {
            sink.render_audio_visualizer (snap, w, h);
        }
    }
}