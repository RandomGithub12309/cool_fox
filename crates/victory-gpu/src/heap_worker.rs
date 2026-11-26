//! The pass that uploads textures picked by index, on a thread of its own
//! (`VICTORY_HEAP_WORKER`; on unless `0`, requires `VICTORY_LATE_WAIT`).
//!
//! `draw::State::heap_textures` normally runs synchronously on whichever title
//! thread records the first shader that picks textures by index, blocking it
//! while scanning due slots, querying page mappings, staging and recording
//! uploads. With this worker, recording threads wake `"victory-heap"` in ~200 ns
//! and keep recording draws, while our worker runs the pass off-thread, detiles
//! ahead with AES-NI hashing, and hands finished upload lists to the next
//! submission (`take_ready`). Decoration bake passes take priority via `urgent`.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering::Relaxed};
use std::sync::{Condvar, Mutex, MutexGuard, OnceLock};

use crate::descriptor::Heap;
use crate::host::HostList;
use crate::object::This;

/// Whether the pass runs on its own thread now (on unless `VICTORY_HEAP_WORKER=0`).
pub(crate) fn on() -> bool {
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| std::env::var_os("VICTORY_HEAP_WORKER").is_none_or(|v| v != "0")) && crate::host::late()
}

/// Nanoseconds busy, nanoseconds detiling, lists handed over, slots published,
/// slots rewritten before publish, textures left for submission.
pub(crate) static STATS: [AtomicU64; 6] = [const { AtomicU64::new(0) }; 6];

/// Flush an upload list once it accumulates enough bytes or elapsed time so
/// streamed textures appear promptly.
const LIST_BYTES: u64 = 48 << 20;
const LIST_MS: u128 = 40;

pub(crate) struct Publish {
    heap: usize,
    index: u32,
    handle: u64,
    key: u64,
}

struct HeldHeap(This);
// SAFETY: reference-counted title object; only the atomic refcount and
// mutex-guarded host heap state are touched from the worker.
unsafe impl Send for HeldHeap {}

impl HeldHeap {
    fn new(heap: &Heap) -> Self {
        let this = std::ptr::from_ref(heap).cast();
        crate::object::add_ref(this);
        HeldHeap(this)
    }

    fn heap(&self) -> &Heap {
        crate::descriptor::heap(self.0)
    }
}

impl Drop for HeldHeap {
    fn drop(&mut self) {
        crate::object::release_boxed::<Heap>(self.0);
    }
}

struct Ready {
    list: HostList,
    publish: Vec<Publish>,
    _heap: HeldHeap,
}
// SAFETY: closed D3D12 command list; untouched until taken by the submit thread.
unsafe impl Send for Ready {}

static READY: Mutex<Vec<Ready>> = Mutex::new(Vec::new());

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

pub(crate) struct Batch {
    heap: This,
    list: Option<HostList>,
    publish: Vec<Publish>,
    bytes: u64,
    began: std::time::Instant,
}

impl Batch {
    fn new(heap: &Heap) -> Self {
        Batch {
            heap: std::ptr::from_ref(heap).cast(),
            list: None,
            publish: Vec::new(),
            bytes: 0,
            began: std::time::Instant::now(),
        }
    }

    pub(crate) fn list(&mut self) -> Option<&HostList> {
        if self.list.is_none() {
            self.list = crate::list::fresh_list();
            self.began = std::time::Instant::now();
        }
        self.list.as_ref()
    }

    pub(crate) fn publish(&mut self, index: u32, handle: u64, key: u64) {
        self.publish.push(Publish { heap: self.heap as usize, index, handle, key });
    }

    pub(crate) fn uploaded(&mut self, bytes: u64) {
        self.bytes += bytes;
        if self.bytes >= LIST_BYTES || self.began.elapsed().as_millis() >= LIST_MS {
            self.flush();
        }
    }

