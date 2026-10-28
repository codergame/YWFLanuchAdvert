#ifndef YWF_INFLATE_H
#define YWF_INFLATE_H

#include <stddef.h>
#include <stdint.h>

int ywf_inflate_raw(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_cap, size_t *dst_len);

#endif
