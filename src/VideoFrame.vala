public class VideoFrame : GLib.Object {
    public Gst.Buffer buf {get; construct;}
    public Gst.Caps caps {get; construct;}
    public GLib.HashTable<size_t?, Gdk.Texture> cache {get; construct;}
    public Gee.HashSet<size_t?> used_keys {get; construct;}
    private const uint64 MOD_LINEAR = 0;
    private const uint64 MOD_INVALID = 0xffffffffffffffff;

    public VideoFrame (Gst.Buffer buffer, Gst.Caps cap, GLib.HashTable<size_t?, Gdk.Texture> cac, Gee.HashSet<size_t?> used_k) {
        Object (buf: buffer, caps: cap, cache: cac, used_keys: used_k);
    }

    public GLib.GenericArray<FrameTexture> into_textures () {
        var result = new GLib.GenericArray<FrameTexture> ();
        FrameTexture? main_ft = make_dmabuf_texture ();
        if (main_ft == null) {
            main_ft = make_memory_texture ();
        }
        if (main_ft != null) {
            result.add (main_ft);
        }
        collect_overlays (result);
        return result;
    }

    private FrameTexture? make_dmabuf_texture () {
        if (buf == null || caps == null) {
            return null;
        }
        Gst.Video.Info info = new Gst.Video.Info ();
        if (!info.from_caps (caps)) {
            return null;
        }
        unowned Gst.Structure str = caps.get_structure (0);
        string? drm_fmt_str = str.get_string ("drm-format");
        if (drm_fmt_str == null) {
            return null;
        }
        var parts = drm_fmt_str.split (":");
        if (parts.length < 1 || parts[0].length < 4) {
            return null;
        }
        uint32 fourcc = drm_name_to_fourcc (parts[0]);
        if (fourcc == 0) {
            return null;
        }
        uint64 modifier = (parts.length >= 2) ? g_ascii_strtoull (parts[1], null, 0) : MOD_LINEAR;

        uint n_planes = drm_format_n_planes (parts[0]);
        unowned Gst.Video.Meta? vmeta = Gst.Video.buffer_get_video_meta (buf);
        unowned Gst.Memory mem = buf.peek_memory (0);

        var builder = new Gdk.DmabufTextureBuilder () {
            display = Gdk.Display.get_default (),
            width = (uint) info.width,
            height = (uint) info.height,
            fourcc = fourcc,
            modifier = modifier
        };
        if (!gst_is_dmabuf_memory (mem)) {
            return null;
        }
        int fd = gst_dmabuf_memory_get_fd (mem);
        if (fd < 0) {
            return null;
        }
        if (n_planes < 3) {
            builder.n_planes = n_planes;
        }
        for (uint i = 0; i < (n_planes > 2? 2 : n_planes); i++) {
            uint offset, stride;
            if (vmeta != null && i < vmeta.n_planes) {
                offset = (uint) vmeta.offset[i];
                stride = (uint) vmeta.stride[i];
            } else {
                offset = (uint) info.offset[i];
                stride = (uint) info.stride[i];
            }
            builder.set_fd (i, fd);
            builder.set_offset (i, offset);
            builder.set_stride (i, stride);
        }
        Gdk.Texture texture = null;
        try {
            texture = builder.build (null, null);
            if (n_planes > 2) {
                builder.n_planes = n_planes;
            }
        } catch {
            if (modifier != MOD_INVALID) {
                builder.modifier = MOD_INVALID;
                try {
                    texture = builder.build (null, null);
                } catch {}
            }
        }
        if (texture == null) {
            return null;
        }
        var frame = new FrameTexture () {
            texture = texture,
            width = (float) info.width,
            height = (float) info.height,
            has_alpha = false,
            _source = buf
        };
        return frame;
    }

    private FrameTexture? make_memory_texture () {
        Gst.Video.Info info = new Gst.Video.Info ();
        if (!info.from_caps (caps)) {
            return null;
        }
        Gst.MapInfo map;
        if (!buf.map (out map, Gst.MapFlags.READ)) {
            return null;
        }
        size_t ptr_key = (size_t) map.data;
        if (cache.contains (ptr_key)) {
            buf.unmap (map);
            used_keys.add (ptr_key);
            var cached = cache.get (ptr_key);
            return make_frame_texture_from (cached, info, false);
        }
        var bytes = new GLib.Bytes.take (map.data);
        buf.unmap (map);

        unowned var vmeta = Gst.Video.buffer_get_video_meta (buf);
        size_t stride = (vmeta != null) ? (size_t) vmeta.stride[0] : (size_t) (info.width * info.finfo.pixel_stride[0]);

        var tex = new Gdk.MemoryTexture (info.width, info.height, video_format_to_gdk_enum (info.finfo.format), bytes, stride);
        cache.insert (ptr_key, tex);
        used_keys.add (ptr_key);
        return new FrameTexture () {
            texture = tex,
            width = (float) info.width,
            height = (float) info.height,
            has_alpha = has_alpha_from_format (info),
            _source = buf
        };
    }

    private FrameTexture make_frame_texture_from (Gdk.Texture tex, Gst.Video.Info info, bool has_alpha) {
        return new FrameTexture () {
            texture = tex,
            width = (float) info.width,
            height = (float) info.height,
            has_alpha = has_alpha,
            _source = buf
        };
    }

    private void collect_overlays (GLib.GenericArray<FrameTexture> result) {
        var comp_meta = get_overlay_meta (buf);
        if (comp_meta == null || comp_meta.overlay == null) {
            return;
        }
        unowned Gst.Video.OverlayComposition comp = comp_meta.overlay;
        uint n = comp.n_rectangles ();
        for (uint i = 0; i < n; i++) {
            unowned Gst.Video.OverlayRectangle? rect = comp.get_rectangle (i);
            if (rect == null) {
                continue;
            }
            int rx, ry; uint rw, rh;
            rect.get_render_rectangle (out rx, out ry, out rw, out rh);
            Gst.Buffer? overlay_buf = rect.get_pixels_unscaled_raw (Gst.Video.OverlayFormatFlags.NONE);
            if (overlay_buf == null) {
                continue;
            }
            unowned var ovmeta = Gst.Video.buffer_get_video_meta (overlay_buf);
            Gdk.MemoryFormat gdk_format;
            size_t stride;
            if (ovmeta != null) {
                gdk_format = video_format_to_gdk_enum (ovmeta.format);
                stride = (size_t) ovmeta.stride[0];
            } else {
                gdk_format = Gdk.MemoryFormat.B8G8R8A8;
                stride = (size_t) (rw * 4);
            }

            Gst.MapInfo omi;
            if (!overlay_buf.map (out omi, Gst.MapFlags.READ)) {
                continue;
            }
            var obytes = new GLib.Bytes.take (omi.data);
            overlay_buf.unmap (omi);

            var otex = new Gdk.MemoryTexture ((int) rw, (int) rh, gdk_format, obytes, stride);
            result.add (new FrameTexture () {
                texture = otex,
                x = (float) rx,
                y = (float) ry,
                width = (float) rw,
                height = (float) rh,
                has_alpha = true,
                _source = overlay_buf
            });
        }
    }
}