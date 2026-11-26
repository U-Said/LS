/* FastRevers — shared core. See ls_core.h.
 * There is no dictionary: a word is judged by Russian and English spelling rules
 * and by lists of frequent words. */
#include "ls_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXW 128

/* ------------------------------------------------------------------ UTF-8 */
int ls_from_utf8(const char *s, size_t len, ls_char *out, int cap)
{
    int n = 0;
    size_t i = 0;
    while (i < len && n < cap) {
        unsigned c = (unsigned char)s[i];
        uint32_t cp;
        int k;
        if (c < 0x80)                { cp = c;        k = 1; }
        else if ((c & 0xE0) == 0xC0) { cp = c & 0x1F; k = 2; }
        else if ((c & 0xF0) == 0xE0) { cp = c & 0x0F; k = 3; }
        else if ((c & 0xF8) == 0xF0) { cp = c & 0x07; k = 4; }
        else { i++; continue; }
        if (i + (size_t)k > len)
            break;
        for (int j = 1; j < k; j++)
            cp = (cp << 6) | ((unsigned char)s[i + j] & 0x3F);
        i += (size_t)k;
        out[n++] = (ls_char)(cp > 0xFFFF ? 0xFFFD : cp);
    }
    return n;
}

int ls_to_utf8(const ls_char *s, int n, char *out, int cap)
{
    int k = 0;
    for (int i = 0; i < n; i++) {
        unsigned c = s[i];
        if (c < 0x80) {
            if (k + 1 > cap) break;
            out[k++] = (char)c;
        } else if (c < 0x800) {
            if (k + 2 > cap) break;
            out[k++] = (char)(0xC0 | (c >> 6));
            out[k++] = (char)(0x80 | (c & 0x3F));
        } else {
            if (k + 3 > cap) break;
            out[k++] = (char)(0xE0 | (c >> 12));
            out[k++] = (char)(0x80 | ((c >> 6) & 0x3F));
            out[k++] = (char)(0x80 | (c & 0x3F));
        }
    }
    return k;
}

/* ------------------------------------------------------------------ characters */
ls_char ls_lower(ls_char c)
{
    if (c >= 'A' && c <= 'Z') return (ls_char)(c + 32);
    if (c >= 0x410 && c <= 0x42F) return (ls_char)(c + 32);
    if (c >= 0x400 && c <= 0x40F) return (ls_char)(c + 80);
    return c;
}

static ls_char ls_upper(ls_char c)
{
    if (c >= 'a' && c <= 'z') return (ls_char)(c - 32);
    if (c >= 0x430 && c <= 0x44F) return (ls_char)(c - 32);
    if (c >= 0x450 && c <= 0x45F) return (ls_char)(c - 80);
    return c;
}

void ls_lower_str(ls_char *s, int n)
{
    for (int i = 0; i < n; i++)
        s[i] = ls_lower(s[i]);
}

int ls_is_lat(ls_char c) { return c >= 'a' && c <= 'z'; }
int ls_is_cyr(ls_char c) { return (c >= 0x430 && c <= 0x44F) || c == 0x451; }

