public class IconOutline : Gtk.DrawingArea {
    private string _icon_name = "";
    public string icon_name {
        get {
            return _icon_name;
        }
        set {
            _icon_name = value;
            update_size ();
            queue_draw ();
        }
    }

    private int _icon_size = 48;
    public int icon_size {
        get {
            return _icon_size;
        }
        set {
            _icon_size = value;
            update_size ();
            queue_draw ();
        }
    }

    private double _outline = 3.0;
    public double outline_width {
        get {
            return _outline;
        }
        set {
            _outline = value;
            update_size ();
            queue_draw ();
        }
    }

    private Gdk.RGBA _icon_color = { 1f, 1f, 1f, 1f };
    public Gdk.RGBA icon_color {
        get {
            return _icon_color;
        }
        set {
            _icon_color = value;
            queue_draw ();
        }
    }

    private Gdk.RGBA _outline_color = { 0f, 0f, 0f, 0.9f };
    public Gdk.RGBA outline_color {
        get {
            return _outline_color;
        }
        set {
            _outline_color = value;
            queue_draw ();
        }
    }

    construct {
        vexpand = false;
        hexpand = false;
        update_size ();
        set_draw_func ((Gtk.DrawingAreaDrawFunc) _draw);
    }

    private void update_size () {
        int pad = (int) (_outline * 2) + 4;
        set_content_width  (_icon_size + pad);
        set_content_height (_icon_size + pad);
    }

    private Cairo.ImageSurface make_colored_surface (Gdk.RGBA color) {
        var theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
        var paintbl = theme.lookup_icon (_icon_name, null, _icon_size, 1, Gtk.TextDirection.NONE, Gtk.IconLookupFlags.PRELOAD);
        var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, _icon_size, _icon_size);
        var c = new Cairo.Context (surf);
        var snap = new Gtk.Snapshot ();
        paintbl.snapshot (snap, _icon_size, _icon_size);
        snap.free_to_node ().draw (c);
        c.set_source_rgba (color.red, color.green, color.blue, color.alpha);
        c.set_operator (Cairo.Operator.IN);
        c.paint ();
        return surf;
    }

    private void _draw (Cairo.Context cr, int width, int height) {
        if (_icon_name == "") {
            return;
        }
        double ox = (width - _icon_size) / 2.0;
        double oy = (height - _icon_size) / 2.0;
        if (_outline > 0) {
            var ol_surf = make_colored_surface (_outline_color);
            double[] dx = {  0,  1,  1,  1,  0, -1, -1, -1 };
            double[] dy = { -1, -1,  0,  1,  1,  1,  0, -1 };
            cr.set_source_rgba (_outline_color.red, _outline_color.green, _outline_color.blue, _outline_color.alpha);
            for (int d = 0; d < 8; d++) {
                cr.mask_surface (ol_surf, ox + dx[d] * _outline, oy + dy[d] * _outline);
            }
        }
        var icon_surf = make_colored_surface (_icon_color);
        cr.set_source_surface (icon_surf, ox, oy);
        cr.paint ();
    }
}