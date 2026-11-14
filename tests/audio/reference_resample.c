/* Independent 8 -> 16 -> 8 kHz PCM reference using the conference's filters. */
#include <pjlib.h>
#include <pjmedia/resample.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    pj_caching_pool cp;
    pj_pool_t *pool;
    pjmedia_resample *up, *down;
    pj_int16_t in[160], middle[320], out[160];
    FILE *input, *output;
    if (argc != 3 || pj_init() != PJ_SUCCESS) return 1;
    pj_caching_pool_init(&cp, NULL, 0);
    pool = pj_pool_create(&cp.factory, "reference", 4096, 4096, NULL);
    if (!pool) return 1;
    if (pjmedia_resample_create(pool, PJ_TRUE, PJ_TRUE, 1, 8000, 16000,
                               160, &up) != PJ_SUCCESS) return 1;
    if (pjmedia_resample_create(pool, PJ_TRUE, PJ_TRUE, 1, 16000, 8000,
                               320, &down) != PJ_SUCCESS) return 1;
    input = fopen(argv[1], "rb");
    output = fopen(argv[2], "wb");
    if (!input || !output) return 1;
    while (fread(in, sizeof(*in), 160, input) == 160) {
        pjmedia_resample_run(up, in, middle);
        pjmedia_resample_run(down, middle, out);
        if (fwrite(out, sizeof(*out), 160, output) != 160) return 1;
    }
    fclose(input);
    fclose(output);
    pj_pool_release(pool);
    pj_caching_pool_destroy(&cp);
    pj_shutdown();
    return 0;
}
