public class DmaBufUpload : Gst.Base.Transform {
    static construct {
        var dmabuf_caps = Gst.Caps.from_string (
            "video/x-raw(memory:DMABuf), "
            + "format = (string) DMA_DRM, "
            + "width = (int) [ 1, 2147483647 ], "
            + "height = (int) [ 1, 2147483647 ], "
            + "framerate = (fraction) [ 0/1, 2147483647/1 ]");

        add_pad_template (new Gst.PadTemplate ("sink", Gst.PadDirection.SINK, Gst.PadPresence.ALWAYS, dmabuf_caps));
        add_pad_template (new Gst.PadTemplate ("src", Gst.PadDirection.SRC, Gst.PadPresence.ALWAYS, dmabuf_caps.copy()));
    }

    construct {
        set_passthrough (true);
        set_in_place (true);
        set_gap_aware (true);
    }

    public override Gst.Caps transform_caps (Gst.PadDirection direction, Gst.Caps caps, Gst.Caps? filter) {
        if (caps == null) {
            return new Gst.Caps.empty ();
        }
        if (filter != null && !filter.is_any ()) {
            return caps.intersect (filter, Gst.CapsIntersectMode.FIRST);
        }
        return caps;
    }


    public override bool propose_allocation (Gst.Query? decide_query, Gst.Query query) {
        if (query == null) {
            return false;
        }
        Gst.Caps? caps = null;
        query.parse_allocation (out caps, null);
        if (caps == null) {
            return false;
        }
        Gst.CapsFeatures? features = caps.get_features (0);
        bool is_dmabuf = (features != null) && features.contains ("memory:DMABuf");
        if (is_dmabuf) {
            Gst.Allocator? alloc = Gst.Allocator.find ("dmabuf");
            if (alloc != null) {
                Gst.AllocationParams allocparams = new Gst.AllocationParams ();
                allocparams.init ();
                query.add_allocation_param (alloc, allocparams);
                query.add_allocation_meta (Gst.Video.afd_meta_api_get_type (), query.get_structure ());
            }
        }
        query.add_allocation_meta(Gst.Video.meta_api_get_type (), query.get_structure ());
        query.add_allocation_meta(Gst.Video.overlay_composition_meta_api_get_type (), query.get_structure ());
        return base.propose_allocation (decide_query, query);
    }

    public override Gst.FlowReturn transform_ip (Gst.Buffer buf) {
        return Gst.FlowReturn.OK;
    }
}