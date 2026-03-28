use rustler::{Binary, ResourceArc};

use crate::compiled::CompiledXPathResource;

#[rustler::nif(schedule = "DirtyCpu")]
pub fn batch_xpath_text(
    docs: Vec<Binary>,
    compiled: ResourceArc<CompiledXPathResource>,
) -> Result<Vec<Vec<String>>, String> {
    let doc_slices: Vec<&[u8]> = docs.iter().map(|b| b.as_slice()).collect();
    simdxml::batch::eval_batch_text(&doc_slices, &compiled.inner)
        .map_err(|e: simdxml::SimdXmlError| e.to_string())
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn batch_xpath_text_bloom(
    docs: Vec<Binary>,
    compiled: ResourceArc<CompiledXPathResource>,
) -> Result<Vec<Vec<String>>, String> {
    let doc_slices: Vec<&[u8]> = docs.iter().map(|b| b.as_slice()).collect();
    simdxml::batch::eval_batch_text_bloom(&doc_slices, &compiled.inner)
        .map_err(|e: simdxml::SimdXmlError| e.to_string())
}
