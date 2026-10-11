/** JSON wire contracts for the stateful Rust library, ABI/payload version 1.
 * These types describe payloads, not a TypeScript implementation.
 * Promise/AsyncIterable sketches elsewhere are conveniences supplied by host adapters.
 */
export type Authentication = {
  mechanisms:
    | { PLAIN: { username: string; password: string } }
    | { XOAUTH2: { username: string; accessToken: string } }
    | { OAUTHBEARER: { username: string; accessToken: string } }
    | { "SCRAM-SHA-256": { username: string; password: string } };
};
// Runtime validation enforces EXACTLY ONE key; TypeScript unions alone do not.
export const passwordExample: Authentication = {
  mechanisms: { "SCRAM-SHA-256": { username: "user@example.com", password: "<password>" } },
};
export const tokenExample: Authentication = {
  mechanisms: { XOAUTH2: { username: "user@gmail.com", accessToken: "<access-token>" } },
};

export interface SessionConfiguration {
  apiVersion: 1;
  libraryRoot: string;
  workerLimit: number; // positive bounded integer; applies to session-owned workers
  busyTimeoutMs: number; // positive bounded integer
  maxRequestBytes: number;
  maxResponseBytes: number;
  maxEventQueueSize: number;
}
export interface AccountConfiguration {
  accountID: string;
  displayName: string;
  imapHost: string;
  imapPort: number;
  transportSecurity: "tls" | "starttls-required";
}
export type SessionRequest =
  | { apiVersion: 1; method: "account.configure"; params: AccountConfiguration }
  | { apiVersion: 1; method: "account.list"; params: Record<string, never> }
  | { apiVersion: 1; method: "auth.set"; params: { accountID: string; authentication: Authentication } }
  | { apiVersion: 1; method: "auth.clear"; params: { accountID: string } }
  | { apiVersion: 1; method: "auth.status"; params: { accountID: string } }
  | { apiVersion: 1; method: "operation.status" | "operation.cancel"; params: { operationID: string } }
  | { apiVersion: 1; method: "operation.result"; params: { operationID: string; cursor?: string } }
  | { apiVersion: 1; method: "events.poll"; params: { after?: string; limit: number } }
  // Validate subsystem params against the sync, processing, query, or fetch sketches.
  | { apiVersion: 1; method:
      "sync.plan" | "sync.start" | "sync.resume" | "sync.status" | "sync.cancel" |
      "processing.start" | "processing.resume" | "processing.status" | "processing.steps" | "processing.cancel" |
      "query.validate" | "query.execute" | "content.fetch" | "content.status" |
      "content.cancel" | "content.release" | "content.cleanup" | "export.start";
      params: Record<string, unknown> };

export type SessionResponse =
  | { apiVersion: 1; ok: true; result: unknown }
  | { apiVersion: 1; ok: false; error: { code: string; message: string; retryable: boolean } };
// Starting long work returns {operationID}; its result is retrieved and paginated.
// IDs, source revisions, event cursors and 64-bit integers use decimal strings
// where JSON numbers would lose precision. UTC timestamps use RFC3339 strings.
// auth.status returns only {accountID, mechanism, state}; never username/secret echoes.
// state: authentication-required | credentials-ready | authenticating | authenticated.
// auth.set validates and stores parameters; a successful set does not prove server login.
