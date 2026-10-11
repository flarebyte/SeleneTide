//! Rust-internal design sketch; not the public C ABI. No external dependencies.
use std::{collections::BTreeMap, future::Future, pin::Pin, sync::Arc};

pub type WorkFuture<'a, T> = Pin<Box<dyn Future<Output = Result<T, String>> + Send + 'a>>;
#[derive(Clone, Debug)]
pub enum OfficialStatus { Succeeded, Retry, Failed, Skipped }
#[derive(Clone, Debug)]
pub enum PersistedOutput { None, Json(String), Binary(Vec<u8>), Utf8(String) }
pub struct TransformerResult<T> {
    pub status: OfficialStatus,
    pub custom_status: Option<String>,
    pub message: Option<String>,
    pub output: Option<T>,
}
pub struct NormalizedEmailMetadata {
    pub schema_version: i32,
    pub source_version: i64,
    pub canonical_json: String, // validated metadata only, no message bodies
}
pub struct TransformerInput {
    pub account_id: String,
    pub mailbox_id: String,
    pub uid_validity: u32,
    pub email_uid: u32,
    pub email_date_unix_ms: i64,
    pub metadata: NormalizedEmailMetadata,
    pub idempotency_key: String,
    pub dependency_outputs: BTreeMap<String, PersistedOutput>,
}
pub trait EmailTransformer: Send + Sync + 'static {
    type Output: Send;
    fn name(&self) -> &str; // durable name; renaming requires SQL migration
    fn version(&self) -> i32;
    fn output_schema_version(&self) -> i32;
    fn transform(&self, input: TransformerInput) -> WorkFuture<'_, TransformerResult<Self::Output>>;
    fn encode(&self, output: Self::Output) -> Result<PersistedOutput, String>;
}
pub struct EncodedResult {
    pub status: OfficialStatus,
    pub custom_status: Option<String>,
    pub message: Option<String>,
    pub output: PersistedOutput,
    pub output_schema_version: i32,
}
pub trait ErasedTransformer: Send + Sync {
    fn name(&self) -> &str;
    fn version(&self) -> i32;
    fn output_schema_version(&self) -> i32;
    fn run(&self, input: TransformerInput) -> WorkFuture<'_, EncodedResult>;
}
pub struct TypedAdapter<T: EmailTransformer>(pub T);
impl<T: EmailTransformer> ErasedTransformer for TypedAdapter<T> {
    fn name(&self) -> &str { self.0.name() }
    fn version(&self) -> i32 { self.0.version() }
    fn output_schema_version(&self) -> i32 { self.0.output_schema_version() }
    fn run(&self, input: TransformerInput) -> WorkFuture<'_, EncodedResult> {
        Box::pin(async move {
            let result = self.0.transform(input).await?;
            let output = match result.output {
                Some(value) => self.0.encode(value)?,
                None => PersistedOutput::None,
            };
            Ok(EncodedResult { status: result.status, custom_status: result.custom_status,
                message: result.message, output,
                output_schema_version: self.0.output_schema_version() })
        })
    }
}
pub struct TransformerRegistry(BTreeMap<String, Arc<dyn ErasedTransformer>>);
impl TransformerRegistry {
    pub fn new(items: Vec<Arc<dyn ErasedTransformer>>) -> Result<Self, String> {
        let mut map = BTreeMap::new();
        for item in items {
            let name = item.name().to_owned();
            if name.is_empty() || name.trim() != name || item.version() <= 0
                || item.output_schema_version() <= 0 {
                return Err("transformer.invalid-contract".into());
            }
            if map.insert(name, item).is_some() { return Err("transformer.duplicate".into()); }
        }
        Ok(Self(map))
    }
    /// Resolve before claiming work; mismatch blocks without consuming attempts.
    pub fn resolve(&self, name: &str, version: i32, schema: i32)
        -> Result<Arc<dyn ErasedTransformer>, String> {
        let item = self.0.get(name).ok_or("transformer.missing")?;
        if item.version() != version || item.output_schema_version() != schema {
            return Err("transformer.incompatible-contract".into());
        }
        Ok(Arc::clone(item))
    }
}
