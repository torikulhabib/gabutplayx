public class SubtitleSpan : Object {
    public string text = "";
    public string? color = null;
    public bool bold { get; set; default = false; }
    public bool italic { get; set; default = false; }
    public bool underline { get; set; default = false; }
}