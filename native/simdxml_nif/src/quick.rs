use rustler::{Binary, ResourceArc};
use simdxml::quick::QuickScanner;

pub struct QuickScannerResource {
    pub inner: QuickScanner,
}

#[rustler::resource_impl]
impl rustler::Resource for QuickScannerResource {}

#[rustler::nif]
pub fn quick_scanner_new(tag: &str) -> ResourceArc<QuickScannerResource> {
    ResourceArc::new(QuickScannerResource {
        inner: QuickScanner::new(tag),
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn quick_extract_first(
    scanner: ResourceArc<QuickScannerResource>,
    data: Binary,
) -> Option<String> {
    scanner
        .inner
        .extract_first(data.as_slice())
        .map(|s: &str| s.to_string())
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn quick_exists(scanner: ResourceArc<QuickScannerResource>, data: Binary) -> bool {
    scanner.inner.exists(data.as_slice())
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn quick_count(scanner: ResourceArc<QuickScannerResource>, data: Binary) -> usize {
    scanner.inner.count(data.as_slice())
}
