#ifndef FP_THEME_SETTINGS_H
#define FP_THEME_SETTINGS_H

typedef struct { int classic; int dark; } fp_theme_settings;
/* theme_mode 3 was the classic light theme before style and tone were separate */
fp_theme_settings fp_theme_settings_read(int mode, int has_style, int style);
#endif
