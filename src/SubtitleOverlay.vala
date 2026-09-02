public class SubtitleOverlay : Object {
    private Gee.ArrayList<SubtitleEntry> entries;
    private Pango.FontMap? font_map = null;
    private Pango.Context? pango_ctx = null;
    private Pango.Layout? layout = null;
    private Pango.Layout? outline_layout = null;
    private Pango.FontDescription? font_desc = null;
    private SubtitleEntry? last_entry = null;
    public string font_family = "Sans";
    public float bg_alpha { get; set; default = 0.55f; }
    public float margin_bottom { get; set; default = 28f; }
    public int64 offset_ms { get; set; default = 0; }
    public int font_size_pt { get; set; default = 18; }
    private string last_font_family = "";
    private string? last_markup = null;
    private int current_index = -1;
    private int last_layout_width = 0;
    private int last_font_height = 0;
    private int last_font_size = 0;

    private bool _visible = true;
    public bool visible {
        get {
            return _visible;
        }
        set {
            _visible = value;
        }
    }

    public int entry_count {
        get {
            return entries.size;
        }
    }

    public SubtitleOverlay () {
        entries = new Gee.ArrayList<SubtitleEntry> ();
    }

    private void ensure_pango () {
        if (font_map == null) {
            font_map = Pango.CairoFontMap.@new ();
            pango_ctx = font_map.create_context ();
            layout = new Pango.Layout (pango_ctx);
            font_desc = new Pango.FontDescription ();
        }
        if (last_font_family != font_family || last_font_size != font_size_pt) {
            font_desc.set_family (font_family);
            font_desc.set_weight (Pango.Weight.SEMIBOLD);
            font_desc.set_size (font_size_pt * Pango.SCALE);
            layout.set_font_description (font_desc);
            last_font_family = font_family;
            last_font_size = font_size_pt;
            foreach (var e in entries) {
                e.invalidate_cache ();
            }
        }
    }

    public bool load_file (string path) {
        entries.clear ();
        current_index = -1;
        string lower = path.down ();
        if (lower.has_suffix (".srt")) {
            return parse_srt (path);
        } else if (lower.has_suffix (".lrc")) {
            return parse_lrc (path);
        } else if (lower.has_suffix (".sm")) {
            return parse_sm (path);
        } else if (lower.has_suffix (".smi")) {
            return parse_sami (path);
        } else if (lower.has_suffix (".sub")) {
            return parse_sub (path);
        } else if (lower.has_suffix (".ssa")) {
            return parse_ssa (path);
        } else if (lower.has_suffix (".ass")) {
            return parse_ssa (path);
        } else if (lower.has_suffix (".asc")) {
            return parse_asc (path);
        } else {
            return false;
        }
    }

    public void clear () {
        entries.clear ();
        current_index = -1;
        last_entry = null;
    }

    public void seek (int64 position_ms) {
        current_index = -1;
        if (entries.is_empty) {
            return;
        }
        int lo = 0, hi = entries.size - 1;
        while (lo <= hi) {
            int mid = (lo + hi) / 2;
            if (entries[mid].start_ms <= position_ms) {
                current_index = mid; lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
    }

    private SubtitleEntry? get_current (int64 position_ms) {
        if (entries.is_empty) {
            return null;
        }
        if (current_index >= 0 && current_index < entries.size) {
            var e = entries[current_index];
            if (position_ms >= e.start_ms && position_ms < e.end_ms) {
                return e;
            }
        }
        while (current_index > 0 && entries[current_index].start_ms > position_ms) {
            current_index--;
            var e = entries[current_index];
            if (position_ms >= e.start_ms && position_ms < e.end_ms) {
                return e;
            }
        }
        while (current_index + 1 < entries.size && entries[current_index + 1].start_ms <= position_ms) {
            current_index++;
        }
        if (current_index < 0 || current_index >= entries.size) {
            return null;
        }
        var entry = entries[current_index];
        if (position_ms >= entry.start_ms && position_ms < entry.end_ms) {
            return entry;
        }
        return null;
    }

    public void render (Gtk.Snapshot snap, double width, double height, int64 position_ms, bool bg_sub) {
        if (!_visible) {
            return;
        }
        var entry = get_current (position_ms + offset_ms);
        if (entry == null || entry.is_empty ()) {
            return;
        }
        ensure_pango ();
        int font_pt = ((int)(height * 0.040)).clamp (2, 46);
        if (font_pt != last_font_height) {
            last_font_height = font_pt;
            font_desc.set_family (font_family);
            font_desc.set_size (font_pt * Pango.SCALE);
            font_desc.set_weight (Pango.Weight.BOLD);
            layout.set_font_description (font_desc);
            foreach (var e in entries) {
                e.cache_valid = false;
            }
        }
        int layout_width = (int)(width * Pango.SCALE);
        if (last_layout_width != layout_width) {
            layout.set_width (layout_width);
            layout.set_alignment (Pango.Alignment.CENTER);
            layout.set_wrap (Pango.WrapMode.WORD_CHAR);
            last_layout_width = layout_width;
            foreach (var e in entries) {
                e.cache_valid = false;
            }
        }
        string markup;
        int pw, ph;
        if (last_entry == entry && entry.cache_valid) {
            markup = entry.cached_markup;
            pw = entry.cached_pw;
            ph = entry.cached_ph;
        } else {
            markup = build_pango_markup (entry);
            if (markup.strip () == "") {
                return;
            }
            layout.set_markup (markup, -1);
            layout.get_pixel_size (out pw, out ph);
            if (pw <= 0 || ph <= 0) {
                return;
            }
            entry.cached_markup = markup;
            entry.cached_pw = pw;
            entry.cached_ph = ph;
            entry.cache_valid = true;
            last_entry = entry;
            last_markup = markup;
        }
        if (last_entry != entry || markup != last_markup) {
            layout.set_markup (markup, -1);
            last_entry = entry;
            last_markup = markup;
        }
        float tx = 0f;
        float ty = (float)(height - ph - margin_bottom);
        float dyn_outline = ((float)(height * 0.003)).clamp (1.0f, 3.0f);
        if (bg_sub) {
            float pad_x = 8f;
            float pad_y = 4f;
            float bg_x = (float)((width - pw) / 2.0 - pad_x);
            float bg_y = ty - pad_y;
            float bg_w = pw + pad_x * 2;
            float bg_h = ph + pad_y * 2;
            var bg = Gdk.RGBA () { red = 0f, green = 0f, blue = 0f, alpha = bg_alpha };
            snap.save ();
            snap.translate (Graphene.Point ().init (bg_x, bg_y));
            snap.append_color (bg, Graphene.Rect ().init (0f, 0f, bg_w, bg_h));
            snap.restore ();
        } else {
            if (outline_layout == null) {
                outline_layout = new Pango.Layout (pango_ctx);
            }
            outline_layout.set_font_description (layout.get_font_description ());
            outline_layout.set_width (layout.get_width ());
            outline_layout.set_alignment (layout.get_alignment ());
            outline_layout.set_wrap (layout.get_wrap ());
            var sb = new StringBuilder ();
            foreach (var span in last_entry.spans) {
                string escaped = GLib.Markup.escape_text (span.text);
                bool has_attr = span.bold || span.italic || span.underline;
                if (has_attr) {
                    sb.append ("<span");
                    if (span.bold) {
                        sb.append (" weight=\"bold\"");
                    }
                    if (span.italic) {
                        sb.append (" style=\"italic\"");
                    }
                    if (span.underline) {
                        sb.append (" underline=\"single\"");
                    }
                    sb.append (@">$escaped</span>");
                } else {
                    sb.append (escaped);
                }
            }
            outline_layout.set_markup (sb.str, -1);
            var outline_rgba = Gdk.RGBA () { red=0f, green=0f, blue=0f, alpha=0.85f };
            float[] dx = { 0f,  1f, 1f,  1f,  0f, -1f, -1f, -1f };
            float[] dy = {-1f, -1f, 0f,  1f,  1f,  1f,  0f, -1f };
            for (int i = 0; i < 8; i++) {
                snap.save ();
                snap.translate (Graphene.Point ().init (tx + dx[i] * dyn_outline, ty + dy[i] * dyn_outline));
                snap.append_layout (outline_layout, outline_rgba);
                snap.restore ();
            }
        }
        var white = Gdk.RGBA () { red = 1f, green = 1f, blue = 1f, alpha = 1f };
        snap.save ();
        snap.translate (Graphene.Point ().init (tx, ty));
        snap.append_layout (layout, white);
        snap.restore ();
    }

    private string build_pango_markup (SubtitleEntry entry) {
        var sb = new StringBuilder ();
        foreach (var span in entry.spans) {
            string escaped = GLib.Markup.escape_text (span.text);
            bool has_attr = span.color != null || span.bold || span.italic || span.underline;
            if (has_attr) {
                sb.append ("<span");
                if (span.color != null) {
                    sb.append (@" foreground=\"$(span.color)\"");
                }
                if (span.bold) {
                    sb.append (" weight=\"bold\"");
                }
                if (span.italic) {
                    sb.append (" style=\"italic\"");
                }
                if (span.underline) {
                    sb.append (" underline=\"single\"");
                }
                sb.append (@">$escaped</span>");
            } else {
                sb.append (escaped);
            }
        }
        return sb.str;
    }

    private bool parse_srt (string path) {
        string? raw = load_text_file (path);
        if (raw == null) {
            return false;
        }
        raw = raw.replace ("\r\n", "\n").replace ("\r", "\n");
        if (raw.has_prefix ("\xef\xbb\xbf")) {
            raw = raw[3:];
        }
        string[] blocks = raw.split ("\n\n");
        foreach (string block in blocks) {
            string[] lines = block.strip ().split ("\n");
            if (lines.length < 2) {
                continue;
            }
            int ts_line = -1;
            for (int i = 0; i < lines.length; i++) {
                if ("-->" in lines[i]) {
                    ts_line = i;
                    break;
                }
            }
            if (ts_line < 0) {
                continue;
            }
            int64 start_ms, end_ms;
            if (!parse_srt_time_line (lines[ts_line], out start_ms, out end_ms)) {
                continue;
            }
            var sb = new StringBuilder ();
            for (int i = ts_line + 1; i < lines.length; i++) {
                if (i > ts_line + 1) {
                    sb.append ("\n");
                }
                sb.append (lines[i]);
            }
            var entry = new SubtitleEntry () {
                start_ms = start_ms,
                end_ms = end_ms
            };
            parse_srt_tags (sb.str, entry);
            if (!entry.is_empty ()) {
                entries.add (entry);
            }
        }
        entries.sort ((a, b) => (int64)(a.start_ms - b.start_ms) > 0 ? 1 : -1);
        return !entries.is_empty;
    }

    private bool parse_srt_time_line (string line, out int64 start_ms, out int64 end_ms) {
        start_ms = end_ms = 0;
        string[] parts = line.split ("-->");
        if (parts.length < 2) {
            return false;
        }
        start_ms = srt_ts_to_ms (parts[0].strip ());
        end_ms = srt_ts_to_ms (parts[1].strip ());
        return start_ms >= 0 && end_ms > 0;
    }

    private void parse_srt_tags (string text, SubtitleEntry entry) {
        string? cur_color = null;
        bool cur_bold = false;
        bool cur_italic = false;
        bool cur_under = false;
        var color_stack = new Gee.ArrayQueue<string?> ();
        var bold_stack = new Gee.ArrayQueue<bool> ();
        var ital_stack = new Gee.ArrayQueue<bool> ();
        var under_stack = new Gee.ArrayQueue<bool> ();
        int pos = 0;
        int len = text.length;
        while (pos < len) {
            int tag_start = text.index_of ("<", pos);
            if (tag_start < 0) {
                append_span (entry, text[pos:], cur_color, cur_bold, cur_italic, cur_under);
                break;
            }
            if (tag_start > pos) {
                append_span (entry, text[pos:tag_start], cur_color, cur_bold, cur_italic, cur_under);
            }
            int tag_end = text.index_of (">", tag_start);
            if (tag_end < 0) {
                append_span (entry, text[tag_start:], cur_color, cur_bold, cur_italic, cur_under);
                break;
            }
            string tag = text[tag_start + 1 : tag_end].strip ().down ();
            pos = tag_end + 1;
            if (tag.has_prefix ("font")) {
                color_stack.offer_head (cur_color);
                cur_color = extract_html_attr (tag, "color");
            } else if (tag == "/font") {
                cur_color = color_stack.is_empty ? null : color_stack.poll_head ();
            } else if (tag == "b") {
                bold_stack.offer_head (cur_bold); cur_bold = true;
            } else if (tag == "/b") {
                cur_bold = bold_stack.is_empty ? false : bold_stack.poll_head ();
            } else if (tag == "i") {
                ital_stack.offer_head (cur_italic); cur_italic = true;
            } else if (tag == "/i") {
                cur_italic = ital_stack.is_empty ? false : ital_stack.poll_head ();
            } else if (tag == "u") {
                under_stack.offer_head (cur_under); cur_under = true;
            } else if (tag == "/u") {
                cur_under = under_stack.is_empty ? false : under_stack.poll_head ();
            }
        }
    }

    private string? extract_html_attr (string tag, string attr_name) {
        string needle = attr_name + "=";
        int idx = tag.index_of (needle);
        if (idx < 0) {
            return null;
        }
        int start = idx + needle.length;
        if (start >= tag.length) return null;
        char quote = tag[start];
        if (quote != '"' && quote != '\'') {
            int end = start;
            while (end < tag.length && tag[end] != ' ' && tag[end] != '>') end++;
            return tag[start:end];
        }
        start++;
        int end = tag.index_of (quote.to_string (), start);
        if (end < 0) {
            return null;
        }
        return tag[start:end];
    }

    private void append_span (SubtitleEntry entry, string text, string? color, bool bold, bool italic, bool underline) {
        if (text == "" || text.length == 0) {
            return;
        }
        var s = new SubtitleSpan () {
            text = text,
            color = color,
            bold = bold,
            italic = italic,
            underline = underline
        };
        entry.spans.add (s);
    }

    private static string normalize_newlines (string s) {
        var sb = new StringBuilder.sized (s.length);
        int i = 0;
        unowned uint8[] data = s.data;
        while (i < data.length) {
            if (data[i] == '\r') {
                sb.append_c ('\n');
                if (i + 1 < data.length && data[i + 1] == '\n') {
                    i++;
                }
            } else {
                sb.append_c ((char) data[i]);
            }
            i++;
        }
        return sb.str;
    }

    private static string strip_bom (string s) {
        unowned uint8[] d = s.data;
        if (d.length >= 3 && d[0] == 0xEF && d[1] == 0xBB && d[2] == 0xBF) {
            return s[3:];
        }
        if (d.length >= 2 && d[0] == 0xFF && d[1] == 0xFE) {
            return s[2:];
        }
        return s;
    }

    private static string ensure_utf8 (string s) {
        unowned uint8[] d = s.data;
        if (d.length >= 2 && ((d[0] == 0xFF && d[1] == 0xFE) || (d[0] == 0xFE && d[1] == 0xFF))) {
            try {
                return GLib.convert (s, s.length, "UTF-8", "UTF-16");
            } catch (ConvertError e) {
                warning ("ensure_utf8: UTF-16 convert gagal: %s", e.message);
            }
        }
        if (s.validate ()) {
            return s;
        }
        try {
            return GLib.convert (s, s.length, "UTF-8", "WINDOWS-1252");
        } catch {
            try {
                return GLib.convert (s, s.length, "UTF-8", "ISO-8859-1");
            } catch {
                var sb = new StringBuilder.sized (s.length);
                int i = 0;
                while (i < d.length) {
                    int char_len = 1;
                    if (d[i] < 0x80) {
                        char_len = 1;
                    } else if ((d[i] & 0xE0) == 0xC0) {
                        char_len = 2;
                    } else if ((d[i] & 0xF0) == 0xE0) {
                        char_len = 3;
                    } else if ((d[i] & 0xF8) == 0xF0) {
                        char_len = 4;
                    } else {
                        i++;
                        continue;
                    }
                    if (i + char_len > d.length) {
                        break;
                    }
                    bool valid = true;
                    for (int j = 1; j < char_len; j++) {
                        if ((d[i + j] & 0xC0) != 0x80) {
                            valid = false;
                            break;
                        }
                    }
                    if (valid) {
                        for (int j = 0; j < char_len; j++) {
                            sb.append_c ((char) d[i + j]);
                        }
                        i += char_len;
                    } else {
                        i++;
                    }
                }
                return sb.str;
            }
        }
    }

    private static string? load_text_file (string path) {
        try {
            var file = File.new_for_path (path);
            uint8[] contents;
            file.load_contents (null, out contents, null);
            string raw;
            if (contents.length >= 2 && contents[0] == 0xFF && contents[1] == 0xFE) {
                raw = decode_utf16 (contents, true);
                if (raw == null) {
                    throw new GLib.IOError.FAILED ("");
                }
            } else if (contents.length >= 2 && contents[0] == 0xFE && contents[1] == 0xFF) {
                raw = decode_utf16 (contents, false);
                if (raw == null) {
                    throw new GLib.IOError.FAILED ("");
                }
            } else {
                raw = (string) contents;
            }
            raw = strip_bom (raw);
            raw = ensure_utf8 (raw);
            raw = strip_bom_utf8 (raw);
            raw = normalize_newlines (raw);
            return raw;
        } catch {
            return null;
        }
    }

    private static string? decode_utf16 (uint8[] data, bool little_endian) {
        var sb = new StringBuilder ();
        int i = 2;
        while (i + 1 < data.length) {
            uint16 code = little_endian ? (uint16) (data[i] | (data[i + 1] << 8)) : (uint16) ((data[i] << 8) | data[i + 1]);
            i += 2;
            if (code == 0) {
                break;
            }
            if (code < 0x80) {
                sb.append_c ((char) code);
            } else if (code < 0x800) {
                sb.append_c ((char) (0xC0 | (code >> 6)));
                sb.append_c ((char) (0x80 | (code & 0x3F)));
            } else {
                sb.append_c ((char) (0xE0 | (code >> 12)));
                sb.append_c ((char) (0x80 | ((code >> 6) & 0x3F)));
                sb.append_c ((char) (0x80 | (code & 0x3F)));
            }
        }
        return sb.str;
    }

    private static string strip_bom_utf8 (string s) {
        if (s.length >= 3 && s[0] == '\xef' && s[1] == '\xbb' && s[2] == '\xbf') {
            return s[3:];
        }
        return s;
    }

    private bool parse_lrc (string path) {
        string? raw = load_text_file (path);
        if (raw == null) {
            return false;
        }
        string[] lines = raw.split ("\n");
        raw = raw.replace ("\r\n", "\n").replace ("\r", "\n");
        if (raw.has_prefix ("\xef\xbb\xbf")) {
            raw = raw[3:];
        }
        var meta_tags = new Gee.HashSet<string> ();
        meta_tags.add ("ar");
        meta_tags.add ("ti");
        meta_tags.add ("al");
        meta_tags.add ("by");
        meta_tags.add ("offset");
        meta_tags.add ("re");
        meta_tags.add ("ve");
        meta_tags.add ("length");
        foreach (string line in lines) {
            string l = line.strip ();
            if (l == "" || !l.has_prefix ("[")) {
                continue;
            }
            int pos = 0;
            var timestamps = new Gee.ArrayList<int64?> ();
            while (pos < l.length && l[pos] == '[') {
                int close = l.index_of ("]", pos + 1);
                if (close < 0) {
                    break;
                }
                string inner = l[pos + 1 : close];
                pos = close + 1;
                if (":" in inner) {
                    string key = inner.split (":")[0].down ().strip ();
                    if (meta_tags.contains (key)) {
                        continue;
                    }
                }
                int64 ms = lrc_ts_to_ms (inner);
                if (ms >= 0) {
                    timestamps.add (ms);
                }
            }
            if (timestamps.is_empty) {
                continue;
            }
            string text = l[pos:].strip ();
            if (text == "") {
                continue;
            }
            foreach (int64 ts in timestamps) {
                var entry = new SubtitleEntry () {
                    start_ms = ts,
                    end_ms = int64.MAX
                };
                var span = new SubtitleSpan () {
                    text = text
                };
                entry.spans.add (span);
                entries.add (entry);
            }
        }
        entries.sort ((a, b) => (int64)(a.start_ms - b.start_ms) > 0 ? 1 : -1);
        for (int i = 0; i < entries.size - 1; i++) {
            int64 next_start = entries[i + 1].start_ms;
            entries[i].end_ms = int64.min (entries[i].start_ms + 3000, next_start + 100);
        }
        if (!entries.is_empty) {
            int last = entries.size - 1;
            entries[last].end_ms = entries[last].start_ms + 4000;
        }
        return !entries.is_empty;
    }

    private static int safe_int_parse (string? s) {
        if (s == null || s.length == 0) {
            return 0;
        }
        int start = 0;
        while (start < s.length && s[start] == ' ') {
            start++;
        }
        if (start >= s.length) {
            return 0;
        }
        return int.parse (s[start:]);
    }

    private static double safe_double_parse (string? s) {
        if (s == null || s.length == 0) {
            return 0.0;
        }
        int start = 0;
        while (start < s.length && s[start] == ' ') {
            start++;
        }
        if (start >= s.length) {
            return 0.0;
        }
        return double.parse (s[start:]);
    }

    private int64 lrc_ts_to_ms (string? t) {
        if (t == null || t.length == 0) {
            return -1;
        }
        string[] colon = t.split (":");
        int h = 0, m = 0, s = 0, ms = 0;
        if (colon.length >= 3) {
            h = safe_int_parse (colon[0]);
            m = safe_int_parse (colon[1]);
            string sec_part = colon[2] != null ? colon[2] : "0";
            string[] dot = sec_part.split (".");
            s  = safe_int_parse (dot[0]);
            if (dot.length >= 2 && dot[1] != null) {
                string frac = dot[1];
                if (frac.length == 2) {
                    ms = safe_int_parse (frac) * 10;
                } else if (frac.length >= 3) {
                    ms = safe_int_parse (frac[0:3]);
                }
            }

        } else if (colon.length == 2) {
            m = safe_int_parse (colon[0]);
            string sec_part = colon[1] != null ? colon[1] : "0";
            string[] dot = sec_part.split (".");
            s = safe_int_parse (dot[0]);
            if (dot.length >= 2 && dot[1] != null) {
                string frac = dot[1];
                if (frac.length == 2) {
                    ms = safe_int_parse (frac) * 10;
                } else if (frac.length >= 3) {
                    ms = safe_int_parse (frac[0:3]);
                }
            }
        } else {
            return -1;
        }
        if (h < 0 || m < 0 || s < 0) {
            return -1;
        }
        return (int64)((h * 3600 + m * 60 + s) * 1000 + ms);
    }

    private int64 srt_ts_to_ms (string? t) {
        if (t == null || t.length == 0) {
            return -1;
        }
        var sb = new StringBuilder.sized (t.length);
        for (int i = 0; i < t.length; i++) {
            sb.append_c (t[i] == ',' ? '.' : t[i]);
        }
        string norm = sb.str;
        string[] p = norm.split (":");
        if (p.length < 3) {
            return -1;
        }
        int h = safe_int_parse (p[0]);
        int mi = safe_int_parse (p[1]);
        double s = safe_double_parse (p[2]);

        if (h < 0 || mi < 0 || s < 0) {
            return -1;
        }
        return (int64)((h * 3600 + mi * 60) * 1000 + s * 1000.0 + 0.5);
    }

    private bool parse_sm (string path) {
        string? raw = load_text_file (path);
        if (raw == null) {
            return false;
        }
        raw = raw.replace ("\r\n", "\n").replace ("\r", "\n");
        string dir = GLib.Path.get_dirname (path);
        int idx = raw.index_of ("#LYRICSPATH:");
        if (idx >= 0) {
            int start = idx + 12;
            int end = raw.index_of (";", start);
            if (end > start) {
                string lrc_rel = raw[start:end].strip ();
                string lrc_abs = GLib.Path.is_absolute (lrc_rel)? lrc_rel : GLib.Path.build_filename (dir, lrc_rel);
                if (FileUtils.test (lrc_abs, FileTest.EXISTS)) {
                    return parse_lrc (lrc_abs);
                }
            }
        }
        string? title = null;
        int ti = raw.index_of ("#TITLE:");
        if (ti >= 0) {
            int te = raw.index_of (";", ti + 7);
            if (te > ti + 7) {
                title = raw[ti + 7 : te].strip ();
            }
        }
        string base_name = GLib.Path.get_basename (path);
        int dot_idx = base_name.last_index_of (".");
        if (dot_idx > 0) {
            base_name = base_name[0:dot_idx];
        }
        string[] try_exts = { ".lrc", ".srt" };
        string[] try_names = null;
        if (title != null) {
            try_names = { base_name, title };
        } else {
            try_names = { base_name };
        }
        foreach (string name in try_names) {
            foreach (string ext in try_exts) {
                string candidate = GLib.Path.build_filename (dir, name + ext);
                if (FileUtils.test (candidate, FileTest.EXISTS)) {
                    return load_file (candidate);
                }
            }
        }
        return false;
    }

    private bool parse_sub (string path) {
        string? raw = load_text_file (path);
        if (raw == null) {
            return false;
        }
        string[] lines = raw.split ("\n");
        bool is_microdvd = false;
        foreach (string line in lines) {
            string l = line.strip ();
            if (l == "") {
                continue;
            }
            is_microdvd = l.has_prefix ("{");
            break;
        }
        if (is_microdvd) {
            double fps = 25.0;
            foreach (string line in lines) {
                string l = line.strip ();
                if (l == "" || !l.has_prefix ("{")) {
                    continue;
                }
                int c1 = l.index_of ("}");
                if (c1 < 0) {
                    continue;
                }
                int c2 = l.index_of ("}", c1 + 1);
                if (c2 < 0) {
                    continue;
                }
                string sf = l[1 : c1];
                string ef = l[c1 + 2 : c2];
                string text = l[c2 + 1 :];
                if (sf == "0" && ef == "0") {
                    double cand = safe_double_parse (text.strip ());
                    if (cand > 0) {
                        fps = cand;
                    }
                    continue;
                }
                int64 start_ms = (int64)(safe_int_parse (sf) / fps * 1000.0 + 0.5);
                int64 end_ms = (int64)(safe_int_parse (ef) / fps * 1000.0 + 0.5);
                if (end_ms <= start_ms) {
                    continue;
                }
                var sb = new StringBuilder.sized (text.length);
                for (int i = 0; i < text.length; i++) {
                    sb.append_c (text[i] == '|' ? '\n' : text[i]);
                }
                var entry = new SubtitleEntry () {
                    start_ms = start_ms,
                    end_ms = end_ms
                };
                parse_srt_tags (sb.str, entry);
                if (!entry.is_empty ()) {
                    entries.add (entry);
                }
            }
        } else {
            int i = 0;
            while (i < lines.length) {
                string l = lines[i].strip ();
                i++;
                if (l == "" || l.has_prefix ("[")) {
                    continue;
                }
                int64 start_ms, end_ms;
                if (!parse_subviewer_time_line (l, out start_ms, out end_ms)) {
                    continue;
                }
                var sb = new StringBuilder ();
                while (i < lines.length && lines[i].strip () != "") {
                    if (sb.len > 0) {
                        sb.append_c ('\n');
                    }
                    string tl = lines[i].strip ();
                    int j = 0;
                    while (j < tl.length) {
                        if (j + 3 < tl.length && tl[j : j + 4].down () == "[br]") {
                            sb.append_c ('\n'); j += 4;
                        } else {
                            sb.append_c (tl[j]); j++;
                        }
                    }
                    i++;
                }
                if (sb.len == 0) {
                    continue;
                }
                var entry = new SubtitleEntry () {
                    start_ms = start_ms,
                    end_ms = end_ms
                };
                parse_srt_tags (sb.str, entry);
                if (!entry.is_empty ()) {
                    entries.add (entry);
                }
            }
        }
        entries.sort ((a, b) => a.start_ms > b.start_ms ? 1 : -1);
        return !entries.is_empty;
    }

    private bool parse_subviewer_time_line (string line, out int64 start_ms, out int64 end_ms) {
        start_ms = end_ms = 0;
        string[] parts = line.split (",");
        if (parts.length < 2) {
            return false;
        }
        int64 s = subviewer_ts_to_ms (parts[0].strip ());
        int64 e = subviewer_ts_to_ms (parts[1].strip ());
        if (s < 0 || e < 0) {
            return false;
        }
        start_ms = s; end_ms = e;
        return true;
    }

    private int64 subviewer_ts_to_ms (string? t) {
        if (t == null || t.length == 0) {
            return -1;
        }
        string[] p = t.split (":");
        if (p.length < 3) {
            return -1;
        }
        int h = safe_int_parse (p[0]);
        int m = safe_int_parse (p[1]);
        string[] sd = p[2].split (".");
        int s  = safe_int_parse (sd[0]);
        int cs = sd.length >= 2 ? safe_int_parse (sd[1]) : 0;
        if (h < 0 || m < 0 || s < 0) {
            return -1;
        }
        return (int64)((h * 3600 + m * 60 + s) * 1000 + cs * 10);
    }

    private bool parse_ssa (string path) {
        string? raw = load_text_file (path);
        if (raw == null) {
            return false;
        }
        string[] lines = raw.split ("\n");
        bool in_events = false;
        int col_start = -1, col_end = -1, col_text = -1;
        foreach (string line in lines) {
            string l = line.strip ();
            if (l.down () == "[events]") {
                in_events = true;
                continue;
            }
            if (in_events && l.has_prefix ("[") && l.down () != "[events]") {
                break;
            }
            if (!in_events) {
                continue;
            }
            if (l.down ().has_prefix ("format:")) {
                string[] cols = l[7:].strip ().split (",");
                for (int i = 0; i < cols.length; i++) {
                    string c = cols[i].strip ().down ();
                    if (c == "start") {
                        col_start = i;
                    } else if (c == "end") {
                        col_end = i;
                    } else if (c == "text") {
                        col_text = i;
                    }
                }
                continue;
            }
            if (!l.down ().has_prefix ("dialogue:")) {
                continue;
            }
            if (col_start < 0 || col_end < 0 || col_text < 0) {
                continue;
            }
            string data = l[9:].strip ();
            int max_col = int.max (int.max (col_start, col_end), col_text);
            string[] fields = ssa_split_fields (data, max_col + 1);
            if (fields.length <= col_text) {
                continue;
            }
            int64 start_ms = ssa_ts_to_ms (fields[col_start].strip ());
            int64 end_ms = ssa_ts_to_ms (fields[col_end].strip ());
            if (start_ms < 0 || end_ms <= start_ms) {
                continue;
            }
            string text = ssa_strip_tags (fields[col_text]);
            if (text.strip () == "") {
                continue;
            }
            var entry = new SubtitleEntry () {
                start_ms = start_ms,
                end_ms = end_ms
            };
            var span = new SubtitleSpan () {
                text = text
            };
            entry.spans.add (span);
            entries.add (entry);
        }
        entries.sort ((a, b) => a.start_ms > b.start_ms ? 1 : -1);
        return !entries.is_empty;
    }

    private string[] ssa_split_fields (string s, int max_fields) {
        var result = new Gee.ArrayList<string> ();
        int pos = 0;
        while (pos <= s.length) {
            if (result.size >= max_fields) {
                result.add (pos <= s.length ? s[pos:] : "");
                break;
            }
            int comma = s.index_of (",", pos);
            if (comma < 0) {
                result.add (s[pos:]); break;
            }
            result.add (s[pos : comma]);
            pos = comma + 1;
        }
        return result.to_array ();
    }

    private string ssa_strip_tags (string text) {
        var sb = new StringBuilder.sized (text.length);
        int i = 0;
        while (i < text.length) {
            if (text[i] == '{') {
                while (i < text.length && text[i] != '}') {
                    i++;
                }
                if (i < text.length) {
                    i++;
                }
            } else if (text[i] == '\\' && i + 1 < text.length) {
                char nx = text[i + 1];
                if (nx == 'N' || nx == 'n') {
                    sb.append_c ('\n');
                    i += 2;
                } else if (nx == 'h') {
                    sb.append_c (' '); 
                    i += 2;
                } else {
                    sb.append_c (text[i]);
                    i++;
                }
            } else {
                sb.append_c (text[i]); i++;
            }
        }
        return sb.str;
    }

    private int64 ssa_ts_to_ms (string? t) {
        if (t == null || t.length == 0) {
            return -1;
        }
        string[] p = t.split (":");
        if (p.length < 3) {
            return -1;
        }
        int h = safe_int_parse (p[0]);
        int m = safe_int_parse (p[1]);
        string[] sd = p[2].split (".");
        int s  = safe_int_parse (sd[0]);
        int cs = sd.length >= 2 ? safe_int_parse (sd[1]) : 0;
        if (h < 0 || m < 0 || s < 0) {
            return -1;
        }
        return (int64)((h * 3600 + m * 60 + s) * 1000 + cs * 10);
    }

    private bool parse_asc (string path) {
        string? raw = load_text_file (path);
        if (raw == null) {
            return false;
        }
        if ("-->" in raw) {
            return parse_srt_from_raw (raw);
        }
        string[] blocks = raw.split ("\n\n");
        int64 t = 0;
        int64 dur = 3000;
        int64 gap = 300;
        foreach (string block in blocks) {
            string b = block.strip ();
            if (b == "") {
                continue;
            }
            if (b.has_prefix ("//") || b.has_prefix ("#")) {
                continue;
            }
            var entry = new SubtitleEntry () {
                start_ms = t,
                end_ms = t + dur
            };
            t += dur + gap;
            var span = new SubtitleSpan () {
                text = b
            };
            entry.spans.add (span);
            entries.add (entry);
        }
        return !entries.is_empty;
    }

    private bool parse_srt_from_raw (string raw) {
        string[] blocks = raw.split ("\n\n");
        foreach (string block in blocks) {
            string[] lines = block.strip ().split ("\n");
            if (lines.length < 2) {
                continue;
            }
            int ts_line = -1;
            for (int i = 0; i < lines.length; i++) {
                if ("-->" in lines[i]) {
                    ts_line = i;
                    break;
                }
            }
            if (ts_line < 0) {
                continue;
            }
            int64 start_ms, end_ms;
            if (!parse_srt_time_line (lines[ts_line], out start_ms, out end_ms)) {
                continue;
            }
            var sb = new StringBuilder ();
            for (int i = ts_line + 1; i < lines.length; i++) {
                if (i > ts_line + 1) {
                    sb.append_c ('\n');
                }
                sb.append (lines[i]);
            }

            var entry = new SubtitleEntry () {
                start_ms = start_ms,
                end_ms = end_ms
            };
            parse_srt_tags (sb.str, entry);
            if (!entry.is_empty ()) {
                entries.add (entry);
            }
        }
        entries.sort ((a, b) => a.start_ms > b.start_ms ? 1 : -1);
        return !entries.is_empty;
    }

    private bool parse_sami (string path) {
        string? raw = load_text_file (path);
        if (raw == null) {
            return false;
        }
        string body = sami_extract_body (raw);
        if (body == "") {
            body = raw;
        }
        var starts = new Gee.ArrayList<int64?> ();
        var texts = new Gee.ArrayList<string> ();
        string bl = body.down ();
        int pos = 0;
        while (pos < body.length) {
            int sync_pos = bl.index_of ("<sync", pos);
            if (sync_pos < 0) {
                break;
            }
            int tag_end = bl.index_of (">", sync_pos);
            if (tag_end < 0) {
                break;
            }
            int64 ms = sami_extract_start (body[sync_pos : tag_end + 1]);
            pos = tag_end + 1;
            int next_sync = bl.index_of ("<sync", pos);
            int body_close = bl.index_of ("</body>", pos);
            int content_end;
            if (next_sync >= 0 && (body_close < 0 || next_sync < body_close)) {
                content_end = next_sync;
            } else if (body_close >= 0) {
                content_end = body_close;
            } else {
                content_end = body.length;
            }
            string content = body[pos : content_end];
            string text = sami_extract_p_text (content);
            starts.add (ms);
            texts.add (text);
            pos = content_end;
        }
        for (int i = 0; i < starts.size; i++) {
            string text = texts[i].strip ();
            if (text == "") {
                continue;
            }
            int64 end_ms = starts[i] + 10000;
            for (int j = i + 1; j < starts.size; j++) {
                if (starts[j] > starts[i]) {
                    end_ms = starts[j];
                    break;
                }
            }
            if (end_ms <= starts[i]) {
                continue;
            }
            var entry = new SubtitleEntry () {
                start_ms = starts[i],
                end_ms = end_ms
            };
            parse_srt_tags (text, entry);
            if (!entry.is_empty ()) {
                entries.add (entry);
            }
        }
        entries.sort ((a, b) => a.start_ms > b.start_ms ? 1 : -1);
        return !entries.is_empty;
    }

    private string sami_extract_body (string raw) {
        string rl = raw.down ();
        int bs = rl.index_of ("<body");
        if (bs < 0) {
            return raw;
        }
        int be = rl.index_of (">", bs);
        if (be < 0) {
            return raw;
        }
        int start = be + 1;
        while (start < raw.length && (raw[start] == '\n' || raw[start] == '\r' || raw[start] == ' ' || raw[start] == '\t')) {
            start++;
        }
        int end = rl.index_of ("</body>", start);
        if (end < 0) {
            return raw[start:];
        }
        return raw[start : end];
    }

    private string sami_extract_p_text (string content) {
        string cl = content.down ();
        int p = cl.index_of ("<p");
        int tag_end = p >= 0 ? cl.index_of (">", p) : -1;
        string html = (p >= 0 && tag_end > p) ? content[tag_end + 1:].strip () : content.strip ();
        string decoded = sami_decode_html (html).strip ();
        if (decoded == "") {
            return "";
        }
        return decoded;
    }

    private int64 sami_extract_start (string tag) {
        string tl = tag.down ();
        int idx = tl.index_of ("start=");
        if (idx < 0) {
            return 0;
        }
        int s = idx + 6;
        if (s < tl.length && (tl[s] == '"' || tl[s] == '\'')) {
            s++;
        }
        int e = s;
        while (e < tl.length && tl[e] >= '0' && tl[e] <= '9') {
            e++;
        }
        return (int64) safe_int_parse (tl[s : e]);
    }

    private string sami_decode_html (string html) {
        var sb = new StringBuilder.sized (html.length);
        int i = 0;
        while (i < html.length) {
            if (html[i] == '<') {
                int end = html.index_of (">", i + 1);
                if (end < 0) {
                    sb.append_c (html[i]);
                    i++;
                    continue;
                }
                string tag = html[i + 1 : end].strip ().down ();
                if (tag == "br" || tag == "br/" || tag.has_prefix ("br ")) {
                    sb.append_c ('\n');
                } else {
                    sb.append (html[i : end + 1]);
                }
                i = end + 1;
            } else if (html[i] == '&') {
                bool hit = false;
                int semi = html.index_of (";", i + 1);
                if (semi > i && semi - i <= 7) {
                    string ent = html[i : semi + 1].down ();
                    if (ent == "&nbsp;") {
                        hit = true;
                        i = semi + 1;
                    } else if (ent == "&amp;") {
                        sb.append_c ('&');
                        hit = true;
                        i = semi + 1;
                    } else if (ent == "&lt;") {
                        sb.append_c ('<');
                        hit = true;
                        i = semi + 1;
                    } else if (ent == "&gt;") {
                        sb.append_c ('>');
                        hit = true;
                        i = semi + 1;
                    } else if (ent == "&quot;") {
                        sb.append_c ('"');
                        hit = true;
                        i = semi + 1;
                    } else if (ent == "&apos;") {
                        sb.append_c ('\'');
                        hit = true;
                        i = semi + 1;
                    }
                }
                if (!hit && i + 5 <= html.length && html[i : i + 5].down () == "&nbsp") {
                    hit = true;
                    i += 5;
                }
                if (!hit) {
                    sb.append_c (html[i]);
                    i++;
                }
            } else {
                sb.append_c (html[i]); i++;
            }
        }
        return sb.str.strip ();
    }

    public void push_embedded_raw (string text, int64 pts_ms, int64 dur_ms) {
        if (text.strip () == "") {
            return;
        }
        int64 end_ms = (dur_ms > 0) ? pts_ms + dur_ms : pts_ms + 5000;
        if (!entries.is_empty) {
            var last = entries[entries.size - 1];
            if (last.start_ms == pts_ms) {
                return;
            }
        }
        var entry = new SubtitleEntry () {
            start_ms = pts_ms,
            end_ms = end_ms
        };
        string clean = strip_embedded_tags (text);
        if (clean.strip () == "") {
            return;
        }
        parse_srt_tags (clean, entry);
        if (!entry.is_empty ()) {
            entries.add (entry);
            entries.sort ((a, b) => a.start_ms > b.start_ms ? 1 : -1);
        }
    }

    public void push_embedded_ass (string text, int64 pts_ms, int64 dur_ms) {
        string stripped = ssa_strip_tags (text);
        push_embedded_raw (stripped, pts_ms, dur_ms);
    }

    private string strip_embedded_tags (string input) {
        var sb = new StringBuilder ();
        int i = 0;
        while (i < input.length) {
            if (input[i] == '{') {
                while (i < input.length && input[i] != '}') i++;
                if (i < input.length) {
                    i++;
                }
            } else if (input[i] == '\\' && i + 1 < input.length) {
                char nx = input[i + 1];
                if (nx == 'N' || nx == 'n') {
                    sb.append_c ('\n'); i += 2;
                } else if (nx == 'h') {
                    sb.append_c (' '); i += 2;
                } else {
                    sb.append_c (input[i]); i++;
                }
            } else {
                sb.append_c (input[i]); i++;
            }
        }
        return sb.str;
    }
}