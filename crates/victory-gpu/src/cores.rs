//! Which processors our own threads run on, where a processor has two kinds
//! of cores. `cpu_sets` and `keep_on_fast_cores` are fxceless/victory-fork's
//! (`framelog.rs`, commit 0b0074e0, GPL-3.0-or-later, as this).

/// The system's processor sets of group 0: each one's id and its efficiency
/// class (higher is faster).
fn cpu_sets() -> Vec<(u32, u8)> {
    use windows_sys::Win32::System::SystemInformation::{GetSystemCpuSetInformation, SYSTEM_CPU_SET_INFORMATION};
    use windows_sys::Win32::System::Threading::GetCurrentProcess;
    let mut bytes = 0u32;
    // SAFETY: a size query, then the call into a buffer of that size.
    unsafe { GetSystemCpuSetInformation(std::ptr::null_mut(), 0, &mut bytes, GetCurrentProcess(), 0) };
    let mut buffer = vec![0u64; (bytes as usize).div_ceil(8).max(1)];
    // SAFETY: as above; the buffer holds `bytes` bytes, aligned for the records.
    let ok = unsafe { GetSystemCpuSetInformation(buffer.as_mut_ptr().cast(), bytes, &mut bytes, GetCurrentProcess(), 0) };
    let mut sets = Vec::new();
    let mut at = 0usize;
    while ok != 0 && at + size_of::<SYSTEM_CPU_SET_INFORMATION>() <= bytes as usize {
        // SAFETY: a record inside the buffer; each says its own size.
        let info = unsafe { &*(buffer.as_ptr().cast::<u8>().add(at).cast::<SYSTEM_CPU_SET_INFORMATION>()) };
        if info.Size == 0 {
            break;
        }
        // SAFETY: the record's type is CpuSet (the only one there is).
        let set = unsafe { &info.Anonymous.CpuSet };
        if set.Group == 0 {
            sets.push((set.Id, set.EfficiencyClass));
        }
        at += info.Size as usize;
    }
    sets
}

/// The sets of the fastest class, if there are slower ones too.
fn fast_of(sets: &[(u32, u8)]) -> Vec<u32> {
    let best = sets.iter().map(|c| c.1).max().unwrap_or(0);
    let fast: Vec<u32> = sets.iter().filter(|c| c.1 == best).map(|c| c.0).collect();
    if fast.len() == sets.len() { Vec::new() } else { fast }
}

/// The sets below the fastest class (efficiency cores on hybrid CPUs).
fn slow_of(sets: &[(u32, u8)]) -> Vec<u32> {
    let best = sets.iter().map(|c| c.1).max().unwrap_or(0);
    let slow: Vec<u32> = sets.iter().filter(|c| c.1 < best).map(|c| c.0).collect();
    if slow.len() == sets.len() { Vec::new() } else { slow }
}

fn cached_slow_sets() -> &'static (Vec<u32>, usize) {
    static SLOW: std::sync::OnceLock<(Vec<u32>, usize)> = std::sync::OnceLock::new();
    SLOW.get_or_init(|| {
        let sets = cpu_sets();
        (slow_of(&sets), sets.len())
    })
}

/// Number of efficiency cores on a hybrid CPU (0 on homogeneous CPUs).
pub fn efficiency_core_count() -> usize {
    cached_slow_sets().0.len()
}

/// Routes a background streaming/decompression/detile thread onto efficiency
/// cores on hybrid CPUs with many E-cores (8+ E-cores, e.g. Arrow Lake
/// 8P+12E) and lowers its scheduling priority so it never preempts the
/// title's render/recording threads or latency-critical P-core threads.
pub fn keep_on_efficiency_cores(what: &str) {
    use windows_sys::Win32::System::Threading::{
        GetCurrentThread, SetThreadPriority, SetThreadSelectedCpuSets, THREAD_PRIORITY_BELOW_NORMAL,
    };
    if stage() == 0 {
        return;
    }
    // SAFETY: lowers priority of the calling background worker thread only.
    unsafe { SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL) };
    let (slow, of) = cached_slow_sets();
    if slow.len() < 8 {
        return;
    }
    // SAFETY: our own thread and a list of the system's own CPU set IDs.
    let ok = unsafe { SetThreadSelectedCpuSets(GetCurrentThread(), slow.as_ptr(), slow.len() as u32) };
    if ok == 0 {
        tracing::warn!(what, error = %std::io::Error::last_os_error(), "background worker could not be kept on efficiency cores");
    } else {
        static LOGGED: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        if LOGGED.fetch_add(1, std::sync::atomic::Ordering::Relaxed) < 4 {
            tracing::info!(what, slow = slow.len(), of, "background worker routed to efficiency cores (VICTORY_FAST_CORES=0: not)");
        }
    }
}

