//! Blocking adapter sketch run on a session-owned database worker, never a UI thread.
//! Actual adapters must enforce all row mappings in duckdb_processing_export_tables.csv.
use std::time::Duration;

pub struct ProcessingResultRow {
    pub step_id: String, // stable UUID primary key, not a managed-object URI
    pub account_id: String,
    pub mailbox_id: String,
    pub uid_validity: u32,
    pub email_uid: u32,
    pub transformer_name: String,
    pub transformer_version: i32,
    pub source_version: i64,
    pub canonical_projection_json: String, // immutable validated column snapshot
}
pub struct ExportBatch { pub id: String, pub rows: Vec<ProcessingResultRow> }
pub struct ExportReport {
    pub batch_id: Option<String>,
    pub selected: usize,
    pub committed: usize,
    pub replayed: usize,
}
pub struct ExportConfiguration {
    pub batch_size: usize,
    pub maximum_attempts: u32,
    pub lease_duration: Duration,
}
impl Default for ExportConfiguration {
    fn default() -> Self {
        Self { batch_size: 250, maximum_attempts: 5, lease_duration: Duration::from_secs(120) }
    }
}
pub trait ExportDestination: Send {
    fn prepare_schema(&mut self) -> Result<i32, String>;
    /// One parameterized DuckDB transaction, serialized with other account writers.
    /// Equal/newer stored revisions succeed as no-ops, counted as replayed.
    fn upsert(&mut self, rows: &[ProcessingResultRow]) -> Result<usize, String>;
}
pub trait ExportStateStore: Send {
    /// Claim and snapshot atomically in SQLite. No transaction spans DuckDB work.
    fn claim(&mut self, config: &ExportConfiguration) -> Result<Option<ExportBatch>, String>;
    /// Fence each update by batch ID and immutable source version; preserve newer pending work.
    fn acknowledge(&mut self, batch: &ExportBatch, schema_version: i32) -> Result<(), String>;
    /// Same fencing; diagnostics must not mask the primary error.
    fn record_failure(&mut self, batch: &ExportBatch, error: &str) -> Result<(), String>;
}
pub struct DuckDBExporter<S, D> {
    pub state_store: S,
    pub destination: D,
    pub configuration: ExportConfiguration,
}
impl<S: ExportStateStore, D: ExportDestination> DuckDBExporter<S, D> {
    /// Exclusive mutable ownership serializes batches for this worker.
    /// Metadata projection uses a separate adapter with the same replay contract.
    pub fn export_next_batch(&mut self) -> Result<ExportReport, String> {
        if self.configuration.batch_size == 0 || self.configuration.maximum_attempts == 0
            || self.configuration.lease_duration.is_zero() {
            return Err("export.invalid-configuration".into());
        }
        let schema = self.destination.prepare_schema()?;
        let Some(batch) = self.state_store.claim(&self.configuration)? else {
            return Ok(ExportReport { batch_id: None, selected: 0, committed: 0, replayed: 0 });
        };
        let outcome: Result<ExportReport, String> = (|| {
            let committed = self.destination.upsert(&batch.rows)?;
            if committed > batch.rows.len() { return Err("export.invalid-count".into()); }
            self.state_store.acknowledge(&batch, schema)?;
            Ok(ExportReport { batch_id: Some(batch.id.clone()), selected: batch.rows.len(),
                committed, replayed: batch.rows.len() - committed })
        })();
        if let Err(ref error) = outcome {
            let _ = self.state_store.record_failure(&batch, error);
            // Failed diagnostics leave the claim recoverable after lease expiry.
        }
        outcome
    }
}
