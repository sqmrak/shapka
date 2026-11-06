#include "fp_theme_settings.h"
#include <assert.h>
#include <stdio.h>

int main(void)
{
    fp_theme_settings t;
    t = fp_theme_settings_read(1, 0, 0); assert(!t.classic && !t.dark);
    t = fp_theme_settings_read(2, 0, 0); assert(!t.classic && t.dark);
    t = fp_theme_settings_read(3, 0, 0); assert(t.classic && !t.dark);
    t = fp_theme_settings_read(2, 1, 1); assert(t.classic && t.dark);
    t = fp_theme_settings_read(3, 1, 0); assert(!t.classic && !t.dark);
    t = fp_theme_settings_read(0, 1, 99); assert(!t.classic && !t.dark);
    puts("theme settings tests passed");
    return 0;
}
