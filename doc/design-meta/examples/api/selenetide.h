#ifndef SELENETIDE_H
#define SELENETIDE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

/* Contract only: implementations will be exported from Rust cdylib/staticlib.
 * Process-local opaque registry token: zero is invalid; tokens are never reused.
 * A token contains no Rust pointer and is never persisted or sent across processes.
 */
typedef uint64_t selenetide_session;
typedef struct selenetide_buffer {
    uint8_t *data;
    size_t len;
} selenetide_buffer;

enum selenetide_status {
    SELENETIDE_OK = 0,
    SELENETIDE_INVALID_ARGUMENT = 1,
    SELENETIDE_INVALID_SESSION = 2,
    SELENETIDE_REQUEST_FAILED = 3,
    SELENETIDE_INTERNAL_ERROR = 4
};

uint32_t selenetide_abi_version(void); /* returns 1 */
int32_t selenetide_session_open(const uint8_t *config_json, size_t config_len,
                              selenetide_session *out_session,
                              selenetide_buffer *out_json);
int32_t selenetide_session_call(selenetide_session session,
                              const uint8_t *request_json, size_t request_len,
                              selenetide_buffer *out_json);
int32_t selenetide_session_close(selenetide_session session,
                               selenetide_buffer *out_json);
void selenetide_buffer_free(selenetide_buffer buffer);

/* Inputs are borrowed only for the call and copied before background work.
 * Nonempty input needs a readable pointer; output pointers must be nonnull,
 * writable, aligned and nonaliasing. Caller owns their storage. Invalid pointer
 * provenance is a C caller contract violation, not a recoverable JSON error.
 * Initialize output buffer to {NULL,0}, and open's session to 0 before fallible
 * work. On success/failure JSON is returned when allocation permits; otherwise
 * an empty buffer plus nonzero status. Payload: UTF-8 SessionResponse, no NUL.
 * Each nonempty buffer is owned by Rust and freed exactly once with this API,
 * including error buffers and buffers retained after session_close.
 * Do not modify buffers or free them with a foreign allocator.
 * {NULL,0} may be freed. No panic or exception may unwind across this boundary.
 */
#ifdef __cplusplus
}
#endif
#endif
