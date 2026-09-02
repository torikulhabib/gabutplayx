[CCode (cname = "g_ascii_strtoull", cheader_filename = "glib.h")]
extern uint64 g_ascii_strtoull (string nptr, void* endptr, uint @base);

[CCode (cname = "gst_buffer_get_video_overlay_composition_meta", cheader_filename = "gst/video/video-overlay-composition.h")]
private extern static unowned Gst.Video.OverlayCompositionMeta? get_overlay_meta (Gst.Buffer buffer);

[CCode (cname = "gst_is_dmabuf_memory", cheader_filename = "gst/allocators/gstdmabuf.h")]
extern bool gst_is_dmabuf_memory (Gst.Memory mem);

[CCode (cname = "gst_dmabuf_memory_get_fd", cheader_filename = "gst/allocators/gstdmabuf.h")]
extern int gst_dmabuf_memory_get_fd (Gst.Memory mem);