#include "fp_theme_settings.h"

fp_theme_settings fp_theme_settings_read(int mode, int has_style, int style)
{
    fp_theme_settings result;
    result.classic = has_style ? style == 1 : mode == 3;
    result.dark = mode == 2;
    return result;
}
