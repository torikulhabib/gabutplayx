public class FrameTexture : Object {
    public Gdk.Texture texture;
    public Gst.Buffer? _source = null;
    public float x { get; set; default = 0f; }
    public float y { get; set; default = 0f; }
    public float width { get; set; default = 0f; }
    public float height { get; set; default = 0f; }
    public float global_alpha { get; set; default = 1f; }
    public bool has_alpha { get; set; default = false; }
}