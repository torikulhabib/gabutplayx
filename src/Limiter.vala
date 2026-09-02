public class Limiter : GLib.Object {
    private double ceiling_db = -0.3;
    private double ceiling_lin = 0.0;
    private double attack_ms = 0.1;
    private double release_ms = 50.0;
    private double gain_lin = 1.0;
    private double attack_coeff = 0.0;
    private double release_coeff = 0.0;
    private int channels = 2;
    private int sample_rate = 48000;

    public Limiter (double ceiling) {
        ceiling_db = ceiling;
        ceiling_lin = GLib.Math.pow (10.0, ceiling / 20.0);
    }

    public void init (int ch, int rate) {
        channels = ch;
        sample_rate = rate;
        gain_lin = 1.0;
        attack_coeff = 1.0 - GLib.Math.exp (-1.0 / ((double) sample_rate * attack_ms / 1000.0));
        release_coeff = 1.0 - GLib.Math.exp (-1.0 / ((double) sample_rate * release_ms / 1000.0));
    }

    public void reset () {
        gain_lin = 1.0;
    }

    public void process (ref float[] samples) {
        int nframes = samples.length / channels;
        for (int i = 0; i < nframes; i++) {
            double peak = 0.0;
            for (int c = 0; c < channels; c++) {
                double abs_val = GLib.Math.fabs (samples[i * channels + c]);
                if (abs_val > peak) {
                    peak = abs_val;
                }
            }
            double target = (peak > ceiling_lin && peak > 1e-9) ? ceiling_lin / peak : 1.0;
            double coeff = (target < gain_lin) ? attack_coeff : release_coeff;
            gain_lin+= coeff * (target - gain_lin);
            for (int c = 0; c < channels; c++) {
                samples[i * channels + c] *= (float) gain_lin;
            }
        }
    }
}
