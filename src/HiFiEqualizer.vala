public class HiFiEqualizer : GLib.Object {
    private const double Q_FACTOR = 1.414;
    private const double[] BAND_FREQS = { 32.0, 64.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0};
    private const int N_BANDS = 10;
    private int channels = 2;
    private int sample_rate = 48000;
    private double[] gains_db = new double[N_BANDS];
    private BiquadState[,] filters;

    public void init (int ch, int rate) {
        channels = ch;
        sample_rate = rate;
        filters = new BiquadState[N_BANDS, ch];
        for (int b = 0; b < N_BANDS; b++) {
            gains_db[b] = 0.0;
            for (int c = 0; c < ch; c++) {
              filters[b, c] = new BiquadState ();
            }
        }
    }

    public void set_bands (double[] band_gains) {
        for (int b = 0; b < N_BANDS && b < band_gains.length; b++) {
            gains_db[b] = band_gains[b].clamp (-12.0, 12.0);
            recalc_coeffs (b);
        }
    }

    public void set_band (int band, double gain_db) requires (band >= 0 && band < N_BANDS) {
        gains_db[band] = gain_db.clamp (-12.0, 12.0);
        recalc_coeffs (band);
    }

    public void reset () {
        if (filters == null) {
            return;
        }
        for (int b = 0; b < N_BANDS; b++) {
            for (int c = 0; c < channels; c++) {
                if (filters[b, c] != null) {
                    filters[b, c].reset ();
                }
            }
        }
    }

    public void process (ref float[] samples, int nframes, int ch) {
        for (int band = 0; band < N_BANDS; band++) {
            if (GLib.Math.fabs (gains_db[band]) < 0.05) {
                continue;
            }
            for (int i = 0; i < nframes; i++) {
                for (int c = 0; c < ch && c < channels; c++) {
                    int idx = i * ch + c;
                    samples[idx] = (float) filters[band, c].process ((double) samples[idx]);
                }
            }
        }
    }

    private void recalc_coeffs (int band) {
        double fc = BAND_FREQS[band];
        double gain = gains_db[band];
        double A = GLib.Math.pow (10.0, gain / 40.0);
        double w0 = 2.0 * GLib.Math.PI * fc / (double) sample_rate;
        double alpha = GLib.Math.sin (w0) / (2.0 * Q_FACTOR);
        double cos_w = GLib.Math.cos (w0);
        double b0_raw = 1.0 + alpha * A;
        double b1_raw = -2.0 * cos_w;
        double b2_raw = 1.0 - alpha * A;
        double a0_raw = 1.0 + alpha / A;
        double a1_raw = -2.0 * cos_w;
        double a2_raw = 1.0 - alpha / A;
        double b0 = b0_raw / a0_raw;
        double b1 = b1_raw / a0_raw;
        double b2 = b2_raw / a0_raw;
        double a1 = a1_raw / a0_raw;
        double a2 = a2_raw / a0_raw;
        for (int c = 0; c < channels; c++) {
            filters[band, c].b0 = b0;
            filters[band, c].b1 = b1;
            filters[band, c].b2 = b2;
            filters[band, c].a1 = a1;
            filters[band, c].a2 = a2;
        }
    }
}