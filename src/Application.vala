public class PlayerXApp : Gtk.Application {

    public PlayerXApp () {
        Object (application_id: "com.github.gabutakut.gabutplayx", flags: ApplicationFlags.HANDLES_OPEN);
    }

    construct {
        Adw.StyleManager.get_default ().color_scheme = Adw.ColorScheme.FORCE_DARK;
    }

    protected override void activate () {
        var window = active_window as WindowPage;
        if (window == null) {
            window = new WindowPage (this);
        }
        window.present ();
    }

    protected override void open (File[] files, string hint) {
        var window = active_window as WindowPage;
        if (window == null) {
            window = new WindowPage (this);
        }
        if (files.length > 0) {
            window.files_uris (files);
        }
        window.present ();
    }

    public static int main (string[] args) {
        Gtk.init ();
        Gst.init (ref args);
        var app = new PlayerXApp ();
        return app.run (args);
    }
}
