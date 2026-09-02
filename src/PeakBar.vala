public class PeakBar : Gtk.DrawingArea {
    public signal void seek_requested(double position);
    private Gtk.GestureClick click_gesture;
    public int bar_height { get; set; default = 20; }
    private int peak_count;
    private double[] peak_levels;
    private double current_position;
    private double duration;
    private bool is_seeking;

    construct {
        peak_count = 500;
        peak_levels = new double[peak_count];
        current_position = 0.0;
        duration = 100.0;
        is_seeking = false;

        set_size_request(-1, 60);
        set_draw_func(draw);
        set_cursor(new Gdk.Cursor.from_name("pointer", null));

        notify["bar-height"].connect(() => {
            set_size_request(-1, bar_height);
            queue_draw();
        });

        click_gesture = new Gtk.GestureClick ();
        click_gesture.pressed.connect(on_press);
        click_gesture.released.connect(on_release);
        add_controller(click_gesture);

        var motion = new Gtk.EventControllerMotion();
        motion.motion.connect(on_motion);
        add_controller(motion);
    }

    private void on_press(int n_press, double x, double y) {
        is_seeking = true;
        process_seek(x);
    }

    private void on_release(int n_press, double x, double y) {
        is_seeking = false;
    }

    private void on_motion(double x, double y) {
        if (is_seeking) {
            process_seek(x);
        }
    }

    private void process_seek(double x) {
        if (duration <= 0) {
            return;
        }
        int width = get_width();
        if (width <= 0) {
            return;
        }
        double position = (x / width) * duration;
        if (position < 0) {
            position = 0;
        }
        if (position > duration) {
            position = duration;
        }
        current_position = position;
        queue_draw();
        seek_requested(position);
    }

    public void set_position(double position, double dur) {
        if (!is_seeking) {
            current_position = position;
        }
        duration = dur;
        queue_draw();
    }

    public void load_waveform(double[] data) {
        if (data.length == 0) {
            return;
        }
        int samples_per_bar = (int)GLib.Math.ceil((double)data.length / peak_count);
        for (int i = 0; i < peak_count; i++) {
            double max_peak = 0.0;
            int start = i * samples_per_bar;
            int end = int.min((i + 1) * samples_per_bar, data.length);
            for (int j = start; j < end; j++) {
                double val = GLib.Math.fabs(data[j]);
                if (val > max_peak) {
                    max_peak = val;
                }
            }
            peak_levels[i] = GLib.Math.fmin(max_peak, 1.0);
        }
        queue_draw();
    }

    public void generate_random_waveform() {
        var random = new GLib.Rand();
        for (int i = 0; i < peak_count; i++) {
            peak_levels[i] = random.double_range(0.1, 0.9);
        }
        queue_draw();
    }

    private void draw(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        cr.set_operator(Cairo.Operator.SOURCE);
        cr.set_source_rgba(0, 0, 0, 0);
        cr.paint();
        cr.set_operator(Cairo.Operator.OVER);

        if (peak_count == 0 || width == 0) {
            return;
        }
        double bar_width = (double)width / peak_count;
        double center_y = height / 2.0;

        double progress = (duration > 0) ? (current_position / duration) : 0.0;
        int played_bars = (int)(progress * peak_count);

        cr.set_source_rgba(1.0, 0.2, 0.2, 0.85);
        for (int i = 0; i < played_bars && i < peak_count; i++) {
            double x = i * bar_width;
            double bh = peak_levels[i] * (height / 2.0 - 2);
            cr.rectangle(x, center_y - bh, bar_width - 0.5, bh * 2);
        }
        cr.fill();

        cr.set_source_rgba(0.3, 0.7, 1.0, 0.85);
        for (int i = played_bars; i < peak_count; i++) {
            double x = i * bar_width;
            double bh = peak_levels[i] * (height / 2.0 - 2);
            cr.rectangle(x, center_y - bh, bar_width - 0.5, bh * 2);
        }
        cr.fill();

        if (duration > 0) {
            double seek_x = progress * width;
            cr.set_source_rgba(1.0, 1.0, 1.0, 0.9);
            cr.set_line_width(2.0);
            cr.move_to(seek_x, 0);
            cr.line_to(seek_x, height);
            cr.stroke();
        }
    }
}