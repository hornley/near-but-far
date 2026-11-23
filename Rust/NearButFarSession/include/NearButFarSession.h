#ifndef NEAR_BUT_FAR_SESSION_H
#define NEAR_BUT_FAR_SESSION_H

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>

/**
 * Stable status values returned by every bridge operation.
 */
enum NbfStatus
#ifdef __cplusplus
  : int32_t
#endif // __cplusplus
 {
  Ok = 0,
  InvalidArgument = 1,
  InvalidState = 2,
  BufferTooSmall = 3,
  AuthenticationFailed = 4,
  InternalError = 5,
};
#ifndef __cplusplus
typedef int32_t NbfStatus;
#endif // __cplusplus

typedef struct NbfNoiseSession NbfNoiseSession;

/**
 * Input bytes are borrowed only for the duration of the call.
 */
typedef struct NbfBytes {
  const uint8_t *ptr;
  size_t len;
} NbfBytes;

typedef struct NbfConfig {
  uint32_t role;
  uint32_t mode;
  struct NbfBytes local_private;
  struct NbfBytes local_public;
  struct NbfBytes expected_remote;
  struct NbfBytes psk;
  struct NbfBytes offer_id;
} NbfConfig;

/**
 * `ptr` and `written` must be valid, writable, and non-overlapping with all inputs and other outputs.
 */
typedef struct NbfOutput {
  uint8_t *ptr;
  size_t capacity;
  size_t *written;
} NbfOutput;

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

int32_t nbf_session_new(const struct NbfConfig *c, struct NbfNoiseSession **out);

int32_t nbf_session_start(struct NbfNoiseSession *p, struct NbfOutput o, uint32_t *finished);

/**
 * `peer` and `hash` must each reference 32 writable bytes, distinct from one another and all other buffers.
 */
int32_t nbf_session_receive(struct NbfNoiseSession *p,
                            struct NbfBytes input,
                            struct NbfOutput o,
                            uint32_t *finished,
                            struct NbfOutput peer,
                            struct NbfOutput hash);

int32_t nbf_session_peer(struct NbfNoiseSession *p, struct NbfOutput peer, struct NbfOutput hash);

int32_t nbf_session_seal(struct NbfNoiseSession *p, struct NbfBytes i, struct NbfOutput o);

int32_t nbf_session_open(struct NbfNoiseSession *p, struct NbfBytes i, struct NbfOutput o);

int32_t nbf_session_close(struct NbfNoiseSession *p);

void nbf_session_free(struct NbfNoiseSession *p);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* NEAR_BUT_FAR_SESSION_H */
