public class LabelOutline : Gtk.DrawingArea {
    private string _label = "";
    private bool _ellipsize = false;
    private int _fontsize = 12;

    public string label {
        get {
            return _label;
        }
        set {
            _label = value;
            update_size_request ();
            queue_draw ();
        }
    }

    public int fontsize {
        get {
            return _fontsize;
        }
        set {
            _fontsize = value;
            update_size_request ();
            queue_draw ();
        }
    }

    public bool ellipsize {
        get {
            return _ellipsize;
        }
        set {
            _ellipsize = value;
            update_size_request ();
            queue_draw ();
        }
    }

    construct {
        vexpand = false;
        hexpand = false;
        update_size_request ();
        set_draw_func ((Gtk.DrawingAreaDrawFunc) draw_outlined_text);
    }

    private void update_size_request () {
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, 1, 1);
        var cr = new Cairo.Context (surface);
        cr.select_font_face ("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
        cr.set_font_size (_fontsize);
        Cairo.FontExtents fe;
        cr.font_extents (out fe);
        double outline = double.max (_fontsize * 0.045, 1.5);
        int req_h = (int) Math.ceil (fe.ascent + fe.descent + outline * 2 + 2);
        set_content_height (req_h);
        if (_label == "") {
            set_content_width (_ellipsize ? 5 : _fontsize * 4);
            return;
        }
        if (_ellipsize) {
            set_content_width (5);
        } else {
            Cairo.TextExtents te;
            cr.text_extents (_label, out te);
            int req_w = int.max ((int) Math.ceil (te.width + outline * 2 + 4), 5);
            set_content_width (req_w);
        }
    }

    private string ellipsize_text (Cairo.Context cr, string text, double max_width) {
        Cairo.TextExtents te;
        cr.text_extents (text, out te);
        if (te.width <= max_width) {
            return text;
        }
        Cairo.TextExtents dot_te;
        cr.text_extents ("…", out dot_te);
        double budget = max_width - dot_te.width;
        if (budget <= 0) {
            return "…";
        }
        int char_count = (int) text.char_count ();
        while (char_count > 0) {
            char_count--;
            string s = text.substring (0, text.index_of_nth_char (char_count));
            cr.text_extents (s, out te);
            if (te.width <= budget) {
                return s + "…";
            }
        }
        return "…";
    }

    private void draw_outlined_text (Cairo.Context cr, int width, int height) {
        if (_label == "") {
            return;
        }
        double font_size = (double) _fontsize;
        cr.select_font_face ("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
        cr.set_font_size (font_size);
        double outline = double.max (font_size * 0.040, 1.5);
        double max_w = width - outline * 2 - 4;
        string display = _ellipsize ? ellipsize_text (cr, _label, max_w) : _label;
        Cairo.FontExtents fe;
        cr.font_extents (out fe);
        Cairo.TextExtents te;
        cr.text_extents (display, out te);
        double tx = (width - te.width) / 2.0 - te.x_bearing;
        double ty = (height - fe.ascent - fe.descent) / 2.0 + fe.ascent;
        double[] dx = { 0, 1, 1, 1, 0, -1, -1, -1 };
        double[] dy = { -1, -1, 0, 1, 1, 1, 0, -1 };
        cr.set_source_rgba (0.0, 0.0, 0.0, 0.80);
        for (int d = 0; d < 8; d++) {
            cr.move_to (tx + dx[d] * outline, ty + dy[d] * outline);
            cr.show_text (display);
        }
        cr.set_source_rgb (1.0, 1.0, 1.0);
        cr.move_to (tx, ty);
        cr.show_text (display);
    }
}