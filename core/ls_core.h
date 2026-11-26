/* FastRevers — shared core: decides whether a typed word is in the wrong layout.
 * Used as is by the Windows (Win32) and macOS (Cocoa) apps. Plain C11, no dependencies.
 * Text is UTF-16 (one unit per character): everything FastRevers handles is in the BMP. */
#ifndef LS_CORE_H
#define LS_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint16_t ls_char;

#define LS_VERSION "2.2.0"
#define LS_DONATE_URL "https://app.lava.top/4179967925"
#define LS_PRIVACY_URL "https://github.com/U-Said/FastRevers/blob/main/PRIVACY.md"

/* en / ru: what the typed keys give in the English and in the Russian layout;
 * cur_is_en: which of the two is active. Returns 1 when the word should be retyped
 * in the other layout. */
int ls_should_switch(const ls_char *en, int en_len, const ls_char *ru, int ru_len, int cur_is_en);

/* Exceptions: words that are never auto-fixed, and apps where auto-switching is off. */
void ls_exc_reset(void);                              /* clears words and apps */
void ls_exc_load(const char *utf8, size_t len);       /* exceptions file: words, "@app" lines, "#" comments */
void ls_exc_add_word(const ls_char *w, int n);        /* stored lowercase */
int  ls_exc_has_word(const ls_char *w, int n);
void ls_app_add_utf8(const char *name);
int  ls_app_excluded(const ls_char *name, int n);     /* case-insensitive */

/* Helpers. */
ls_char ls_lower(ls_char c);
void ls_lower_str(ls_char *s, int n);
int  ls_is_lat(ls_char c);                            /* a-z */
int  ls_is_cyr(ls_char c);                            /* а-я, ё */
int  ls_latin_wins(const ls_char *s, int n);          /* latin letters >= cyrillic ones */
/* Replaces every character found in from[] with the one at the same index in to[]. */
void ls_map_text(ls_char *s, int n, const ls_char *from, const ls_char *to, int map_len);
int  ls_from_utf8(const char *s, size_t len, ls_char *out, int cap);
int  ls_to_utf8(const ls_char *s, int n, char *out, int cap);

/* Detector self-test on a fixed US / Russian table. Writes a UTF-8 report,
 * returns the number of failed cases. */
int ls_selftest(char *report, int cap);

#ifdef __cplusplus
}
#endif

#endif
