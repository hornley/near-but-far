use snow::{params::NoiseParams, Builder, HandshakeState, TransportState};
use std::{
    panic::{catch_unwind, AssertUnwindSafe},
    ptr, slice,
};
use x25519_dalek::{PublicKey, StaticSecret};

const MAX: usize = 1024;

#[repr(i32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
/// Stable status values returned by every bridge operation.
pub enum NbfStatus {
    Ok = 0,
    InvalidArgument = 1,
    InvalidState = 2,
    BufferTooSmall = 3,
    AuthenticationFailed = 4,
    InternalError = 5,
}
const OK: i32 = NbfStatus::Ok as i32;
const INVALID: i32 = NbfStatus::InvalidArgument as i32;
const STATE: i32 = NbfStatus::InvalidState as i32;
const BUFFER: i32 = NbfStatus::BufferTooSmall as i32;
const AUTH: i32 = NbfStatus::AuthenticationFailed as i32;
const INTERNAL: i32 = NbfStatus::InternalError as i32;

/// Input bytes are borrowed only for the duration of the call.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct NbfBytes {
    pub ptr: *const u8,
    pub len: usize,
}
/// `ptr` and `written` must be valid, writable, and non-overlapping with all inputs and other outputs.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct NbfOutput {
    pub ptr: *mut u8,
    pub capacity: usize,
    pub written: *mut usize,
}
#[repr(C)]
pub struct NbfConfig {
    pub role: u32,
    pub mode: u32,
    pub local_private: NbfBytes,
    pub local_public: NbfBytes,
    pub expected_remote: NbfBytes,
    pub psk: NbfBytes,
    pub offer_id: NbfBytes,
}
pub struct NbfNoiseSession {
    inner: Session,
}
enum Noise {
    Handshake(HandshakeState),
    Transport(TransportState),
}
struct Session {
    role: u32,
    started: bool,
    closed: bool,
    noise: Option<Noise>,
    expected: Option<[u8; 32]>,
    peer: Option<[u8; 32]>,
    hash: Option<[u8; 32]>,
    messages: u8,
}

unsafe fn bytes<'a>(v: NbfBytes, exact: Option<usize>, max: usize) -> Result<&'a [u8], i32> {
    if v.len > max || exact.is_some_and(|n| n != v.len) || (v.len > 0 && v.ptr.is_null()) {
        return Err(INVALID);
    }
    Ok(if v.len == 0 {
        &[]
    } else {
        slice::from_raw_parts(v.ptr, v.len)
    })
}
unsafe fn validate_output(o: NbfOutput, min: usize) -> Result<(), i32> {
    if o.written.is_null()
        || (o.capacity > 0 && o.ptr.is_null())
        || o.capacity < min
        || o.capacity > MAX
    {
        return Err(BUFFER);
    }
    *o.written = 0;
    Ok(())
}
fn ffi(f: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(INTERNAL)
}
unsafe fn session<'a>(p: *mut NbfNoiseSession) -> Result<&'a mut Session, i32> {
    if p.is_null() {
        Err(INVALID)
    } else {
        Ok(&mut (*p).inner)
    }
}
fn ffi_session(p: *mut NbfNoiseSession, f: impl FnOnce() -> i32) -> i32 {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(v) => v,
        Err(_) => {
            unsafe {
                if let Ok(s) = session(p) {
                    poison(s)
                }
            }
            INTERNAL
        }
    }
}
fn poison(s: &mut Session) {
    s.noise = None;
    s.closed = true
}
fn state_failure(s: &mut Session) -> i32 {
    poison(s);
    STATE
}
fn finish(s: &mut Session) -> Result<(), i32> {
    let hs = match s.noise.take() {
        Some(Noise::Handshake(h)) => h,
        _ => return Err(STATE),
    };
    let remote = hs.get_remote_static().ok_or(AUTH)?;
    if remote.len() != 32 {
        return Err(AUTH);
    }
    if s.expected.is_some_and(|k| k.as_slice() != remote) {
        return Err(AUTH);
    }
    let hash = hs.get_handshake_hash();
    if hash.len() != 32 {
        return Err(INTERNAL);
    }
    let mut peer = [0; 32];
    peer.copy_from_slice(remote);
    let mut sid = [0; 32];
    sid.copy_from_slice(hash);
    let transport = hs.into_transport_mode().map_err(|_| INTERNAL)?;
    s.peer = Some(peer);
    s.hash = Some(sid);
    s.noise = Some(Noise::Transport(transport));
    Ok(())
}

