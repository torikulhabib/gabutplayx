public class SubtitleEntry : GLib.Object {
    public int64 start_ms { get; set; default = 0; }
    public int64 end_ms { get; set; default = int64.MAX; }
    public Gee.ArrayList<SubtitleSpan> spans;
    internal string? cached_markup = null;
    internal int cached_pw = 0;
    internal int cached_ph = 0;
    internal bool cache_valid = false;

    public SubtitleEntry () {
        spans = new Gee.ArrayList<SubtitleSpan> ();
    }

    public bool is_empty () {
        return spans.is_empty;
    }

    public void invalidate_cache () {
        cache_valid = false;
        cached_markup = null;
    }
}