    fn flush(&mut self) {
        self.bytes = 0;
        let publish = std::mem::take(&mut self.publish);
        let Some(list) = self.list.take() else {
            return;
        };
        let started = std::time::Instant::now();
        let left = list.refresh_textures_ahead();
        STATS[1].fetch_add(started.elapsed().as_nanos() as u64, Relaxed);
        STATS[5].fetch_add(left, Relaxed);
        list.close();
        let heap = HeldHeap::new(crate::descriptor::heap(self.heap));
        lock(&READY).push(Ready { list, publish, _heap: heap });
    }
}

impl Drop for Batch {
    fn drop(&mut self) {
        self.flush();
    }
}

/// Returns finished background upload lists to prepend to the next submission,
/// publishing their host descriptor slots first.
pub(crate) fn take_ready() -> Vec<HostList> {
    if JOB.get().is_none() {
        return Vec::new();
    }
    let ready = std::mem::take(&mut *lock(&READY));
    STATS[2].fetch_add(ready.len() as u64, Relaxed);
    ready
        .into_iter()
        .map(|r| {
            for p in &r.publish {
                let Some(host) = crate::descriptor::heap(p.heap as This).host() else {
                    continue;
                };
                let shown = host.publish(p.index, p.handle, p.key);
                STATS[if shown { 3 } else { 4 }].fetch_add(1, Relaxed);
            }
            r.list
        })
        .collect()
}

struct Job {
    heap: Mutex<Option<HeldHeap>>,
    wake: Condvar,
}

static JOB: OnceLock<Job> = OnceLock::new();
static PASS: Mutex<()> = Mutex::new(());
static URGENT: AtomicBool = AtomicBool::new(false);

/// Wakes the background heap texture worker for `heap`. Returns `false` if the
/// worker is disabled or unavailable so the caller runs the pass inline.
pub(crate) fn kick(heap: &Heap) -> bool {
    if !on() {
        return false;
    }
    static STARTED: OnceLock<bool> = OnceLock::new();
    let started = *STARTED.get_or_init(|| {
        JOB.get_or_init(|| Job { heap: Mutex::new(None), wake: Condvar::new() });
        match std::thread::Builder::new().name("victory-heap".into()).spawn(worker) {
            Ok(_) => {
                tracing::info!("textures picked by index are uploaded on dedicated worker thread (VICTORY_HEAP_WORKER=1)");
                true
            }
            Err(e) => {
                tracing::warn!(error = %e, "no worker thread for indexed textures; running inline");
                false
            }
        }
    });
    let Some(job) = JOB.get().filter(|_| started) else {
        return false;
    };
    *lock(&job.heap) = Some(HeldHeap::new(heap));
    job.wake.notify_one();
    true
}

/// Pauses the background worker so a synchronous decoration bake pass can run
/// immediately on the recording thread without contending on the texture queue.
pub(crate) fn urgent() -> MutexGuard<'static, ()> {
    if let Ok(pass) = PASS.try_lock() {
        return pass;
    }
    URGENT.store(true, Relaxed);
    let pass = lock(&PASS);
    URGENT.store(false, Relaxed);
    pass
}

pub(crate) fn make_way() -> bool {
    URGENT.load(Relaxed)
}

fn worker() {
    crate::cores::keep_on_efficiency_cores("victory-heap");
    let Some(job) = JOB.get() else {
        return;
    };
    loop {
        let heap = {
            let mut next = lock(&job.heap);
            loop {
                match next.take() {
                    Some(heap) => break heap,
                    None => next = job.wake.wait(next).unwrap_or_else(|e| e.into_inner()),
                }
            }
        };
        let started = std::time::Instant::now();
        {
            let _pass = lock(&PASS);
            let heap = heap.heap();
            if let Some(host) = heap.host() {
                let mut batch = Batch::new(heap);
                let _ = crate::draw::State::heap_textures(crate::draw::Into::Ahead(&mut batch), heap, host, None);
            }
        }
        STATS[0].fetch_add(started.elapsed().as_nanos() as u64, Relaxed);
        while make_way() {
            std::thread::yield_now();
        }
    }
}
