#include "ywf_inflate.h"
#include <string.h>
#include <zlib.h>

int ywf_inflate_raw(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_cap, size_t *dst_len) {
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
        return -1;
    }
    stream.next_in = (Bytef *)src;
    stream.avail_in = (uInt)src_len;
    stream.next_out = dst;
    stream.avail_out = (uInt)dst_cap;
    if (src_len > UINT32_MAX || dst_cap > UINT32_MAX) {
        inflateEnd(&stream);
        return -1;
    }
    int status = inflate(&stream, Z_FINISH);
    *dst_len = stream.total_out;
    inflateEnd(&stream);
    return status == Z_STREAM_END ? 0 : -1;
}
