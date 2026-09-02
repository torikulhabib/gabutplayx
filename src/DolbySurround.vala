public class DolbySurround : GLib.Object {
    private DolbyMode mode = DolbyMode.STEREO;
    private AllPassShifter phase_shift_l = new AllPassShifter ();
    private AllPassShifter phase_shift_r = new AllPassShifter ();
    private int channels_in = 2;
    private int sample_rate = 48000;
    private int delay_len = 1;
    private int delay_pos = 0;
    private float lfe_state = 0.0f;
    private float lpf_coeff = 0.0f;
    private const int MAX_DELAY = 4096;
    private float[] surround_delay = new float[MAX_DELAY];
    private float[] surround_delay_r = new float[MAX_DELAY];
    private float[] reverb_buffer_l = new float[MAX_DELAY];
    private float[] reverb_buffer_r = new float[MAX_DELAY];
    private int reverb_pos = 0;
    private int reverb_len = 1;
    private float reverb_feedback = 0.3f;
    private float reverb_damping = 0.5f;
    private float reverb_state_l = 0.0f;
    private float reverb_state_r = 0.0f;

    public void init (int ch, int rate) {
        channels_in = ch;
        sample_rate = rate;
        delay_len = (int) ((float) rate * 0.025f);
        if (delay_len > 1024) {
            delay_len = 1024;
        }
        double fc = 120.0 / (double) rate;
        double rc = 1.0 / (2.0 * GLib.Math.PI * fc);
        lpf_coeff = (float) (rc / (rc + 1.0 / (double) rate));
        reverb_len = (int) ((float) rate * 0.050f);
        reverb_len = int.min(reverb_len, MAX_DELAY);
        reverb_len = int.max(reverb_len, 1);
    }

    public void set_mode (DolbyMode m) {
        mode = m;
    }

    public void reset () {
        delay_pos = 0;
        for (int i = 0; i < surround_delay.length; i++) {
            surround_delay[i] = 0.0f;
        }
        lfe_state = 0.0f;
        phase_shift_l = new AllPassShifter ();
        phase_shift_r = new AllPassShifter ();
    }

    public void process (ref float[] samples, int nframes, ref int ch) {
        if (mode == DolbyMode.STEREO || mode == DolbyMode.BYPASS) {
            return;
        }
        if (ch < 2) {
            return;
        }
        switch (mode) {
            case DolbyMode.PROLOGIC:
                decode_prologic (ref samples, nframes, ch);
                ch = 4;
                break;
            case DolbyMode.PROLOGIC2:
                decode_prologic2 (ref samples, nframes, ch);
                ch = 6;
                break;
            case DolbyMode.SURROUND:
                virtual_surround (ref samples, nframes, ch);
                break;
            default:
                break;
        }
    }

    private void decode_prologic (ref float[] src, int nframes, int in_ch) {
        float[] aout = new float[nframes * 4];
        for (int i = 0; i < nframes; i++) {
            float lt = src[i * in_ch];
            float rt = src[i * in_ch + 1];
            float ch_l = lt;
            float ch_r = rt;
            float ch_c = 0.7071f * (lt + rt);
            float ch_s = 0.7071f * (lt - rt);
            float s_del = read_delay ();
            write_delay (ch_s);
            ch_s = iir_lpf (s_del, ref lfe_state, lpf_coeff);
            aout[i * 4] = ch_l;
            aout[i * 4 + 1] = ch_c;
            aout[i * 4 + 2] = ch_r;
            aout[i * 4 + 3] = ch_s;
        }
        src = aout;
    }

    private void decode_prologic2 (ref float[] src, int nframes, int in_ch) {
        float[] aout = new float[nframes * 6];
        for (int i = 0; i < nframes; i++) {
            float lt = src[i * in_ch];
            float rt = src[i * in_ch + 1];
            float ch_l = lt - 0.8165f * rt;
            float ch_r = rt - 0.8165f * lt;
            float ch_c = 0.7071f * (lt + rt);
            float diff = lt - rt;
            float ls_ph = phase_shift_l.process (diff);
            float rs_ph = phase_shift_r.process (-diff);
            float ls_del = read_delay ();
            write_delay (ls_ph);
            float lfe_raw = 0.5f * (lt + rt);
            float lfe_out = iir_lpf (lfe_raw, ref lfe_state, lpf_coeff);
            ch_l *= 0.8165f;
            ch_r *= 0.8165f;
            ch_c *= 0.7071f;
            ls_ph *= 0.7071f;
            rs_ph *= 0.7071f;
            aout[i * 6] = ch_l;
            aout[i * 6 + 1] = ch_c;
            aout[i * 6 + 2] = ch_r;
            aout[i * 6 + 3] = ls_del;
            aout[i * 6 + 4] = rs_ph;
            aout[i * 6 + 5] = lfe_out * 0.5f;
        }
        src = aout;
    }

    private void virtual_surround (ref float[] src, int nframes, int in_ch) {
        float[] aout = new float[nframes * 2];
        for (int i = 0; i < nframes; i++) {
            float l = src[i * in_ch];
            float r = src[i * in_ch + 1];
            float s = 0.7071f * (l - r);
            float s_del_l = read_delay_l ();
            float s_del_r = read_delay_r ();
            write_delay_l (s);
            write_delay_r (-s);
            float cf = 0.30f;
            float l_cf = l * (1.0f - cf) + r * cf;
            float r_cf = r * (1.0f - cf) + l * cf;
            float reverb_l = process_reverb_l (s * 0.5f);
            float reverb_r = process_reverb_r (-s * 0.5f);
            float width = 1.8f;
            float depth = 0.4f;
            float surround_l = width * s_del_l + depth * reverb_l;
            float surround_r = width * s_del_r + depth * reverb_r;
            float out_l = l_cf + surround_l;
            float out_r = r_cf + surround_r;
            aout[i * 2] = soft_limit(out_l);
            aout[i * 2 + 1] = soft_limit(out_r);
        }
        src = aout;
    }

    private float soft_limit (float x) {
        if (x > 1.0f) {
            return 1.0f + (x - 1.0f) * 0.1f;
        }
        if (x < -1.0f) {
            return -1.0f + (x + 1.0f) * 0.1f;
        }
        return x;
    }

    private float process_reverb_l (float x) {
        if (reverb_len <= 0) {
            return 0.0f;
        }
        int rp = reverb_pos % reverb_len;
        float buf = reverb_buffer_l[rp];
        reverb_state_l = reverb_state_l * reverb_damping + buf * (1.0f - reverb_damping);
        reverb_buffer_l[rp] = x + reverb_state_l * reverb_feedback;
        return buf;
    }

    private float process_reverb_r (float x) {
        if (reverb_len <= 0) {
            return 0.0f;
        }
        int rp = reverb_pos % reverb_len;
        float buf = reverb_buffer_r[rp];
        reverb_state_r = reverb_state_r * reverb_damping + buf * (1.0f - reverb_damping);
        reverb_buffer_r[rp] = x + reverb_state_r * reverb_feedback;
        reverb_pos = (reverb_pos + 1) % reverb_len;
        return buf;
    }

    private float read_delay_l () {
        if (delay_len <= 0) {
            return 0.0f;
        }
        return surround_delay[delay_pos % delay_len];
    }

    private float read_delay_r () {
        if (delay_len <= 0) {
            return 0.0f;
        }
        return surround_delay_r[delay_pos % delay_len];
    }

    private void write_delay_l (float val) {
        if (delay_len <= 0) {
            return;
        }
        surround_delay[delay_pos % delay_len] = val;
    }

    private void write_delay_r (float val) {
        if (delay_len <= 0) {
            return;
        }
        surround_delay_r[delay_pos % delay_len] = val;
        delay_pos = (delay_pos + 1) % delay_len;
    }

    private float read_delay () {
        if (delay_len <= 0) {
            return 0.0f;
        }
        return surround_delay[delay_pos % delay_len];
    }

    private void write_delay (float val) {
        if (delay_len <= 0) {
            return;
        }
        surround_delay[delay_pos % delay_len] = val;
        delay_pos = (delay_pos + 1) % delay_len;
    }

    private float iir_lpf (float x, ref float state, float coeff) {
        state = state * coeff + x * (1.0f - coeff);
        return state;
    }
}