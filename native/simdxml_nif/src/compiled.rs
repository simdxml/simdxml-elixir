use rustler::ResourceArc;
use simdxml::CompiledXPath;

pub struct CompiledXPathResource {
    pub inner: CompiledXPath,
}

#[rustler::resource_impl]
impl rustler::Resource for CompiledXPathResource {}

#[rustler::nif]
pub fn compile_xpath(expr: &str) -> Result<ResourceArc<CompiledXPathResource>, String> {
    let compiled =
        CompiledXPath::compile(expr).map_err(|e: simdxml::SimdXmlError| e.to_string())?;
    Ok(ResourceArc::new(CompiledXPathResource { inner: compiled }))
}
