// Pointer validation helpers
#ifndef STEAMGPTK_UTIL_PTR_H
#define STEAMGPTK_UTIL_PTR_H

#include <stdint.h>

static inline int np_plausible_ptr(uint64_t v) {
    if (v < 0x100000000ULL)      return 0;  // below 4 GB (image/stack guard)
    if (v >= 0x800000000000ULL)  return 0;  // kernel space
    if (v & 0x7)                 return 0;  // not 8-byte aligned
    return 1;
}

#endif // STEAMGPTK_UTIL_PTR_H
