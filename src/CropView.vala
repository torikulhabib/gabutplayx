public class CropView : Gtk.DrawingArea {
    public signal void crop_confirmed (Gdk.Rectangle area);
    private Gdk.Rectangle drag_area;
    private Gdk.Rectangle area;
    private Gdk.Pixbuf _pixbuf;
    public Gdk.Pixbuf pixbuf {
        get {
            return _pixbuf;
        }
        set {
            _pixbuf = value;
            queue_draw ();
        }
    }
    private string current_operation = "default";
    private static string[] HANDLE_CURSORS = { "nw-resize", "n-resize", "ne-resize", "e-resize", "se-resize", "s-resize", "sw-resize", "w-resize" };
    public bool overlay_mode { get; set; default = false; }
    public bool quadratic_selection = false;
    public bool handles_visible = true;
    private double current_scale = 1.0;
    private int[,] pos = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } };
    private int temp_x = 0;
    private int temp_y = 0;
    private int offset_x = 0;
    private int offset_y = 0;
    private int drag_start_x;
    private int drag_start_y;
    private int r = 12;
    private bool mouse_button_down = false;

    construct {
        var click = new Gtk.GestureClick () {
            button = Gdk.BUTTON_PRIMARY
        };
        click.pressed.connect ((n_press, x, y) => {
            if (n_press == 2) {
                crop_confirmed (area);
                return;
            }
            mouse_button_down = true;
            drag_start_x = (int)x;
            drag_start_y = (int)y;
            drag_area = area;
            temp_x = (int)x;
            temp_y = (int)y;
        });
        click.released.connect ((n_press, x, y) => {
            current_operation = "default";
            mouse_button_down = false;
            apply_cursor ();
        });
        add_controller (click);
        var motion = new Gtk.EventControllerMotion ();
        motion.motion.connect ((x, y) => {
            if (!mouse_button_down) {
                handle_hover ((int) x, (int) y);
            } else {
                handle_drag ((int) x, (int) y);
                queue_draw ();
            }
        });
        add_controller (motion);
        set_draw_func (on_draw);
    }

    private void handle_hover (int x, int y) {
        bool determined = false;
        for (var i = 0; i < 8; i++) {
            if (in_quad (pos[i, 0] - r, pos[i, 1] - r, r * 2, r * 2, x, y)) {
                current_operation = HANDLE_CURSORS[i];
                determined = true;
                break;
            }
        }
        if (!determined) {
            if (in_quad ((int) Math.floor (area.x * current_scale), (int) Math.floor (area.y * current_scale), (int) Math.floor (area.width * current_scale), (int) Math.floor (area.height * current_scale), x - offset_x, y - offset_y)) {
                current_operation = "move";
            } else {
                current_operation = "default";
            }
        }
        apply_cursor ();
    }

    private void handle_drag (int ex, int ey) {
        double dx = (ex - drag_start_x) / current_scale;
        double dy = (ey - drag_start_y) / current_scale;
        switch (current_operation) {
            case "move": {
                area.x = (int)(drag_area.x + dx);
                area.y = (int)(drag_area.y + dy);
                break;
            }
            case "e-resize": {
                area.width  = (int)(drag_area.width + dx);
                int diff = area.width - drag_area.width;
                area.y = drag_area.y - diff / 2;
                area.height = drag_area.height + diff;
                break;
            }
            case "w-resize": {
                area.x = (int)(drag_area.x + dx);
                area.width = (int)(drag_area.width - dx);
                int diff = area.width - drag_area.width;
                area.y = drag_area.y - diff / 2;
                area.height = drag_area.height + diff;
                break;
            }
            case "s-resize": {
                area.height = (int)(drag_area.height + dy);
                int diff = area.height - drag_area.height;
                area.x = drag_area.x - diff / 2;
                area.width = drag_area.width + diff;
                break;
            }
            case "n-resize": {
                area.y = (int)(drag_area.y + dy);
                area.height = (int)(drag_area.height - dy);
                int diff = area.height - drag_area.height;
                area.x = drag_area.x - diff / 2;
                area.width = drag_area.width + diff;
                break;
            }
            case "se-resize": {
                area.width = (int)(drag_area.width + dx);
                area.height = (int)(drag_area.height + dy);
                break;
            }
            case "sw-resize": {
                area.x = (int)(drag_area.x + dx);
                area.width = (int)(drag_area.width - dx);
                area.height = (int)(drag_area.height + dy);
                break;
            }
            case "ne-resize": {
                area.width = (int)(drag_area.width + dx);
                area.y = (int)(drag_area.y + dy);
                area.height = (int)(drag_area.height - dy);
                break;
            }
            case "nw-resize": {
                area.x = (int)(drag_area.x + dx);
                area.width = (int)(drag_area.width - dx);
                area.y = (int)(drag_area.y + dy);
                area.height = (int)(drag_area.height - dy);
                break;
            }
        }
        if (area.width < 10) {
            area.width = 10;
        }
        if (area.height < 10) {
            area.height = 10;
        }
        if (area.x < 0) {
            area.x = 0;
        }
        if (area.y < 0) {
            area.y = 0;
        }
        if (area.x + area.width > _pixbuf.get_width ()) {
            area.width = _pixbuf.get_width () - area.x;
        }
        if (area.y + area.height > _pixbuf.get_height ()) {
            area.height = _pixbuf.get_height () - area.y;
        }
        queue_draw ();
    }

    private void on_draw (Gtk.DrawingArea da, Cairo.Context cr, int width, int height) {
        if (_pixbuf == null) {
            return;
        }
        int pb_w = _pixbuf.get_width ();
        int pb_h = _pixbuf.get_height ();
        double scale = 1.0;
        if (overlay_mode) {
            double sx = width / (double) pb_w;
            double sy = height / (double) pb_h;
            scale = double.min (sx, sy);
            offset_x = (int)((width - pb_w * scale) / 2.0);
            offset_y = (int)((height - pb_h * scale) / 2.0);
            cr.set_source_rgba (0.0, 0.0, 0.0, 0.55);
            cr.paint ();
        } else {
            int pw = pb_w, ph = pb_h;
            if (pw > width) {
                scale = width / (double) pw; ph = (int)(ph * scale);
                pw = width;
            }
            if (ph > height) {
                scale = height / (double) ph;
                pw = (int)(pw * (height / (double) ph));
                ph = height;
            }
            var scaled = _pixbuf.scale_simple (pw, ph, Gdk.InterpType.BILINEAR);
            offset_x = width / 2 - pw / 2;
            offset_y = height / 2 - ph / 2;
            Gdk.cairo_set_source_pixbuf (cr, scaled, offset_x, offset_y);
            cr.paint ();
            scale = pw / (double) _pixbuf.get_width ();
        }
        int x = offset_x + (int) Math.floor (area.x * scale);
        int y = offset_y + (int) Math.floor (area.y * scale);
        int w = (int) Math.floor (area.width * scale);
        int h = (int) Math.floor (area.height * scale);
        pos = {
            { x, y }, { x + w/2, y }, { x + w, y },
            { x + w, y + h/2 }, { x + w, y + h },
            { x + w/2, y + h },
            { x, y + h }, { x, y + h/2 }
        };
        if (overlay_mode) {
            cr.set_operator (Cairo.Operator.CLEAR);
            cr.rectangle (x, y, w, h);
            cr.fill ();
            cr.set_operator (Cairo.Operator.OVER);
            cr.set_source_rgba (1.0, 1.0, 1.0, 0.35);
            cr.set_line_width (0.5);
            for (int i = 1; i < 3; i++) {
                cr.move_to (x + w * i / 3.0, y);
                cr.line_to (x + w * i / 3.0, y + h);
                cr.move_to (x, y + h * i / 3.0);
                cr.line_to (x + w, y + h * i / 3.0);
            }
            cr.stroke ();
            cr.set_source_rgba (1.0, 1.0, 1.0, 0.75);
            cr.select_font_face ("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.set_font_size (12.0);
            cr.move_to (x + 4, y + h - 6);
            cr.show_text ("Double-click to apply");
        } else {
            cr.rectangle (x, y, w, h);
            cr.set_source_rgba (0.1, 0.1, 0.1, 0.2);
            cr.fill ();
        }
        cr.rectangle (x, y, w, h);
        cr.set_source_rgb (1.0, 1.0, 1.0);
        cr.set_line_width (1.5);
        cr.stroke ();
        if (handles_visible) {
            for (var i = 0; i < 8; i++) {
                cr.arc (pos[i, 0], pos[i, 1], r, 0.0, 2.0 * Math.PI);
                cr.set_source_rgba (1.0, 1.0, 1.0, 0.9);
                cr.fill ();
                cr.arc (pos[i, 0], pos[i, 1], r, 0.0, 2.0 * Math.PI);
                cr.set_source_rgba (0.3, 0.3, 0.3, 0.8);
                cr.set_line_width (1.5);
                cr.stroke ();
            }
        }
        current_scale = scale;
    }

    public CropView.from_pixbuf_with_size (Gdk.Pixbuf pixb, int x, int y, bool quadratic = false) {
        pixbuf = pixb;
        quadratic_selection = quadratic;
        if (pixbuf.get_width () > pixbuf.get_height ()) {
            area = { 5, 5, _pixbuf.get_height () / 2, _pixbuf.get_height () / 2 };
            double ts = (double) x / (double) pixbuf.get_width ();
            if (pixbuf.get_height () * ts < y) {
                y = (int)(pixbuf.get_height () * ts);
            }
        } else if (pixbuf.get_width () < pixbuf.get_height ()) {
            area = { 5, 5, _pixbuf.get_width () / 2, pixbuf.get_width () / 2 };
            double ts = (double) y / (double) pixbuf.get_height ();
            if (pixbuf.get_width () * ts < x) {
                x = (int)(pixbuf.get_width () * ts);
            }
        } else {
            area = { 5, 5, _pixbuf.get_width () / 2, pixbuf.get_height () / 2 };
        }
        set_size_request (x, y);
    }

    private bool in_quad (int qx, int qy, int qw, int qh, int x, int y) {
        return (x > qx) && (x < qx + qw) && (y > qy) && (y < qy + qh);
    }

    private void apply_cursor () {
        set_cursor_from_name (current_operation);
    }
}