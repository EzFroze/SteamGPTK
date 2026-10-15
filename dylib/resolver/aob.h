// AOB pattern scanner
#ifndef STEAMGPTK_RESOLVER_AOB_H
#define STEAMGPTK_RESOLVER_AOB_H

#include <stdint.h>
#include <stddef.h>

// A compiled byte pattern with per-byte mask (0xFF = match, 0x00 = wildcard).
typedef struct {
    uint8_t *bytes;
    uint8_t *mask;
    int      length;
} np_byte_pattern_t;

// Hex string like "AB ?? CD 01" into a compiled pattern.
int np_compile_pattern(const char *hex_str, np_byte_pattern_t *out);

void np_release_pattern(np_byte_pattern_t *pat);

// The sole match of `pat` in `size` bytes at `base`, or 0 when zero or
// multiple matches exist.
uintptr_t np_scan_sole_match(uintptr_t base, size_t size, const np_byte_pattern_t *pat);

#endif // STEAMGPTK_RESOLVER_AOB_H
