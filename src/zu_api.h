/* zu_api.h -- the function zu_api.c defines and init.c registers as the
   "zuint_get_api" callable (inst/include/zuint.h). */
#ifndef ZUINT_API_H
#define ZUINT_API_H

#include "zuint.h"

const zuint_api_v1 *zuint_get_api(uint32_t version);

#endif /* ZUINT_API_H */
