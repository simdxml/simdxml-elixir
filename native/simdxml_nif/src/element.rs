use rustler::ResourceArc;
use simdxml::XmlIndex;

use crate::document::DocumentResource;

// ---------------------------------------------------------------------------
// Element navigation NIFs — elements are (doc_ref, tag_idx) pairs, not resources
// ---------------------------------------------------------------------------

#[rustler::nif]
pub fn element_tag(doc: ResourceArc<DocumentResource>, tag_idx: usize) -> String {
    doc.index().tag_name(tag_idx).to_string()
}

#[rustler::nif]
pub fn element_text(doc: ResourceArc<DocumentResource>, tag_idx: usize) -> Option<String> {
    doc.index()
        .direct_text_first(tag_idx)
        .map(|s| XmlIndex::decode_entities(s).into_owned())
}

#[rustler::nif]
pub fn element_all_text(doc: ResourceArc<DocumentResource>, tag_idx: usize) -> String {
    doc.index().all_text(tag_idx)
}

#[rustler::nif]
pub fn element_attributes(
    doc: ResourceArc<DocumentResource>,
    tag_idx: usize,
) -> Vec<(String, String)> {
    doc.index()
        .attributes(tag_idx)
        .into_iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

#[rustler::nif]
pub fn element_get_attribute(
    doc: ResourceArc<DocumentResource>,
    tag_idx: usize,
    name: &str,
) -> Option<String> {
    doc.index()
        .get_attribute(tag_idx, name)
        .map(|s| s.to_string())
}

#[rustler::nif]
pub fn element_children(doc: ResourceArc<DocumentResource>, tag_idx: usize) -> Vec<usize> {
    doc.index()
        .child_slice(tag_idx)
        .iter()
        .map(|&c| c as usize)
        .collect()
}

#[rustler::nif]
pub fn element_parent(doc: ResourceArc<DocumentResource>, tag_idx: usize) -> Option<usize> {
    doc.index().parent(tag_idx)
}

#[rustler::nif]
pub fn element_raw_xml(doc: ResourceArc<DocumentResource>, tag_idx: usize) -> String {
    doc.index().raw_xml(tag_idx).to_string()
}