int ls_latin_wins(const ls_char *s, int n)
{
    int lat = 0, cyr = 0;
    for (int i = 0; i < n; i++) {
        ls_char c = s[i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'))
            lat++;
        else if ((c >= 0x410 && c <= 0x44F) || c == 0x401 || c == 0x451)
            cyr++;
    }
    return lat >= cyr;
}

void ls_map_text(ls_char *s, int n, const ls_char *from, const ls_char *to, int map_len)
{
    for (int i = 0; i < n; i++)
        for (int j = 0; j < map_len; j++)
            if (from[j] == s[i]) {
                s[i] = to[j];
                break;
            }
}

/* ------------------------------------------------------------------ word sets */
typedef struct { ls_char *s; int n; int used; } item;
typedef struct { item *tab; int cap, count; } wset;

static uint32_t hash_of(const ls_char *s, int n)
{
    uint32_t h = 2166136261u;
    for (int i = 0; i < n; i++) {
        h ^= s[i];
        h *= 16777619u;
    }
    return h;
}

static int find_slot(const wset *w, const ls_char *s, int n)
{
    int mask = w->cap - 1;
    int i = (int)(hash_of(s, n) & (uint32_t)mask);
    while (w->tab[i].used) {
        if (w->tab[i].n == n && memcmp(w->tab[i].s, s, (size_t)n * sizeof(ls_char)) == 0)
            return i;
        i = (i + 1) & mask;
    }
    return i;
}

static void wset_grow(wset *w)
{
    int ocap = w->cap;
    item *old = w->tab;
    int ncap = ocap ? ocap * 2 : 64;
    item *tab = (item *)calloc((size_t)ncap, sizeof(item));
    if (!tab)
        return;
    w->tab = tab;
    w->cap = ncap;
    w->count = 0;
    for (int i = 0; i < ocap; i++)
        if (old[i].used) {
            w->tab[find_slot(w, old[i].s, old[i].n)] = old[i];
            w->count++;
        }
    free(old);
}

static int wset_has(const wset *w, const ls_char *s, int n)
{
    return w->cap && w->tab[find_slot(w, s, n)].used;
}

static void wset_add(wset *w, const ls_char *s, int n)
{
    if ((w->count + 1) * 2 > w->cap)
        wset_grow(w);
    if (!w->cap)
        return;
    int i = find_slot(w, s, n);
    if (w->tab[i].used)
        return;
    ls_char *copy = (ls_char *)malloc((size_t)(n ? n : 1) * sizeof(ls_char));
    if (!copy)
        return;
    if (n)
        memcpy(copy, s, (size_t)n * sizeof(ls_char));
    w->tab[i].s = copy;
    w->tab[i].n = n;
    w->tab[i].used = 1;
    w->count++;
}

static void wset_clear(wset *w)
{
    for (int i = 0; i < w->cap; i++)
        if (w->tab[i].used)
            free(w->tab[i].s);
    free(w->tab);
    w->tab = NULL;
    w->cap = w->count = 0;
}

/* Space-separated UTF-8 words; the empty word is added too (it matters for onsets/codas). */
static void wset_add_words(wset *w, const char *words)
{
    ls_char tmp[MAXW];
    wset_add(w, tmp, 0);
    const char *p = words;
    while (*p) {
        while (*p == ' ')
            p++;
        const char *q = p;
        while (*q && *q != ' ')
            q++;
        if (q > p)
            wset_add(w, tmp, ls_from_utf8(p, (size_t)(q - p), tmp, MAXW));
        p = q;
    }
}

/* ------------------------------------------------------------------ word lists */
/* Lists of frequent words were compiled for this project (with an AI assistant) and are not copied from
   third-party dictionaries; MIT, like the rest of the code. */
static const char COMMON_EN[] =
    "the be to of and in that have it for not on with he as you do at this but his by from they we say her she or an "
    "will my one all would there their what so up out if about who get which go me when make can like time no just him "
    "know take people into year your good some could them see other than then now look only come its over think also "
    "back after use two how our work first well way even new want because any these give day most us is are was were "
    "been has had did am being here very much more many such those own same too where why while should must may might "
    "each every both few again once before between under through during without against around off down still never "
    "always often really maybe yes ok okay hello hi hey thanks thank please sorry love help need find tell ask try call "
    "keep let put seem feel become leave mean name home world life hand part place case week number point fact group "
    "problem thing man woman child school state family house company system program question money right left long "
    "little big great small old high low next last best better sure true false null file code data test user login "
    "email password google windows linux python java script http https ftp www html css xml json sql php pdf txt jpg "
    "jpeg png gif svg exe dll zip rar mp3 mp4 usb cpu gpu ram ssd hdd wifi api url uri sdk ide git npm pip src cmd ssh "
    "vpn dns tcp udp ip id ui ux qa pr vs tv pc db js ts cs py md rb kb mb gb px pt hr br td tr th ul ol li div img "
    "btn std str int ptr len num max min avg tmp msg cfg app dev prod docs lib bin etc usr var opt i.e e.g fly sky dry "
    "cry shy spy fry myth sync lynx hymn crypt gym printf sprintf fprintf scanf kubectl href rgba rgb stdin stdout "
    "stderr nginx mkdir chmod chown sudo grep curl wget argv argc args kwargs utf ascii uuid guid tsx jsx yml yaml "
    "toml csv tsv sqlite mysql redis nodejs webpack eslint pytest numpy scipy github gitlab vscode powershell dotnet "
    "nuget xcode docker async await const struct enum void bool char float double string array object class public "
    "private static return import export function default brew zsh bash macos";

static const char COMMON_RU[] =
    "и в не на я что он с как а то по это она этот к но они мы все всё у же вы за бы так от его её ее из ты да нет "
    "для о мне меня был была было были быть есть ещё еще уже или если когда только вот тоже себя свой мой твой наш "
    "ваш их там тут здесь где кто чем чтобы до ли ну под при над без про через после очень можно надо нужно будет "
    "буду будем раз два три год день время дело жизнь рука человек люди слово место лицо друг дом сам сама само "
    "самый который которая которые этого этом эта эти тот та те того тем том них него неё нее ним ней нас нам вас "
    "вам тебя тебе себе мной тобой один одна одно ничего никогда всегда сейчас теперь потом тогда потому почему "
    "зачем куда откуда сколько какой какая какие такой такая такие другой другие новый большой хорошо плохо "
    "спасибо пожалуйста привет пока ладно давай может могу можешь хочу хочешь знаю знаешь думаю говорит сказал "
    "сказала сделать делать работа работать вопрос ответ более менее много мало также либо ведь даже лишь уж "
    "вдруг почти совсем просто конечно наверное кстати например значит вообще именно сегодня завтра вчера утро "
    "вечер ночь ща шт ша ок здравствуйте добрый доброе понял поняла ясно точно типа короче блин норм нормально "
    "дела чё че щас";

static const char ONSETS[] =
    "b bl br c ch chr cl cr d dr dw f fl fr g gh gl gn gr h j k kl kn kr l m n p ph phr pl pr ps q r rh s sc sch scr "
    "sh shr sk sl sm sn sp sph spl spr st str sv sw t th thr tr ts tw v w wh wr x z";

static const char CODAS[] =
    "b bb bs bt bts c ch ck cks cs ct cts d dd dds ds dth dz f ff ffs fs ft fth fths fts g gg gs gh ghs ght ghts gm gn "
    "gns h hm hn hs k ks l lb lbs lc lch ld lds lf lfs lfth lk lks ll lls lm lms ln lp lps lpt ls lt lth lts ltz lv m "
    "mb mbs mm mn mns mp mps mpt mpts ms mth n nc nch nct ncts nd nds ng ngs ngst ngth ngths nk nks nn ns nst nt nth "
    "nths nts ntz nx nz p pp ps pt pth pths pts r rb rbs rc rch rd rds rf rfs rg rgs rk rks rl rld rlds rls rm rms "
    "rmth rn rns rp rps rpt rr rs rsh rst rsts rt rth rths rts rtz rv rz s sc sh sk sks sm sms sp sps ss st sts t tch "
    "th thm thms ths ts tt tts tz v vs w wd wds wk wks wl wls wn wns ws wt wth x xt xth xts z zz";

static const char BAD_EN[] =
    "vb vc vd vf vg vh vj vk vm vp vq vt vw vx vz zx xz qq wx wq wj hx hj hq kx kq kz kj pq pz cx cj cv cf cg cp cw "
    "bx bq dx dq fq fx fz fv gq gx mq mx mz mj lx lq tq tx sx zc zd zf zg zj zk zp zq zr zs zv zw xj xk xg";

static wset g_common_en, g_common_ru, g_onsets, g_codas, g_bad_en;
static wset g_exc, g_apps;
static int g_inited;

/* Short Russian letter sets, decoded once. */
enum { S_RUV, S_SOFT_HARD_Y, S_AFTER_HARD, S_AFTER_SOFT, S_BEFORE_Y, S_AFTER_J,
       S_BEFORE_SHCH, S_AFTER_SHCH, S_AFTER_CH, S_AFTER_ZH, S_AFTER_SH, S_AFTER_TS, S_AFTER_F,
       S_COUNT };
static const char *const SET_SRC[S_COUNT] = {
    "аеёиоуыэюя",      /* S_RUV */
    "ъьы",             /* S_SOFT_HARD_Y: cannot start a word */
    "еёюя",            /* S_AFTER_HARD: what may follow ъ */
    "ыйау",            /* S_AFTER_SOFT: what may not follow ь */
    "жшчщйгкх",        /* S_BEFORE_Y: what may not precede ы */
    "йёэ",             /* S_AFTER_J */
    "гджзклпсфхцчшщ",  /* S_BEFORE_SHCH */
    "аеёиоун",         /* S_AFTER_SHCH: the only letters after щ */
    "бгджзпфхцсяю",    /* S_AFTER_CH */
    "фхцчшптзя",       /* S_AFTER_ZH */
    "жзчцфхбгдя",      /* S_AFTER_SH */
    "бгджзпфхчшяюё",   /* S_AFTER_TS */
    "бвгджзпхц",       /* S_AFTER_F */
};
static ls_char g_sets[S_COUNT][16];

static int in_set(int set, ls_char c)
{
    for (const ls_char *p = g_sets[set]; *p; p++)
        if (*p == c)
            return 1;
    return 0;
}

static void ls_init(void)
{
    if (g_inited)
        return;
    g_inited = 1;
    wset_add_words(&g_common_en, COMMON_EN);
    wset_add_words(&g_common_ru, COMMON_RU);
    wset_add_words(&g_onsets, ONSETS);
    wset_add_words(&g_codas, CODAS);
    wset_add_words(&g_bad_en, BAD_EN);
    for (int i = 0; i < S_COUNT; i++) {
        int n = ls_from_utf8(SET_SRC[i], strlen(SET_SRC[i]), g_sets[i], 15);
        g_sets[i][n] = 0;
    }
}

/* ------------------------------------------------------------------ Russian rules */
#define CH(x) ((ls_char)(x))
static const ls_char RU_SOFT = 0x44C, RU_HARD = 0x44A, RU_Y = 0x44B, RU_J = 0x439, RU_JO = 0x451,
                     RU_SHCH = 0x449, RU_CH = 0x447, RU_ZH = 0x436, RU_SH = 0x448, RU_TS = 0x446,
                     RU_F = 0x444, RU_E = 0x44D;

/* p — previous letter, c — current one: true when the pair does not occur in Russian. */
static int bad_ru(ls_char p, ls_char c)
{
    int pv = in_set(S_RUV, p);
    if (c == RU_SOFT || c == RU_HARD)
        return pv || p == RU_J || p == RU_SOFT || p == RU_HARD || p == CH('-');
    if (p == CH('-')) return 0;
    if (p == RU_HARD) return !in_set(S_AFTER_HARD, c);
    if (p == RU_SOFT) return in_set(S_AFTER_SOFT, c);
    if (c == RU_Y)    return pv || in_set(S_BEFORE_Y, p);
    if (p == RU_JO)   return in_set(S_RUV, c);
    if (p == RU_J)    return in_set(S_AFTER_J, c);
    if (c == RU_SHCH) return in_set(S_BEFORE_SHCH, p);
    if (p == RU_SHCH) return !in_set(S_AFTER_SHCH, c);
    if (p == RU_CH)   return in_set(S_AFTER_CH, c);
    if (p == RU_ZH)   return in_set(S_AFTER_ZH, c);
    if (p == RU_SH)   return in_set(S_AFTER_SH, c);
    if (p == RU_TS)   return in_set(S_AFTER_TS, c);
    if (p == RU_F)    return in_set(S_AFTER_F, c);
    if (p == RU_E)    return c == RU_E;
    return 0;
}

static int ru_plausible(const ls_char *w, int n)
{
    if (n < 3)
        return 0;
    if (in_set(S_SOFT_HARD_Y, w[0]) || w[n - 1] == RU_HARD)
        return 0;
    int has_v = 0, run = 0;
    ls_char p = 0, pp = 0;
    for (int i = 0; i < n; i++) {
        ls_char c = w[i];
        if (c == CH('-')) {
            if (i == 0 || i == n - 1)
                return 0;
            run = 0;
        } else {
            if (!ls_is_cyr(c))
                return 0;
            if (in_set(S_RUV, c)) {
                has_v = 1;
                run = 0;
            } else if (c != RU_SOFT && c != RU_HARD) {
                if (++run > 5)
                    return 0;
            }
            if (i > 0) {
                if (bad_ru(p, c))
                    return 0;
                if (i > 1 && p == c && pp == c)
                    return 0;
            }
        }
        pp = p;
        p = c;
    }
    return has_v;
}

/* ------------------------------------------------------------------ English rules */
static int is_en_vowel(ls_char c)
{
    return c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u' || c == 'y';
}

static int en_plausible_word(const ls_char *w, int n)
{
    if (n <= 0)
        return 0;
    int first = -1, last = -1, run = 0, strong = 0;
    for (int i = 0; i < n; i++) {
        ls_char c = w[i];
        if (!ls_is_lat(c))
            return 0;
        if (is_en_vowel(c)) {
            if (first < 0)
                first = i;
            last = i;
            run = 0;
            if (c != 'y')
                strong = 1;
        } else if (++run > 5) {
            return 0;
        }
        if (i < n - 1) {
            ls_char d = w[i + 1];
            if (c == 'q' && d != 'u')
                return 0;
            if (c == 'j' && !is_en_vowel(d))
                return 0;
            if (wset_has(&g_bad_en, w + i, 2))
                return 0;
        } else if (c == 'q' || c == 'j') {
            return 0;
        }
    }
    if (!strong)
        return 0;
    return wset_has(&g_onsets, w, first) && wset_has(&g_codas, w + last + 1, n - last - 1);
}

/* A token like "file.txt" or "don't": split on non-letters. */
static int en_plausible_token(const ls_char *t, int n)
{
    int any = 0, start = -1;
    for (int i = 0; i <= n; i++) {
        if (i < n && ls_is_lat(t[i])) {
            if (start < 0)
                start = i;
            continue;
        }
        if (start < 0)
            continue;
        int len = i - start;
        if (en_plausible_word(t + start, len)) {
            if (len >= 2)
                any = 1;
        } else if (len > 3) {
            return 0;
        }
        start = -1;
    }
    return any;
}

static void trim_to(const ls_char *s, int n, int cyr, int *from, int *len)
{
    int a = 0, b = n - 1;
    while (a <= b && !(cyr ? ls_is_cyr(s[a]) : ls_is_lat(s[a])))
        a++;
    while (b >= a && !(cyr ? ls_is_cyr(s[b]) : ls_is_lat(s[b])))
        b--;
    *from = a;
    *len = b - a + 1;
}

static int all_lat(const ls_char *s, int n)
{
    if (n <= 0)
        return 0;
    for (int i = 0; i < n; i++)
        if (!ls_is_lat(s[i]))
            return 0;
    return 1;
}

/* ------------------------------------------------------------------ the decision */
int ls_should_switch(const ls_char *en_in, int en_len, const ls_char *ru_in, int ru_len, int cur_is_en)
{
    ls_init();
    if (en_len <= 0 || ru_len <= 0 || en_len > MAXW || ru_len > MAXW)
        return 0;
    const ls_char *cur = cur_is_en ? en_in : ru_in;
    int cur_len = cur_is_en ? en_len : ru_len;
    int letters = 0, has_lower = 0;
    for (int i = 0; i < cur_len; i++) {
        ls_char c = cur[i];
        if (c >= '0' && c <= '9')
            return 0;
        if (ls_upper(c) != ls_lower(c)) {
            letters++;
            if (c != ls_upper(c))
                has_lower = 1;
        }
    }
    if (letters >= 2 && !has_lower)            /* ABBREVIATIONS are left alone */
        return 0;

    ls_char en[MAXW], ru[MAXW];
    memcpy(en, en_in, (size_t)en_len * sizeof(ls_char));
    memcpy(ru, ru_in, (size_t)ru_len * sizeof(ls_char));
    ls_lower_str(en, en_len);
    ls_lower_str(ru, ru_len);
    if (cur_is_en ? wset_has(&g_exc, en, en_len) : wset_has(&g_exc, ru, ru_len))
        return 0;

    int ef, el, rf, rl;
    trim_to(en, en_len, 0, &ef, &el);
    trim_to(ru, ru_len, 1, &rf, &rl);
    const ls_char *ec = en + ef, *rc = ru + rf;

    if (cur_is_en) {
        if (rl < 2)
            return 0;
        if (wset_has(&g_exc, ec, el) || wset_has(&g_common_en, ec, el))
            return 0;
        if (wset_has(&g_common_ru, rc, rl))
            return 1;
        return ru_plausible(rc, rl) && !en_plausible_token(ec, el);
    }
    if (el < 2 || !all_lat(ec, el))
        return 0;
    if (wset_has(&g_exc, rc, rl) || wset_has(&g_common_ru, rc, rl))
        return 0;
    if (wset_has(&g_common_en, ec, el))
        return 1;
    return el >= 3 && !ru_plausible(rc, rl) && en_plausible_word(ec, el);
}

/* ------------------------------------------------------------------ exceptions */
void ls_exc_reset(void)
{
    wset_clear(&g_exc);
    wset_clear(&g_apps);
}

void ls_exc_add_word(const ls_char *w, int n)
{
    ls_char tmp[MAXW];
    if (n <= 0 || n > MAXW)
        return;
    memcpy(tmp, w, (size_t)n * sizeof(ls_char));
    ls_lower_str(tmp, n);
    wset_add(&g_exc, tmp, n);
}

int ls_exc_has_word(const ls_char *w, int n)
{
    ls_char tmp[MAXW];
    if (n <= 0 || n > MAXW)
        return 0;
    memcpy(tmp, w, (size_t)n * sizeof(ls_char));
    ls_lower_str(tmp, n);
    return wset_has(&g_exc, tmp, n);
}

void ls_app_add_utf8(const char *name)
{
    ls_char tmp[MAXW];
    int n = ls_from_utf8(name, strlen(name), tmp, MAXW);
    ls_lower_str(tmp, n);
    if (n > 0)
        wset_add(&g_apps, tmp, n);
}

int ls_app_excluded(const ls_char *name, int n)
{
    ls_char tmp[MAXW];
    if (n <= 0 || n > MAXW)
        return 0;
    memcpy(tmp, name, (size_t)n * sizeof(ls_char));
    ls_lower_str(tmp, n);
    return wset_has(&g_apps, tmp, n);
}

void ls_exc_load(const char *data, size_t len)
{
    size_t i = 0;
    if (len >= 3 && (unsigned char)data[0] == 0xEF && (unsigned char)data[1] == 0xBB && (unsigned char)data[2] == 0xBF)
        i = 3;
    while (i < len) {
        size_t e = i;
        while (e < len && data[e] != '\n')
            e++;
        size_t a = i, b = e;
        while (a < b && (data[a] == ' ' || data[a] == '\t' || data[a] == '\r'))
            a++;
        while (b > a && (data[b - 1] == ' ' || data[b - 1] == '\t' || data[b - 1] == '\r'))
            b--;
        if (b > a && data[a] != '#') {
            ls_char w[MAXW];
            if (data[a] == '@') {
                int n = ls_from_utf8(data + a + 1, b - a - 1, w, MAXW);
                ls_lower_str(w, n);
                if (n > 0)
                    wset_add(&g_apps, w, n);
            } else {
                int n = ls_from_utf8(data + a, b - a, w, MAXW);
                ls_exc_add_word(w, n);
            }
        }
        i = e + 1;
    }
}

/* ------------------------------------------------------------------ self-test */
/* The standard US and Russian (ЙЦУКЕН) layouts, key by key. */
static const char TAB_EN[] =
    "`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?@#$^&|";
static const char TAB_RU[] =
    "ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,\"№;:?/";

typedef struct { const char *typed; int cur_is_en; int expect; } tcase;
static const tcase CASES[] = {
    /* typed in the English layout */
    {"ghbdtn", 1, 1}, {"Ghbdtn", 1, 1}, {"rfr", 1, 1}, {"xnj", 1, 1}, {"relf", 1, 1}, {"ytn", 1, 1},
    {"k.,jdm", 1, 1}, {"cgfcb,j", 1, 1}, {"vjcrdf", 1, 1}, {"[jhjij", 1, 1}, {"e;t", 1, 1}, {"ghbdtn?", 1, 1},
    {"hello", 1, 0}, {"the", 1, 0}, {"printf", 1, 0}, {"file.txt", 1, 0}, {"google.com", 1, 0}, {"pdf", 1, 0},
    {"grep", 1, 0}, {"world", 1, 0}, {"don't", 1, 0}, {"HTTP", 1, 0}, {"GHBDTN", 1, 0}, {"abc123", 1, 0},
    {"kubectl", 1, 0}, {"strength", 1, 0},
    /* typed in the Russian layout */
    {"руддщ", 0, 1}, {"цщкдв", 0, 1}, {"еру", 0, 1}, {"ершы", 0, 1}, {"сщьзгеук", 0, 1}, {"цштвщц", 0, 1},
    {"привет", 0, 0}, {"днк", 0, 0}, {"хорошо", 0, 0}, {"компьютер", 0, 0}, {"спс", 0, 0}, {"молоко", 0, 0},
};

static int tab_convert(const ls_char *s, int n, ls_char *out, int to_ru)
{
    static ls_char en[96], ru[96];
    static int len;
    if (!len) {
        len = ls_from_utf8(TAB_EN, strlen(TAB_EN), en, 96);
        ls_from_utf8(TAB_RU, strlen(TAB_RU), ru, 96);
    }
    memcpy(out, s, (size_t)n * sizeof(ls_char));
    ls_map_text(out, n, to_ru ? en : ru, to_ru ? ru : en, len);
    return n;
}

int ls_selftest(char *report, int cap)
{
    int fails = 0, k = 0;
    report[0] = 0;
    for (size_t i = 0; i < sizeof CASES / sizeof CASES[0]; i++) {
        const tcase *t = &CASES[i];
        ls_char typed[MAXW], alt[MAXW];
        char alt8[MAXW * 3];
        int n = ls_from_utf8(t->typed, strlen(t->typed), typed, MAXW);
        tab_convert(typed, n, alt, t->cur_is_en);
        int got = t->cur_is_en ? ls_should_switch(typed, n, alt, n, 1) : ls_should_switch(alt, n, typed, n, 0);
        alt8[ls_to_utf8(alt, n, alt8, (int)sizeof alt8 - 1)] = 0;
        if (got != t->expect)
            fails++;
        if (k < cap - 1)
            k += snprintf(report + k, (size_t)(cap - k), "%s %-12s -> %-14s %s\n", got == t->expect ? "ok  " : "FAIL",
                          t->typed, alt8, got ? "switch" : "keep");
    }
    return fails;
}
