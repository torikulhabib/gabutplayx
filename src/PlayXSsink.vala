public class PlayXSsink : Gst.App.Sink {
    public signal void text_received (string text, int64 pts_ms, int64 dur_ms, string mime);

    construct {
        sync = true;
        emit_signals = true;
        max_buffers = 5;
        drop = true;
    }

    public override Gst.FlowReturn new_sample () {
        var sample = pull_sample ();
        if (sample == null) {
            return Gst.FlowReturn.OK;
        }
        var buf = sample.get_buffer ();
        if (buf == null) {
            return Gst.FlowReturn.OK;
        }
        string mime = "";
        var scaps = sample.get_caps ();
        if (scaps != null) {
            unowned Gst.Structure st = scaps.get_structure (0);
            mime = st.get_name ();
        }
        Gst.MapInfo map;
        if (!buf.map (out map, Gst.MapFlags.READ)) {
            return Gst.FlowReturn.OK;
        }
        string text = ((string) map.data).substring (0, (int) map.size);
        buf.unmap (map);
        if (text.strip () == "") {
            return Gst.FlowReturn.OK;
        }
        int64 pts_ms = (buf.pts != Gst.CLOCK_TIME_NONE) ? (int64)(buf.pts / Gst.MSECOND) : 0;
        int64 dur_ms = (buf.duration != Gst.CLOCK_TIME_NONE) ? (int64)(buf.duration / Gst.MSECOND) : 3000;
        text_received (text, pts_ms, dur_ms, mime);
        return Gst.FlowReturn.OK;
    }
}