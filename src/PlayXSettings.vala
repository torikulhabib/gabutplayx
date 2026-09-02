public class PlayXSettings : Object {
    private static string config_path () {
        return Path.build_filename (Environment.get_user_config_dir (), "playx", "settings.json");
    }
    public double brightness { get; set; default = 0.0; }
    public double contrast { get; set; default = 0.0; }
    public double saturation { get; set; default = 0.0; }
    public double hue { get; set; default = 0.0; }
    public double gamma { get; set; default = 1.0; }
    public double volume { get; set; default = 1.0; }
    public string audio_backend = "alsa";
    public int video_sink_mode { get; set; default = 0; }
    public int audio_preset { get; set; default = 0; }
    public bool auto_rotation { get; set; default = false; }
    public bool background_blur { get; set; default = true; }
    public bool background_osd { get; set; default = true; }
    public bool audio_visualizer { get; set; default = false; }
    public bool mute { get; set; default = false; }
    public bool equalizer { get; set; default = false; }

    private static PlayXSettings? _instance = null;
    public static PlayXSettings get_default () {
        if (_instance == null) {
            _instance = new PlayXSettings ();
            _instance.load ();
        }
        return _instance;
    }

    public void save () {
        var dir = Path.build_filename (Environment.get_user_config_dir (), "playx");
        DirUtils.create_with_parents (dir, 0755);
        var cb_obj = new Json.Object ();
        cb_obj.set_double_member ("brightness", brightness);
        cb_obj.set_double_member ("contrast", contrast);
        cb_obj.set_double_member ("saturation", saturation);
        cb_obj.set_double_member ("hue", hue);
        cb_obj.set_double_member ("gamma", gamma);

        var au_obj = new Json.Object ();
        au_obj.set_int_member ("preset", audio_preset);
        au_obj.set_string_member ("backend", audio_backend);
        au_obj.set_boolean_member("mute", mute);
        au_obj.set_double_member ("volume", volume);
        au_obj.set_boolean_member("equalizer", equalizer);

        var vi_obj = new Json.Object ();
        vi_obj.set_int_member ("sink_mode", video_sink_mode);
        vi_obj.set_boolean_member ("auto_rotation", auto_rotation);
        vi_obj.set_boolean_member ("background_blur", background_blur);
        vi_obj.set_boolean_member ("background_osd", background_osd);
        vi_obj.set_boolean_member ("audio_visualizer", audio_visualizer);

        var root_obj = new Json.Object ();
        root_obj.set_object_member ("color_balance", cb_obj);
        root_obj.set_object_member ("audio", au_obj);
        root_obj.set_object_member ("video", vi_obj);
        var root_node = new Json.Node (Json.NodeType.OBJECT);
        root_node.set_object (root_obj);
        var generator = new Json.Generator ();
        generator.set_root (root_node);
        generator.pretty = true;
        try {
            generator.to_file (config_path ());
        } catch {}
    }

    public void load () {
        var path = config_path ();
        if (!FileUtils.test (path, FileTest.EXISTS)) {
            return;
        }
        try {
            var parser = new Json.Parser ();
            parser.load_from_file (path);
            var root = parser.get_root ().get_object ();
            var cb = root.get_object_member ("color_balance");
            if (cb != null) {
                brightness = cb.get_double_member_with_default ("brightness", 0.0);
                contrast = cb.get_double_member_with_default ("contrast", 0.0);
                saturation = cb.get_double_member_with_default ("saturation", 0.0);
                hue = cb.get_double_member_with_default ("hue", 0.0);
                gamma = cb.get_double_member_with_default ("gamma", 0.0);
            }
            var au = root.get_object_member ("audio");
            if (au != null) {
                audio_preset  = (int) au.get_int_member_with_default ("preset",  0);
                audio_backend = au.get_string_member_with_default ("backend", "alsa");
                mute = au.get_boolean_member_with_default ("mute", false);
                volume = au.get_double_member_with_default ("volume",  1.0);
                equalizer = au.get_boolean_member_with_default ("equalizer", true);
            }
            var vi = root.get_object_member ("video");
            if (vi != null) {
                video_sink_mode = (int) vi.get_int_member_with_default ("sink_mode", 0);
                auto_rotation = vi.get_boolean_member_with_default ("auto_rotation", false);
                background_blur = vi.get_boolean_member_with_default ("background_blur", true);
                background_osd = vi.get_boolean_member_with_default ("background_osd", false);
                audio_visualizer = vi.get_boolean_member_with_default ("audio_visualizer", false);
            }
        } catch {}
    }
}