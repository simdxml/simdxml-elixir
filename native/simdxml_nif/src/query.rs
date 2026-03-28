use rustler::{Encoder, Env, ResourceArc, Term};
use simdxml::xpath::XPathNode;
use simdxml::XmlIndex;

use crate::compiled::CompiledXPathResource;
use crate::document::DocumentResource;

mod atoms {
    rustler::atoms! {
        element,
        text,
        attribute,
        number,
        string,
        boolean,
        nodeset,
    }
}

// ---------------------------------------------------------------------------
// XPath query NIFs
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
pub fn xpath_text(doc: ResourceArc<DocumentResource>, expr: &str) -> Result<Vec<String>, String> {
    let index = doc.index();
    let results = index
        .xpath_text(expr)
        .map_err(|e: simdxml::SimdXmlError| e.to_string())?;
    Ok(results.into_iter().map(|s| s.to_string()).collect())
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn xpath_string(
    doc: ResourceArc<DocumentResource>,
    expr: &str,
) -> Result<Vec<String>, String> {
    let index = doc.index();
    index
        .xpath_string(expr)
        .map_err(|e: simdxml::SimdXmlError| e.to_string())
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn xpath_text_from(
    doc: ResourceArc<DocumentResource>,
    expr: &str,
    context_idx: usize,
) -> Result<Vec<String>, String> {
    let index = doc.index();
    let nodes = index
        .xpath_from(expr, context_idx)
        .map_err(|e: simdxml::SimdXmlError| e.to_string())?;
    let mut texts: Vec<String> = Vec::new();
    for node in &nodes {
        match node {
            XPathNode::Element(idx) => {
                if let Some(first) = index.direct_text_first(*idx) {
                    texts.push(XmlIndex::decode_entities(first).into_owned());
                }
            }
            XPathNode::Text(idx) => {
                texts.push(index.text_by_index(*idx).to_string());
            }
            XPathNode::Attribute(tag_idx, _) => {
                let attrs = index.attributes(*tag_idx);
                if let Some((_, val)) = attrs.first() {
                    texts.push(val.to_string());
                }
            }
            XPathNode::Namespace(_, _) => {}
        }
    }
    Ok(texts)
}

/// Return node references as tagged tuples: {:element, idx} | {:text, idx} | {:attribute, idx}
#[rustler::nif(schedule = "DirtyCpu")]
pub fn xpath_nodes<'a>(
    env: Env<'a>,
    doc: ResourceArc<DocumentResource>,
    expr: &str,
) -> Result<Vec<Term<'a>>, String> {
    let index = doc.index();
    let nodes = index
        .xpath(expr)
        .map_err(|e: simdxml::SimdXmlError| e.to_string())?;
    let mut result = Vec::with_capacity(nodes.len());
    for node in &nodes {
        let term = match node {
            XPathNode::Element(idx) => (atoms::element(), idx).encode(env),
            XPathNode::Text(idx) => (atoms::text(), idx).encode(env),
            XPathNode::Attribute(tag_idx, _) => (atoms::attribute(), tag_idx).encode(env),
            XPathNode::Namespace(_, _) => continue,
        };
        result.push(term);
    }
    Ok(result)
}

/// Evaluate a scalar XPath expression. Returns tagged result.
#[rustler::nif(schedule = "DirtyCpu")]
pub fn eval<'a>(
    env: Env<'a>,
    doc: ResourceArc<DocumentResource>,
    expr: &str,
) -> Result<Term<'a>, String> {
    let compiled =
        simdxml::CompiledXPath::compile(expr).map_err(|e: simdxml::SimdXmlError| e.to_string())?;
    let index = doc.index();

    // Evaluate as nodeset (published API only has eval -> Vec<XPathNode>)
    let nodes = compiled
        .eval(index)
        .map_err(|e: simdxml::SimdXmlError| e.to_string())?;

    // Handle count() and boolean() wrappers
    if expr.starts_with("count(") {
        return Ok((atoms::number(), nodes.len() as f64).encode(env));
    }
    if expr.starts_with("boolean(") || expr == "true()" || expr == "false()" {
        return Ok((atoms::boolean(), !nodes.is_empty()).encode(env));
    }
    let mut terms = Vec::with_capacity(nodes.len());
    for node in &nodes {
        match node {
            XPathNode::Element(idx) => terms.push((atoms::element(), idx).encode(env)),
            XPathNode::Text(idx) => terms.push((atoms::text(), idx).encode(env)),
            XPathNode::Attribute(tag_idx, _) => {
                terms.push((atoms::attribute(), tag_idx).encode(env))
            }
            XPathNode::Namespace(_, _) => {}
        }
    }
    Ok((atoms::nodeset(), terms).encode(env))
}

// ---------------------------------------------------------------------------
// Compiled XPath query NIFs
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
pub fn compiled_eval_text(
    doc: ResourceArc<DocumentResource>,
    compiled: ResourceArc<CompiledXPathResource>,
) -> Result<Vec<String>, String> {
    let index = doc.index();
    let results = compiled
        .inner
        .eval_text(index)
        .map_err(|e: simdxml::SimdXmlError| e.to_string())?;
    Ok(results.into_iter().map(|s: &str| s.to_string()).collect())
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn compiled_eval_count(
    doc: ResourceArc<DocumentResource>,
    compiled: ResourceArc<CompiledXPathResource>,
) -> Result<usize, String> {
    let index = doc.index();
    let nodes = compiled
        .inner
        .eval(index)
        .map_err(|e: simdxml::SimdXmlError| e.to_string())?;
    Ok(nodes.len())
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn compiled_eval_exists(
    doc: ResourceArc<DocumentResource>,
    compiled: ResourceArc<CompiledXPathResource>,
) -> Result<bool, String> {
    let index = doc.index();
    let nodes = compiled
        .inner
        .eval(index)
        .map_err(|e: simdxml::SimdXmlError| e.to_string())?;
    Ok(!nodes.is_empty())
}
