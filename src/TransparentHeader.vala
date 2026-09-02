public class TransparentHeader : Gtk.Box {
    public TransparentHeader (Gtk.Orientation orientation, int spacing) {
        Object (orientation: orientation, spacing: spacing, halign : Gtk.Align.FILL, valign: Gtk.Align.START);
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
            Graphene.Rect bounds;
            if (child.compute_bounds (this, out bounds)) {
                snapshot.save ();
                var point = Graphene.Point () { x = bounds.origin.x, y = bounds.origin.y };
                snapshot.translate (point);
                child.snapshot (snapshot);
                snapshot.restore ();
            } else {
                child.snapshot (snapshot);
            }
        }
    }
}