#[no_mangle]
pub unsafe extern "C" fn nbf_session_new(
    c: *const NbfConfig,
    out: *mut *mut NbfNoiseSession,
) -> i32 {
    ffi(|| {
        if c.is_null() || out.is_null() {
            return INVALID;
        }
        *out = ptr::null_mut();
        let c = &*c;
        if !((c.role == 1 || c.role == 2) && (c.mode == 1 || c.mode == 2)) {
            return INVALID;
        }
        let local = match bytes(c.local_private, Some(32), 32) {
            Ok(v) => v,
            Err(e) => return e,
        };
        let local_pub = match bytes(c.local_public, Some(32), 32) {
            Ok(v) => v,
            Err(e) => return e,
        };
        let expected = match bytes(c.expected_remote, None, 32) {
            Ok(v) => v,
            Err(e) => return e,
        };
        let psk = match bytes(c.psk, None, 32) {
            Ok(v) => v,
            Err(e) => return e,
        };
        let offer = match bytes(c.offer_id, None, 16) {
            Ok(v) => v,
            Err(e) => return e,
        };
        if (!expected.is_empty() && expected.len() != 32)
            || (c.mode == 1 && (psk.len() != 32 || offer.len() != 16))
            || (c.mode == 2 && (!psk.is_empty() || !offer.is_empty() || expected.len() != 32))
        {
            return INVALID;
        }
        if c.mode == 1
            && ((c.role == 1 && expected.len() != 32) || (c.role == 2 && !expected.is_empty()))
        {
            return INVALID;
        }
        let mut prologue = if c.mode == 1 {
            b"NBFPAIR1".to_vec()
        } else {
            b"NBFRECN1".to_vec()
        };
        if c.mode == 1 {
            prologue.extend_from_slice(offer);
            prologue.extend_from_slice(if c.role == 1 { expected } else { local_pub });
        } else if c.role == 1 {
            prologue.extend_from_slice(expected);
            prologue.extend_from_slice(local_pub)
        } else {
            prologue.extend_from_slice(local_pub);
            prologue.extend_from_slice(expected)
        }
        let name = if c.mode == 1 {
            "Noise_XXpsk3_25519_ChaChaPoly_BLAKE2s"
        } else {
            "Noise_XX_25519_ChaChaPoly_BLAKE2s"
        };
        let params: NoiseParams = match name.parse() {
            Ok(v) => v,
            Err(_) => return INTERNAL,
        };
        let b = match Builder::new(params).local_private_key(local) {
            Ok(v) => v,
            Err(_) => return INVALID,
        };
        let mut b = match b.prologue(&prologue) {
            Ok(v) => v,
            Err(_) => return INVALID,
        };
        if c.mode == 1 {
            let key: &[u8; 32] = match psk.try_into() {
                Ok(v) => v,
                Err(_) => return INVALID,
            };
            b = match b.psk(3, key) {
                Ok(v) => v,
                Err(_) => return INVALID,
            }
        }
        let derived = PublicKey::from(&StaticSecret::from(<[u8; 32]>::try_from(local).unwrap()));
        if derived.as_bytes().as_slice() != local_pub {
            return INVALID;
        }
        let hs = match if c.role == 1 {
            b.build_initiator()
        } else {
            b.build_responder()
        } {
            Ok(v) => v,
            Err(_) => return INTERNAL,
        };
        let exp = if expected.len() == 32 {
            let mut k = [0; 32];
            k.copy_from_slice(expected);
            Some(k)
        } else {
            None
        };
        *out = Box::into_raw(Box::new(NbfNoiseSession {
            inner: Session {
                role: c.role,
                started: false,
                closed: false,
                noise: Some(Noise::Handshake(hs)),
                expected: exp,
                peer: None,
                hash: None,
                messages: 0,
            },
        }));
        OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn nbf_session_start(
    p: *mut NbfNoiseSession,
    o: NbfOutput,
    finished: *mut u32,
) -> i32 {
    ffi_session(p, || {
        if finished.is_null() {
            return INVALID;
        }
        let s = match session(p) {
            Ok(v) => v,
            Err(e) => return e,
        };
        if s.closed {
            return STATE;
        }
        if s.started {
            return state_failure(s);
        }
        if let Err(e) = validate_output(o, if s.role == 1 { MAX } else { 0 }) {
            return e;
        }
        let out = if o.capacity == 0 {
            &mut []
        } else {
            slice::from_raw_parts_mut(o.ptr, o.capacity)
        };
        s.started = true;
        if s.role == 1 {
            let hs = match s.noise.as_mut() {
                Some(Noise::Handshake(h)) => h,
                _ => return state_failure(s),
            };
            let n = match hs.write_message(&[], out) {
                Ok(n) => n,
                Err(_) => {
                    poison(s);
                    return AUTH;
                }
            };
            *o.written = n;
            s.messages = 1;
        }
        *finished = 0;
        OK
    })
}

#[no_mangle]
/// `peer` and `hash` must each reference 32 writable bytes, distinct from one another and all other buffers.
pub unsafe extern "C" fn nbf_session_receive(
    p: *mut NbfNoiseSession,
    input: NbfBytes,
    o: NbfOutput,
    finished: *mut u32,
    peer: NbfOutput,
    hash: NbfOutput,
) -> i32 {
    ffi_session(p, || {
        if finished.is_null() {
            return INVALID;
        }
        let s = match session(p) {
            Ok(v) => v,
            Err(e) => return e,
        };
        if s.closed {
            return STATE;
        }
        if let Err(e) = validate_output(o, MAX) {
            return e;
        }
        if let Err(e) = validate_output(peer, 32) {
            return e;
        }
        if let Err(e) = validate_output(hash, 32) {
            return e;
        }
        if !s.started || s.noise.is_none() {
            return state_failure(s);
        }
        if input.len == 0 || input.len > MAX || input.ptr.is_null() {
            poison(s);
            return INVALID;
        }
        let data = slice::from_raw_parts(input.ptr, input.len);
        let out = if o.capacity == 0 {
            &mut []
        } else {
            slice::from_raw_parts_mut(o.ptr, o.capacity)
        };
        let mut plaintext = [0u8; MAX];
        let hs = match s.noise.as_mut() {
            Some(Noise::Handshake(h)) => h,
            _ => return state_failure(s),
        };
        if hs.read_message(data, &mut plaintext).is_err() {
            poison(s);
            return AUTH;
        }
        s.messages += 1;
        // The initiator learns the responder key in message 2 and must pin it before revealing its static key in message 3.
        if s.role == 1
            && s.messages == 2
            && s.expected
                .is_some_and(|k| hs.get_remote_static() != Some(k.as_slice()))
        {
            poison(s);
            return AUTH;
        }
        let done = hs.is_handshake_finished();
        if !done {
            let n = match hs.write_message(&[], out) {
                Ok(n) => n,
                Err(_) => {
                    poison(s);
                    return AUTH;
                }
            };
            *o.written = n;
            s.messages += 1;
        }
        if done || matches!(s.role, 1) && s.messages == 3 {
            if let Err(e) = finish(s) {
                poison(s);
                return e;
            }
            let a = s.peer.unwrap();
            let b = s.hash.unwrap();
            ptr::copy_nonoverlapping(a.as_ptr(), peer.ptr, 32);
            ptr::copy_nonoverlapping(b.as_ptr(), hash.ptr, 32);
            *peer.written = 32;
            *hash.written = 32;
            *finished = 1;
        } else {
            *finished = 0
        }
        OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn nbf_session_peer(
    p: *mut NbfNoiseSession,
    peer: NbfOutput,
    hash: NbfOutput,
) -> i32 {
    ffi_session(p, || {
        let s = match session(p) {
            Ok(v) => v,
            Err(e) => return e,
        };
        if s.closed {
            return STATE;
        }
        if s.peer.is_none() {
            return state_failure(s);
        }
        if let Err(e) = validate_output(peer, 32) {
            return e;
        }
        if let Err(e) = validate_output(hash, 32) {
            return e;
        }
        ptr::copy_nonoverlapping(s.peer.unwrap().as_ptr(), peer.ptr, 32);
        ptr::copy_nonoverlapping(s.hash.unwrap().as_ptr(), hash.ptr, 32);
        *peer.written = 32;
        *hash.written = 32;
        OK
    })
}
#[no_mangle]
pub unsafe extern "C" fn nbf_session_seal(
    p: *mut NbfNoiseSession,
    i: NbfBytes,
    o: NbfOutput,
) -> i32 {
    ffi_session(p, || {
        let data = match bytes(i, None, MAX - 16) {
            Ok(v) => v,
            Err(e) => return e,
        };
        let s = match session(p) {
            Ok(v) => v,
            Err(e) => return e,
        };
        if s.closed {
            return STATE;
        }
        if s.peer.is_none() {
            return state_failure(s);
        }
        if let Err(e) = validate_output(o, data.len() + 16) {
            return e;
        }
        let out = if o.capacity == 0 {
            &mut []
        } else {
            slice::from_raw_parts_mut(o.ptr, o.capacity)
        };
        let t = match s.noise.as_mut() {
            Some(Noise::Transport(v)) => v,
            _ => return state_failure(s),
        };
        match t.write_message(data, out) {
            Ok(n) => {
                *o.written = n;
                OK
            }
            Err(_) => {
                poison(s);
                AUTH
            }
        }
    })
}
#[no_mangle]
pub unsafe extern "C" fn nbf_session_open(
    p: *mut NbfNoiseSession,
    i: NbfBytes,
    o: NbfOutput,
) -> i32 {
    ffi_session(p, || {
        let s = match session(p) {
            Ok(v) => v,
            Err(e) => return e,
        };
        if s.closed {
            return STATE;
        }
        if let Err(e) = validate_output(o, 0) {
            return e;
        }
        if s.peer.is_none() {
            return state_failure(s);
        }
        if i.len < 16 || i.len > MAX || i.ptr.is_null() {
            poison(s);
            return INVALID;
        }
        let data = slice::from_raw_parts(i.ptr, i.len);
        if let Err(e) = validate_output(o, data.len() - 16) {
            return e;
        }
        let out = if o.capacity == 0 {
            &mut []
        } else {
            slice::from_raw_parts_mut(o.ptr, o.capacity)
        };
        let t = match s.noise.as_mut() {
            Some(Noise::Transport(v)) => v,
            _ => return state_failure(s),
        };
        match t.read_message(data, out) {
            Ok(n) => {
                *o.written = n;
                OK
            }
            Err(_) => {
                poison(s);
                AUTH
            }
        }
    })
}
#[no_mangle]
pub unsafe extern "C" fn nbf_session_close(p: *mut NbfNoiseSession) -> i32 {
    ffi_session(p, || {
        let s = match session(p) {
            Ok(v) => v,
            Err(e) => return e,
        };
        s.closed = true;
        s.noise = None;
        OK
    })
}
#[no_mangle]
pub unsafe extern "C" fn nbf_session_free(p: *mut NbfNoiseSession) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !p.is_null() {
            drop(Box::from_raw(p))
        }
    }));
}

#[cfg(test)]
mod tests {
    use super::*;
    use x25519_dalek::{PublicKey, StaticSecret};

    fn public(private: &[u8; 32]) -> [u8; 32] {
        *PublicKey::from(&StaticSecret::from(*private)).as_bytes()
    }
    fn make(
        role: u32,
        mode: u32,
        private: &[u8; 32],
        local: &[u8; 32],
        remote: &[u8],
        psk: &[u8],
        offer: &[u8],
    ) -> *mut NbfNoiseSession {
        let c = NbfConfig {
            role,
            mode,
            local_private: NbfBytes {
                ptr: private.as_ptr(),
                len: 32,
            },
            local_public: NbfBytes {
                ptr: local.as_ptr(),
                len: 32,
            },
            expected_remote: NbfBytes {
                ptr: remote.as_ptr(),
                len: remote.len(),
            },
            psk: NbfBytes {
                ptr: psk.as_ptr(),
                len: psk.len(),
            },
            offer_id: NbfBytes {
                ptr: offer.as_ptr(),
                len: offer.len(),
            },
        };
        let mut p = ptr::null_mut();
        assert_eq!(
            unsafe { nbf_session_new(&c, &mut p) },
            OK,
            "role={role} mode={mode}"
        );
        p
    }
    fn start(p: *mut NbfNoiseSession) -> Vec<u8> {
        let mut out = [0; MAX];
        let mut n = 0;
        let mut finished = 9;
        let o = NbfOutput {
            ptr: out.as_mut_ptr(),
            capacity: out.len(),
            written: &mut n,
        };
        assert_eq!(unsafe { nbf_session_start(p, o, &mut finished) }, OK);
        assert_eq!(finished, 0);
        out[..n].to_vec()
    }
    fn receive(p: *mut NbfNoiseSession, input: &[u8]) -> (i32, Vec<u8>, u32, [u8; 32], [u8; 32]) {
        let mut out = [0; MAX];
        let mut n = 0;
        let mut finished = 0;
        let mut peer = [0; 32];
        let mut peer_written = 0;
        let mut hash = [0; 32];
        let mut hash_written = 0;
        let i = NbfBytes {
            ptr: input.as_ptr(),
            len: input.len(),
        };
        let o = NbfOutput {
            ptr: out.as_mut_ptr(),
            capacity: out.len(),
            written: &mut n,
        };
        let peer_out = NbfOutput {
            ptr: peer.as_mut_ptr(),
            capacity: peer.len(),
            written: &mut peer_written,
        };
        let hash_out = NbfOutput {
            ptr: hash.as_mut_ptr(),
            capacity: hash.len(),
            written: &mut hash_written,
        };
        let status = unsafe { nbf_session_receive(p, i, o, &mut finished, peer_out, hash_out) };
        (status, out[..n].to_vec(), finished, peer, hash)
    }
    fn handshake(
        mode: u32,
        psk_phone: &[u8],
        psk_mac: &[u8],
    ) -> (
        *mut NbfNoiseSession,
        *mut NbfNoiseSession,
        [u8; 32],
        [u8; 32],
    ) {
        let phone_sk = [1; 32];
        let mac_sk = [2; 32];
        let phone_pk = public(&phone_sk);
        let mac_pk = public(&mac_sk);
        let offer = if mode == 1 { &[8; 16][..] } else { &[][..] };
        let phone = make(1, mode, &phone_sk, &phone_pk, &mac_pk, psk_phone, &offer);
        let mac_remote = if mode == 1 { &[][..] } else { &phone_pk[..] };
        let mac = make(2, mode, &mac_sk, &mac_pk, mac_remote, psk_mac, &offer);
        let _ = start(mac);
        let m1 = start(phone);
        let (st, m2, _, _, _) = receive(mac, &m1);
        assert_eq!(st, OK);
        let (st, m3, phone_done, peer, phone_hash) = receive(phone, &m2);
        assert_eq!(st, OK);
        assert_eq!(phone_done, 1);
        assert_eq!(peer, mac_pk);
        let (st, _, mac_done, peer2, mac_hash) = receive(mac, &m3);
        assert_eq!(st, OK);
        assert_eq!(mac_done, 1);
        assert_eq!(peer2, phone_pk);
        assert_eq!(phone_hash, mac_hash);
        (phone, mac, phone_pk, mac_pk)
    }
    fn seal(p: *mut NbfNoiseSession, plain: &[u8]) -> Vec<u8> {
        let mut out = [0; MAX];
        let mut n = 0;
        let i = NbfBytes {
            ptr: plain.as_ptr(),
            len: plain.len(),
        };
        let o = NbfOutput {
            ptr: out.as_mut_ptr(),
            capacity: out.len(),
            written: &mut n,
        };
        assert_eq!(unsafe { nbf_session_seal(p, i, o) }, OK);
        out[..n].to_vec()
    }
    fn open(p: *mut NbfNoiseSession, cipher: &[u8]) -> (i32, Vec<u8>) {
        let mut out = [0; MAX];
        let mut n = 0;
        let i = NbfBytes {
            ptr: cipher.as_ptr(),
            len: cipher.len(),
        };
        let o = NbfOutput {
            ptr: out.as_mut_ptr(),
            capacity: out.len(),
            written: &mut n,
        };
        let status = unsafe { nbf_session_open(p, i, o) };
        (status, out[..n].to_vec())
    }
    fn free(p: *mut NbfNoiseSession) {
        unsafe { nbf_session_free(p) }
    }

    #[test]
    fn fixed_enrollment_and_reconnect_handshakes_and_transport() {
        for mode in [1, 2] {
            let secret = if mode == 1 { &[7; 32][..] } else { &[] };
            let (phone, mac, _, _) = handshake(mode, secret, secret);
            let record = seal(phone, b"ordered authenticated record");
            assert_eq!(
                open(mac, &record),
                (OK, b"ordered authenticated record".to_vec())
            );
            assert_eq!(open(mac, &record).0, AUTH);
            unsafe {
                nbf_session_close(phone);
                nbf_session_close(phone);
            }
            free(phone);
            free(mac);
        }
    }

    #[test]
    fn short_buffers_fail_before_handshake_or_transport_state_advances() {
        let phone_sk = [11; 32];
        let mac_sk = [12; 32];
        let phone_pk = public(&phone_sk);
        let mac_pk = public(&mac_sk);
        let offer = [13; 16];
        let psk = [14; 32];
        let phone = make(1, 1, &phone_sk, &phone_pk, &mac_pk, &psk, &offer);
        let mac = make(2, 1, &mac_sk, &mac_pk, &[], &psk, &offer);
        let mut tiny = [0; 1];
        let mut n = 0;
        let mut done = 0;
        let tiny_output = NbfOutput {
            ptr: tiny.as_mut_ptr(),
            capacity: 1,
            written: &mut n,
        };
        assert_eq!(
            unsafe { nbf_session_start(phone, tiny_output, &mut done) },
            BUFFER
        );
        assert_eq!(n, 0);
        let _ = start(mac);
        let m1 = start(phone);
        let (status, m2, _, _, _) = receive(mac, &m1);
        assert_eq!(status, OK);
        let (status, m3, _, _, _) = receive(phone, &m2);
        assert_eq!(status, OK);
        let (status, _, _, _, _) = receive(mac, &m3);
        assert_eq!(status, OK);

        let record = seal(phone, b"capacity check");
        let mut too_small = [0; 2];
        let mut written = 0;
        let input = NbfBytes {
            ptr: record.as_ptr(),
            len: record.len(),
        };
        let output = NbfOutput {
            ptr: too_small.as_mut_ptr(),
            capacity: too_small.len(),
            written: &mut written,
        };
        assert_eq!(unsafe { nbf_session_open(mac, input, output) }, BUFFER);
        assert_eq!(open(mac, &record), (OK, b"capacity check".to_vec()));
        free(phone);
        free(mac);
    }

    #[test]
    fn malformed_handshake_and_transport_records_poison_the_active_handle() {
        let phone_sk = [21; 32];
        let mac_sk = [22; 32];
        let phone_pk = public(&phone_sk);
        let mac_pk = public(&mac_sk);
        let offer = [23; 16];
        let psk = [24; 32];

        for record in [Vec::new(), vec![0; MAX + 1]] {
            let phone = make(1, 1, &phone_sk, &phone_pk, &mac_pk, &psk, &offer);
            let mac = make(2, 1, &mac_sk, &mac_pk, &[], &psk, &offer);
            let _ = start(mac);
            let m1 = start(phone);
            assert_eq!(receive(mac, &record).0, INVALID);
            assert_eq!(receive(mac, &m1).0, STATE);
            free(phone);
            free(mac);
        }

        for record in [Vec::new(), vec![0; MAX + 1]] {
            let (phone, mac, _, _) = handshake(2, &[], &[]);
            let valid = seal(phone, b"after malformed input");
            assert_eq!(open(mac, &record).0, INVALID);
            assert_eq!(open(mac, &valid).0, STATE);
            free(phone);
            free(mac);
        }
    }

    #[test]
    fn wrong_psk_is_rejected_and_wrong_mac_pin_emits_no_message_three() {
        let phone_sk = [1; 32];
        let mac_sk = [2; 32];
        let phone_pk = public(&phone_sk);
        let mac_pk = public(&mac_sk);
        let offer = [8; 16];
        let psk = [7; 32];
        let wrong_psk = [9; 32];
        let phone = make(1, 1, &phone_sk, &phone_pk, &mac_pk, &psk, &offer);
        let mac = make(2, 1, &mac_sk, &mac_pk, &[], &wrong_psk, &offer);
        let _ = start(mac);
        let m1 = start(phone);
        let (st, m2, _, _, _) = receive(mac, &m1);
        assert_eq!(st, OK);
        let (st, m3, done, _, _) = receive(phone, &m2);
        assert_eq!(st, OK);
        assert_eq!(done, 1);
        // The responder detects the wrong one-use PSK while authenticating message 3.
        assert_eq!(receive(mac, &m3).0, AUTH);
        free(phone);
        free(mac);

        let phone_sk = [3; 32];
        let real_mac_sk = [4; 32];
        let rogue_sk = [5; 32];
        let psk = [6; 32];
        let offer = [10; 16];
        let expected = public(&real_mac_sk);
        let phone_pk = public(&phone_sk);
        let rogue_pk = public(&rogue_sk);
        let phone = make(1, 1, &phone_sk, &phone_pk, &expected, &psk, &offer);
        let m1 = start(phone);
        let mut prologue = b"NBFPAIR1".to_vec();
        prologue.extend_from_slice(&offer);
        prologue.extend_from_slice(&expected);
        let params: NoiseParams = "Noise_XXpsk3_25519_ChaChaPoly_BLAKE2s".parse().unwrap();
        let mut responder = Builder::new(params)
            .local_private_key(&rogue_sk)
            .unwrap()
            .prologue(&prologue)
            .unwrap()
            .psk(3, &psk)
            .unwrap()
            .build_responder()
            .unwrap();
        let mut payload = [0; MAX];
        let _ = responder.read_message(&m1, &mut payload).unwrap();
        let mut m2 = [0; MAX];
        let n = responder.write_message(&[], &mut m2).unwrap();
        assert_ne!(rogue_pk, expected);
        let (status, out, _, _, _) = receive(phone, &m2[..n]);
        assert_eq!(status, AUTH);
        assert!(out.is_empty());
        free(phone);
    }
}
