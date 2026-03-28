use rustler::{Binary, ResourceArc};

/// A simple tag scanner that searches raw bytes for `<tagname>` / `<tagname ` / `<tagname/`.
/// Equivalent to simdxml::quick::QuickScanner but implemented here since it's not
/// in the published crate yet.
pub struct QuickScannerResource {
    open_pattern: Vec<u8>,
    close_pattern: Vec<u8>,
    tag: String,
}

#[rustler::resource_impl]
impl rustler::Resource for QuickScannerResource {}

#[rustler::nif]
pub fn quick_scanner_new(tag: &str) -> ResourceArc<QuickScannerResource> {
    let tag_bytes = tag.as_bytes();
    let mut open = Vec::with_capacity(1 + tag_bytes.len());
    open.push(b'<');
    open.extend_from_slice(tag_bytes);

    let mut close = Vec::with_capacity(2 + tag_bytes.len());
    close.extend_from_slice(b"</");
    close.extend_from_slice(tag_bytes);

    ResourceArc::new(QuickScannerResource {
        open_pattern: open,
        close_pattern: close,
        tag: tag.to_string(),
    })
}

/// Find `needle` in `haystack` starting from `start`.
fn find_bytes(haystack: &[u8], start: usize, needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || start + needle.len() > haystack.len() {
        return None;
    }
    let first = needle[0];
    let mut pos = start;
    while pos + needle.len() <= haystack.len() {
        if let Some(offset) = memchr::memchr(first, &haystack[pos..]) {
            let abs = pos + offset;
            if abs + needle.len() <= haystack.len() && &haystack[abs..abs + needle.len()] == needle
            {
                return Some(abs);
            }
            pos = abs + 1;
        } else {
            return None;
        }
    }
    None
}

/// Check if a position is a valid open tag start (next char after name is > or space or /).
fn is_valid_tag(doc: &[u8], after_name: usize) -> bool {
    if after_name >= doc.len() {
        return false;
    }
    let b = doc[after_name];
    b == b'>' || b == b' ' || b == b'\t' || b == b'\n' || b == b'\r' || b == b'/'
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn quick_extract_first(
    scanner: ResourceArc<QuickScannerResource>,
    data: Binary,
) -> Option<String> {
    let doc = data.as_slice();
    let mut pos = 0;
    while let Some(offset) = find_bytes(doc, pos, &scanner.open_pattern) {
        let after_name = offset + scanner.open_pattern.len();
        if !is_valid_tag(doc, after_name) {
            pos = after_name;
            continue;
        }
        // Find the closing >
        let close_bracket = memchr::memchr(b'>', &doc[after_name..])? + after_name;
        // Self-closing?
        if doc[close_bracket - 1] == b'/' {
            pos = close_bracket + 1;
            continue;
        }
        let text_start = close_bracket + 1;
        // Find closing tag
        let close_offset = find_bytes(doc, text_start, &scanner.close_pattern)?;
        // Check for nested elements
        if memchr::memchr(b'<', &doc[text_start..close_offset]).is_some() {
            return None; // nested elements
        }
        return std::str::from_utf8(&doc[text_start..close_offset])
            .ok()
            .map(|s| s.to_string());
    }
    Some(String::new()) // tag not found
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn quick_exists(scanner: ResourceArc<QuickScannerResource>, data: Binary) -> bool {
    let doc = data.as_slice();
    let mut pos = 0;
    while let Some(offset) = find_bytes(doc, pos, &scanner.open_pattern) {
        let after_name = offset + scanner.open_pattern.len();
        if is_valid_tag(doc, after_name) {
            return true;
        }
        pos = after_name;
    }
    false
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn quick_count(scanner: ResourceArc<QuickScannerResource>, data: Binary) -> usize {
    let doc = data.as_slice();
    let mut pos = 0;
    let mut count = 0;
    while let Some(offset) = find_bytes(doc, pos, &scanner.open_pattern) {
        let after_name = offset + scanner.open_pattern.len();
        if is_valid_tag(doc, after_name) {
            count += 1;
        }
        pos = after_name;
    }
    count
}
