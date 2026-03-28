use rustler::Binary;
use rustler::ResourceArc;
use self_cell::self_cell;
use simdxml::XmlIndex;

// ---------------------------------------------------------------------------
// Self-referential Document: owns bytes + XmlIndex
// ---------------------------------------------------------------------------

self_cell!(
    pub struct DocumentInner {
        owner: Vec<u8>,
        #[covariant]
        dependent: XmlIndex,
    }
);

// SAFETY: DocumentInner owns all its data. XmlIndex borrows only from the
// co-located owner Vec<u8>. No interior mutability, no thread-local state.
// The struct is immutable after construction.
unsafe impl Send for DocumentInner {}
unsafe impl Sync for DocumentInner {}

pub struct DocumentResource {
    pub inner: DocumentInner,
}

impl DocumentResource {
    pub fn index(&self) -> &XmlIndex<'_> {
        self.inner.borrow_dependent()
    }
}

#[rustler::resource_impl]
impl rustler::Resource for DocumentResource {}

// ---------------------------------------------------------------------------
// NIF: parse
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
pub fn parse(binary: Binary) -> Result<ResourceArc<DocumentResource>, String> {
    let bytes = binary.as_slice().to_vec();
    let inner = DocumentInner::try_new(bytes, |data| {
        let mut index = simdxml::parse(data)?;
        // Build all indices eagerly so the index can be used immutably.
        index.ensure_indices();
        index.build_name_index();
        Ok(index)
    })
    .map_err(|e: simdxml::SimdXmlError| e.to_string())?;
    Ok(ResourceArc::new(DocumentResource { inner }))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn parse_for_xpath(
    binary: Binary,
    xpath: &str,
) -> Result<ResourceArc<DocumentResource>, String> {
    let xpath_owned = xpath.to_string();
    let bytes = binary.as_slice().to_vec();
    let inner = DocumentInner::try_new(bytes, |data| {
        let mut index = simdxml::parse_for_xpath(data, &xpath_owned)?;
        index.ensure_indices();
        index.build_name_index();
        Ok(index)
    })
    .map_err(|e: simdxml::SimdXmlError| e.to_string())?;
    Ok(ResourceArc::new(DocumentResource { inner }))
}

// ---------------------------------------------------------------------------
// NIF: document info
// ---------------------------------------------------------------------------

#[rustler::nif]
pub fn document_root(doc: ResourceArc<DocumentResource>) -> Option<usize> {
    let index = doc.index();
    (0..index.tag_count()).find(|&i| {
        index.depth(i) == 0
            && (index.tag_type(i) == simdxml::index::TagType::Open
                || index.tag_type(i) == simdxml::index::TagType::SelfClose)
    })
}

#[rustler::nif]
pub fn document_tag_count(doc: ResourceArc<DocumentResource>) -> usize {
    doc.index().tag_count()
}
