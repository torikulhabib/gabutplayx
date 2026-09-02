[CCode (cheader_filename = "zbar.h", cname = "zbar_symbol_type_t")]
public enum ZBarSymbolType {
    [CCode (cname = "ZBAR_NONE")]
    NONE = 0,

    [CCode (cname = "ZBAR_QRCODE")]
    QRCODE = 64
}

/* ---------- IMAGE SCANNER ---------- */

[CCode (cname = "zbar_image_scanner_t", cheader_filename = "zbar.h",
        free_function = "zbar_image_scanner_destroy")]
[Compact]
public class ZBarImageScanner {}

/* ---------- IMAGE ---------- */

[CCode (cname = "zbar_image_t", cheader_filename = "zbar.h",
        free_function = "zbar_image_destroy")]
[Compact]
public class ZBarImage {}

/* ---------- SYMBOL & SYMBOL SET (POINTER ONLY) ---------- */

[CCode (cname = "zbar_symbol_set_t", cheader_filename = "zbar.h")]
public struct ZBarSymbolSet {}

[CCode (cname = "zbar_symbol_t", cheader_filename = "zbar.h")]
public struct ZBarSymbol {}

/* ---------- FUNCTIONS ---------- */

[CCode (cheader_filename = "zbar.h")]
public static ZBarImageScanner zbar_image_scanner_create ();

[CCode (cheader_filename = "zbar.h")]
public static void zbar_image_scanner_set_config (
    ZBarImageScanner scanner,
    ZBarSymbolType sym,
    int config,
    int value
);

[CCode (cheader_filename = "zbar.h")]
public static ZBarImage zbar_image_create ();

[CCode (cheader_filename = "zbar.h")]
public static void zbar_image_set_format (
    ZBarImage image,
    uint32 format
);

[CCode (cheader_filename = "zbar.h")]
public static void zbar_image_set_size (
    ZBarImage image,
    uint width,
    uint height
);

[CCode (cheader_filename = "zbar.h")]
public static void zbar_image_set_data (
    ZBarImage image,
    void* data,
    ulong length,
    void* cleanup
);

[CCode (cheader_filename = "zbar.h")]
public static int zbar_scan_image (
    ZBarImageScanner scanner,
    ZBarImage image
);

[CCode (cheader_filename = "zbar.h")]
public static unowned ZBarSymbolSet* zbar_image_get_symbols (
    ZBarImage image
);

[CCode (cheader_filename = "zbar.h")]
public static unowned ZBarSymbol* zbar_symbol_set_first_symbol (
    ZBarSymbolSet* set
);

[CCode (cheader_filename = "zbar.h")]
public static unowned ZBarSymbol* zbar_symbol_next (
    ZBarSymbol* symbol
);

[CCode (cheader_filename = "zbar.h")]
public static unowned string zbar_symbol_get_data (
    ZBarSymbol* symbol
);
