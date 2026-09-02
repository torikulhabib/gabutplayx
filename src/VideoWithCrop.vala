public class VideoWithCrop : GLib.Object {
    public Gtk.Overlay widget { get; construct; }
    public PlayXVsink sink { get; construct; }
    private CropView? crop_view = null;
    public bool crop_active = false;

    public VideoWithCrop (Gtk.Overlay widg, PlayXVsink sink) {
        Object (widget: widg, sink: sink);
    }

    public void start_crop_mode () {
        if (crop_active || !sink.video_render) {
            return;
        }
        int vw = sink.display_width > 0 ? sink.display_width : 1280;
        int vh = sink.display_height > 0 ? sink.display_height : 720;
        var dummy = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, vw, vh);
        crop_view = new CropView.from_pixbuf_with_size (dummy, widget.get_width (), widget.get_height (), true) {
            overlay_mode = true,
            hexpand = true,
            vexpand = true
        };
        crop_view.crop_confirmed.connect ((area) => {
            sink.set_crop (area.x, area.y, area.width, area.height);
            stop_crop_mode ();
        });
        widget.add_overlay (crop_view);
        crop_view.show ();
        crop_active = true;
    }

    public void stop_crop_mode () {
        if (!crop_active || crop_view == null) {
            return;
        }
        widget.remove_overlay (crop_view);
        crop_view = null;
        crop_active = false;
    }

    public void reset_crop () {
        sink.reset_crop ();
    }
}