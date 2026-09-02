public class AllPassShifter : GLib.Object {
    private float a = 0.6f;
    private float x1 = 0.0f;
    private float y1 = 0.0f;

    public float process (float x) {
        float y = a * (x - y1) + x1;
        x1 = x;
        y1 = y;
        return y;
    }
}