/// Default `VICTORY_FAST_CORES` stage for a CPU topology.
///
/// On hybrid CPUs with many efficiency cores (8+ E-cores, e.g. Arrow Lake
/// 8P+12E where E-cores have full 256-bit AVX2 and high IPC), pinning helper
/// pools (`stage = 2`) onto only the P-cores oversubscribes them alongside
/// the title's own threads while leaving 8–12 E-cores idle. Stage `1` keeps
/// serial latency-critical threads (`victory-submit`, `victory-relay`,
/// `victory-aside`, `victory-heap-sync`) on P-cores while letting parallel
/// worker pools (`victory-wide`, `victory-land`, `victory-under`, etc.) use
/// every physical core.
fn default_stage_for(sets: &[(u32, u8)]) -> u32 {
    let fast = fast_of(sets);
    if !fast.is_empty() && sets.len().saturating_sub(fast.len()) >= 8 {
        1
    } else {
        2
    }
}

/// `VICTORY_FAST_CORES`: 0: no thread asks; 1: the threads a frame waits for
/// one by one; 2: the threads they share their work with too;
/// 3: those that work beside the rest as well (lists translated, descriptors
/// made): more threads by then than the fast cores run at a time, while the
/// slow ones stood idle.
fn stage() -> u32 {
    static STAGE: std::sync::OnceLock<u32> = std::sync::OnceLock::new();
    *STAGE.get_or_init(|| {
        std::env::var("VICTORY_FAST_CORES")
            .ok()
            .and_then(|v| v.trim().parse().ok())
            .unwrap_or_else(|| default_stage_for(&cpu_sets()))
    })
}

/// Asks the system to run the calling thread, which a frame waits for, on
/// the fast cores only, where the processor has two kinds. That fork's submit
/// thread was found on a slow one in 1,529 looks of 24,021. (A selection of
/// processors is a preference the scheduler keeps unless nothing of it is
/// free.) The title's threads are not asked for.
pub(crate) fn keep_on_fast_cores(what: &str) {
    ask(what, 1);
}

/// [`keep_on_fast_cores`] for one of the threads a submission's preparing or
/// a landing shares its work with.
pub(crate) fn keep_helper_on_fast_cores(what: &str) {
    ask(what, 2);
}

/// [`keep_on_fast_cores`] for one of many threads whose work is ahead of what
/// a frame waits for.
pub(crate) fn keep_many_on_fast_cores(what: &str) {
    ask(what, 3);
}

fn ask(what: &str, from: u32) {
    use windows_sys::Win32::System::Threading::{GetCurrentThread, SetThreadSelectedCpuSets};
    if stage() < from {
        return;
    }
    static FAST: std::sync::OnceLock<(Vec<u32>, usize)> = std::sync::OnceLock::new();
    let (fast, of) = FAST.get_or_init(|| {
        let sets = cpu_sets();
        (fast_of(&sets), sets.len())
    });
    // All alike (or nothing known): nothing to ask for.
    if fast.is_empty() {
        return;
    }
    // SAFETY: our own thread and a list of the system's own set ids.
    let ok = unsafe { SetThreadSelectedCpuSets(GetCurrentThread(), fast.as_ptr(), fast.len() as u32) };
    if ok == 0 {
        tracing::warn!(what, error = %std::io::Error::last_os_error(), "the thread could not be kept on the fast cores");
    } else {
        tracing::info!(what, fast = fast.len(), of, "the thread is kept on the fast cores (VICTORY_FAST_CORES=0: not)");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_fast_cores_are_those_of_the_best_class_if_there_is_a_worse_one() {
        assert_eq!(fast_of(&[(256, 1), (257, 1), (258, 0)]), [256, 257]);
        assert!(fast_of(&[(256, 0), (257, 0)]).is_empty());
        assert!(fast_of(&[]).is_empty());
        assert!(!cpu_sets().is_empty());
        std::thread::spawn(|| keep_on_fast_cores("test")).join().unwrap();
    }
}
