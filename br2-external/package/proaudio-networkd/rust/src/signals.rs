use std::sync::atomic::{AtomicBool, Ordering};

static STOP_REQUESTED: AtomicBool = AtomicBool::new(false);
static SETUP_REQUESTED: AtomicBool = AtomicBool::new(false);

const SIGINT: i32 = 2;
const SIGUSR1: i32 = 10;
const SIGTERM: i32 = 15;

unsafe extern "C" {
    fn signal(sig: i32, handler: usize) -> usize;
}

extern "C" fn signal_handler(sig: i32) {
    match sig {
        SIGUSR1 => SETUP_REQUESTED.store(true, Ordering::Relaxed),
        SIGINT | SIGTERM => STOP_REQUESTED.store(true, Ordering::Relaxed),
        _ => {}
    }
}

pub fn install() {
    unsafe {
        signal(SIGUSR1, signal_handler as usize);
        signal(SIGINT, signal_handler as usize);
        signal(SIGTERM, signal_handler as usize);
    }
}

pub fn stop_requested() -> bool {
    STOP_REQUESTED.load(Ordering::Relaxed)
}

pub fn request_stop() {
    STOP_REQUESTED.store(true, Ordering::Relaxed);
}

pub fn take_setup_request() -> bool {
    SETUP_REQUESTED.swap(false, Ordering::Relaxed)
}
