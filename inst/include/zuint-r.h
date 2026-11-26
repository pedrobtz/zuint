/* zuint-r.h -- how an R package gets zuint's C table.
 *
 * Include this, not zuint.h, in a package that resolves the table. It
 * includes zuint.h and R's headers, and adds zuint_api(). Code that is only
 * handed the pointer includes zuint.h alone.
 *
 * LinkingTo supplies headers, not object code, and nothing links across
 * installed packages, so the table reaches you through R's registered
 * C-callable mechanism: one versioned table, one lookup.
 *
 *     #include <zuint-r.h>
 *
 *     const zuint_api_v1 *api = zuint_api();
 *     if (api == NULL) { ... this zuint has another ABI version ... }
 *     zuint_i128 c;
 *     int status = api->dec_parse("1.50", 4, 10, 2, &c);
 *
 * DESCRIPTION needs both
 *
 *     Imports:   zuint   # loads the DLL that registers the callable
 *     LinkingTo: zuint   # these headers
 *
 * and NAMESPACE a real import directive, such as importFrom(zuint, int128):
 * that is what Writing R Extensions documents as loading an imported
 * package's namespace, and so its DLL, before yours.
 */
#ifndef ZUINT_R_H
#define ZUINT_R_H

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

#include "zuint.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Resolves the table on first use and caches it.
 *
 * Call it on R's main thread only: R_GetCCallable() is R API and the cache
 * is a plain static. Resolve the table there, at load say, and hand the
 * pointer to other threads; every member may then run on any thread
 * (zuint.h).
 *
 * zuint's DLL must already be loaded (the Imports and importFrom above).
 * If it is not, R_GetCCallable() raises an R error and does not return, so
 * call this where an R error is safe: from R_init_<pkg>, or a .Call entry
 * point before it holds a native resource.
 *
 * NULL when the loaded zuint serves another ABI version, or a table smaller
 * than this header's (an older zuint, without the members appended since).
 * A NULL is not cached, so a later call asks again.
 *
 * `static inline`, so that a translation unit that includes this header
 * without calling it gets no unused-function warning. */
static inline const zuint_api_v1 *zuint_api(void)
{
    static const zuint_api_v1 *cached = NULL;
    if (cached == NULL) {
        /* R_GetCCallable() returns DL_FUNC. Going through a union, not a
           cast, keeps -Wcast-function-type quiet in a consumer's build. */
        union {
            DL_FUNC fn;
            zuint_get_api_fn get;
        } resolve;
        resolve.fn = R_GetCCallable("zuint", "zuint_get_api");
        if (resolve.fn != NULL) {
            const zuint_api_v1 *api = resolve.get((uint32_t)ZUINT_ABI_VERSION);
            if (api != NULL && api->struct_size >= (uint32_t)sizeof(zuint_api_v1)) cached = api;
        }
    }
    return cached;
}

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* ZUINT_R_H */
