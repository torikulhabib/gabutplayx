public class BiquadState : GLib.Object {
    public double b0 = 1.0;
    public double b1 = 0.0;
    public double b2 = 0.0;
    public double a1 = 0.0;
    public double a2 = 0.0;
    private double w1 = 0.0;
    private double w2 = 0.0;

    public double process (double x) {
        double y = b0 * x + w1;
        w1 = b1 * x - a1 * y + w2;
        w2 = b2 * x - a2 * y;
        return y;
    }

    public void reset () {
        w1 = 0.0;
        w2 = 0.0;
    }
}