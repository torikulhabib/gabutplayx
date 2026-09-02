public class OsdIconPaintable : GLib.Object, Gdk.Paintable {
    public OsdIconKind kind { get; construct; }
    public int size { get; construct; }

    public OsdIconPaintable (OsdIconKind kind, int size = 18) {
        GLib.Object (kind: kind, size: size);
    }

    public Gdk.PaintableFlags get_flags () {
        return (Gdk.PaintableFlags) 0;
    }

    public int get_intrinsic_width () {
        return size;
    }

    public int get_intrinsic_height () {
        return size;
    }

    public double get_intrinsic_aspect_ratio () {
        return 1.0;
    }

    public void snapshot (Gdk.Snapshot gdk_snap, double w, double h) {
        var snap = (Gtk.Snapshot) gdk_snap;
        var ctx = snap.append_cairo (Graphene.Rect ().init (0, 0, (float) w, (float) h));
        ctx.set_line_cap (Cairo.LineCap.ROUND);
        ctx.set_line_join (Cairo.LineJoin.ROUND);
        ctx.translate (w / 2.0, h / 2.0);
        double s = w / 36.0;

        ctx.set_source_rgba (1, 1, 1, 1);
        ctx.set_line_width (2.0 * s);

        switch (kind) {
            case BRIGHTNESS: _draw_brightness (ctx, s); break;
            case CONTRAST: _draw_contrast (ctx, s); break;
            case SATURATION: _draw_saturation (ctx, s); break;
            case HUE: _draw_hue (ctx, s); break;
            case GAMMA: _draw_gamma (ctx, s); break;
        }
    }

    private void _draw_brightness (Cairo.Context cr, double s) {
        double R = 11 * s;
        double ri = 4.5 * s;
        double r1 = 17 * s;
        double r2 = 21 * s;
        cr.arc (0, 0, R, 0, 2 * Math.PI);
        cr.stroke ();
        cr.arc (0, 0, ri, 0, 2 * Math.PI);
        cr.fill ();
        for (int i = 0; i < 8; i++) {
            double a = i * Math.PI / 4.0;
            cr.move_to (Math.cos (a) * r1, Math.sin (a) * r1);
            cr.line_to (Math.cos (a) * r2, Math.sin (a) * r2);
            cr.stroke ();
        }
    }

    private void _draw_contrast (Cairo.Context cr, double s) {
        double R = 18 * s;
        cr.arc (0, 0, R, -Math.PI / 2.0, Math.PI / 2.0);
        cr.close_path ();
        cr.fill ();
        cr.arc (0, 0, R, 0, 2 * Math.PI);
        cr.stroke ();
        cr.set_source_rgba (1, 1, 1, 1);
        cr.arc (-4 * s, -6 * s, 2.5 * s, 0, 2 * Math.PI);
        cr.fill ();
        cr.set_source_rgba (0, 0, 0, 1);
        cr.arc (4 * s, 6 * s, 2.5 * s, 0, 2 * Math.PI);
        cr.fill ();

        cr.set_source_rgba (1, 1, 1, 1);
    }

    private void _draw_saturation (Cairo.Context cr, double s) {
        cr.move_to (0, -20 * s);
        cr.curve_to ( 8 * s, -8 * s, 16 * s, 4 * s, 16 * s, 10 * s);
        cr.arc (0, 10 * s, 16 * s, 0, Math.PI);
        cr.curve_to (-16 * s, 4 * s, -8 * s, -8 * s, 0, -20 * s);
        cr.close_path ();
        cr.stroke ();
        double[] ys = { 6 * s, 10 * s, 14 * s };
        double[] xws = { 9 * s, 12 * s, 7 * s };
        double[] alps = { 0.3, 0.55, 0.85 };
        cr.set_line_width (2.8 * s);
        for (int i = 0; i < 3; i++) {
            cr.set_source_rgba (1, 1, 1, alps[i]);
            cr.move_to (-xws[i], ys[i]);
            cr.line_to ( xws[i], ys[i]);
            cr.stroke ();
        }
        cr.set_line_width (2.0 * s);
        cr.set_source_rgba (1, 1, 1, 1);
    }

    private void _draw_hue (Cairo.Context cr, double s) {
        double R = 18 * s;
        double lw = 5.0 * s;
        cr.set_line_width (lw);
        cr.set_source_rgba (1.0, 0.42, 0.42, 1);
        cr.arc (0, 0, R, -Math.PI / 2.0, Math.PI / 2.0 - Math.PI / 6.0);
        cr.stroke ();
        cr.set_source_rgba (0.42, 1.0, 0.62, 1);
        cr.arc (0, 0, R, Math.PI / 2.0 - Math.PI / 6.0, Math.PI * 7.0 / 6.0);
        cr.stroke ();
        cr.set_source_rgba (0.42, 0.72, 1.0, 1);
        cr.arc (0, 0, R, Math.PI * 7.0 / 6.0, Math.PI * 3.0 / 2.0);
        cr.stroke ();
        cr.set_line_width (1.5 * s);
        cr.set_source_rgba (1, 1, 1, 1);
        cr.arc (0, 0, 4 * s, 0, 2 * Math.PI);
        cr.stroke ();
        cr.move_to (0, -4 * s);
        cr.line_to (0, -9 * s);
        cr.stroke ();
    }

    private void _draw_gamma (Cairo.Context cr, double s) {
        double sz = 18 * s;
        cr.set_line_width (1.5 * s);
        cr.set_source_rgba (1, 1, 1, 0.25);
        cr.rectangle (-sz, -sz, sz * 2, sz * 2);
        cr.stroke ();
        cr.set_source_rgba (1, 1, 1, 0.2);
        double dash[] = { 3 * s, 3 * s };
        cr.set_dash (dash, 0.0);
        cr.move_to (-14 * s, 14 * s);
        cr.line_to ( 14 * s, -14 * s);
        cr.stroke ();
        double[] empty_dash = {};
        cr.set_dash (empty_dash, 0.0);
        cr.set_line_width (2.2 * s);
        cr.set_source_rgba (1, 1, 1, 1);
        cr.move_to (-13 * s, 13 * s);
        cr.curve_to (-13 * s, 4 * s, -4 * s, 4 * s, 0, 0);
        cr.curve_to ( 4 * s, -4 * s, 13 * s, -4 * s, 13 * s, -13 * s);
        cr.stroke ();
        cr.set_source_rgba (1, 1, 1, 1);
        cr.arc (-13 * s, 13 * s, 2.5 * s, 0, 2 * Math.PI);
        cr.fill ();
        cr.arc ( 13 * s, -13 * s, 2.5 * s, 0, 2 * Math.PI);
        cr.fill ();
    }
}