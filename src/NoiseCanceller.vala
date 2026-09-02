public class NoiseCanceller : GLib.Object {
    private int fft_size = 512;
    private int hop_size = 128;
    private int channels = 2;
    private int sample_rate = 48000;
    private int vad_holdoff = 0;
    private int overlap_pos = 0;
    private double alpha = 0.7;
    private double reduction_db = 12.0;
    private double smooth_factor = 0.15;
    private double vad_threshold = 0.01;
    private bool adaptive_mode = false;
    private float[] noise_profile = new float[0];
    private float[] smooth_gain = new float[0];
    private float[] window = new float[0];
    private float[] overlap_buffer = new float[0];

    public void init (int ch, int rate, int buf_size) {
        channels = ch;
        sample_rate = rate;
        fft_size = next_power_of_two (buf_size);
        if (fft_size < 256) {
            fft_size = 256;
        }
        hop_size = fft_size / 4;
        int spec_size = fft_size / 2 + 1;
        noise_profile = new float[spec_size * channels];
        smooth_gain = new float[spec_size * channels];
        window = new float[fft_size];
        overlap_buffer = new float[fft_size * channels];
        for (int i = 0; i < fft_size; i++) {
            window[i] = 0.5f - 0.5f * (float)GLib.Math.cos((2.0 * Math.PI * i) / (fft_size - 1));
        }
        GLib.Memory.set (noise_profile, 0, noise_profile.length * (int) sizeof (float));
        GLib.Memory.set (smooth_gain, 0, smooth_gain.length * (int) sizeof (float));
        GLib.Memory.set (overlap_buffer, 0, overlap_buffer.length * (int) sizeof (float));
        overlap_pos = 0;
    }

    public void reset () {
        GLib.Memory.set (smooth_gain, 0, smooth_gain.length * (int) sizeof (float));
        GLib.Memory.set (overlap_buffer, 0, overlap_buffer.length * (int) sizeof (float));
        overlap_pos = 0;
        vad_holdoff = 0;
    }

    public void configure (double a, double db, double smooth) {
        alpha = a;
        reduction_db = db;
        smooth_factor = smooth;
    }

    public void set_adaptive (bool val) {
        adaptive_mode = val;
    }

    public void set_noise_profile (float[] profile) {
        int len = int.min(profile.length, noise_profile.length);
        GLib.Memory.copy (noise_profile, profile, len * (int) sizeof (float));
        for (int i = 0; i < smooth_gain.length && i < len; i++) {
            float noise_var = profile[i] * profile[i];
            float signal_var = noise_var * 4.0f;
            float snr = signal_var / float.max(noise_var, 1e-10f);
            smooth_gain[i] = snr / (1.0f + snr);
        }
    }

    public void process (ref float[] samples, int nframes, int ch) {
        channels = ch;
        int spec_size = fft_size / 2 + 1;
        for (int c = 0; c < channels; c++) {
            float[] chan_buf = new float[nframes];
            for (int i = 0; i < nframes; i++) {
                chan_buf[i] = samples[i * channels + c];
            }
            float[] processed = process_channel_time_domain (chan_buf, c, spec_size);
            for (int i = 0; i < nframes && i < processed.length; i++) {
                samples[i * channels + c] = processed[i];
            }
        }
        if (adaptive_mode) {
            update_adaptive_noise (samples, nframes);
        }
    }

    private float[] process_channel_time_domain (float[] input, int ch, int spec_size) {
        float[] output = new float[input.length];
        float beta = (float) GLib.Math.pow (10.0, -reduction_db / 20.0);
        int ch_off = ch * spec_size;
        float frame_energy = 0.0f;
        for (int i = 0; i < input.length; i++) {
            frame_energy += input[i] * input[i];
        }
        frame_energy = GLib.Math.sqrtf (frame_energy / input.length);
        float noise_rms = 0.0f;
        int count = 0;
        for (int s = 0; s < spec_size; s++) {
            noise_rms += noise_profile[ch_off + s];
            count++;
        }
        noise_rms = (count > 0) ? (noise_rms / count) : 0.0f;
        for (int i = 0; i < input.length; i++) {
            float x = input[i];
            float local_power = estimate_local_power (input, i, 32);
            float signal_est = float.max(local_power - (float)alpha * noise_rms, 0.0f);
            float snr = (noise_rms > 1e-6f) ? (signal_est / noise_rms) : 100.0f;
            float target_gain = snr / (1.0f + snr);
            float floor_gain = beta;
            target_gain = float.max(target_gain, floor_gain);
            target_gain = float.min(target_gain, 1.0f);
            int spec_idx = (i * spec_size / input.length).clamp(0, spec_size - 1);
            float prev_g = smooth_gain[ch_off + spec_idx];
            float g = (1.0f - (float)smooth_factor) * prev_g + (float)smooth_factor * target_gain;
            smooth_gain[ch_off + spec_idx] = g;
            output[i] = x * g;
        }
        return output;
    }

    private float estimate_local_power (float[] buf, int pos, int win_len) {
        float sum = 0.0f;
        int count = 0;
        int start = int.max(0, pos - win_len / 2);
        int end = int.min(buf.length, pos + win_len / 2);
        for (int i = start; i < end; i++) {
            sum += buf[i] * buf[i];
            count++;
        }
        return (count > 0) ? GLib.Math.sqrtf (sum / (float) count) : 0.0f;
    }

    private void update_adaptive_noise (float[] samples, int nframes) {
        int spec_size = fft_size / 2 + 1;
        float energy = 0.0f;
        for (int i = 0; i < samples.length; i++) {
            energy += samples[i] * samples[i];
        }
        energy /= (float) samples.length;
        bool is_noise = (energy < (float) vad_threshold);
        if (energy >= (float) vad_threshold) {
            vad_holdoff = (int) ((float) sample_rate * 0.3f / nframes);
        } else if (vad_holdoff > 0) {
            vad_holdoff--;
        }
        if (is_noise && vad_holdoff <= 0) {
            float adapt_rate = 0.01f;
            for (int c = 0; c < channels; c++) {
                for (int s = 0; s < spec_size; s++) {
                    int idx = c * spec_size + s;
                    int sample_start = (s * nframes / spec_size).clamp(0, nframes - 1);
                    int sample_end = ((s + 1) * nframes / spec_size).clamp(0, nframes);
                    float chunk_rms = 0.0f;
                    int chunk_count = 0;
                    for (int i = sample_start; i < sample_end && (i * channels + c) < samples.length; i++) {
                        float v = samples[i * channels + c];
                        chunk_rms += v * v;
                        chunk_count++;
                    }
                    chunk_rms = (chunk_count > 0) ? GLib.Math.sqrtf(chunk_rms / chunk_count) : 0.0f;
                    noise_profile[idx] = noise_profile[idx] * (1.0f - adapt_rate) + chunk_rms * adapt_rate;
                }
            }
        }
    }

    private int next_power_of_two (int n) {
        int p = 1;
        while (p < n) {
            p <<= 1;
        }
        return p;
    }
}