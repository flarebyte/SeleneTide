/** JSON request contract for constrained DuckDB analytics. */

export type JSONScalar = string | number | boolean | null;
export type QueryValue = JSONScalar | readonly JSONScalar[];
export type QueryValues = Readonly<Record<string, QueryValue>>;

export type DatasetName = "email_metadata" | "processing_results";
export type SortDirection = "asc" | "desc";
export type NullOrdering = "first" | "last";

export interface OrderByItem {
  field: string;
  direction: SortDirection;
  nulls?: NullOrdering;
}

export type SimpleStat =
  | "count"
  | "min"
  | "max"
  | "avg"
  | "stddev"
  | "median"
  | "approx_distinct";

export type StatRequest =
  | SimpleStat
  | {
      function: SimpleStat;
      as?: string;
    }
  | {
      function: "quantile";
      /** Variable reference such as "$percentile"; never a literal. */
      probability: string;
      as?: string;
    };

export interface QueryBase {
  from: DatasetName;
  where?: string;
  group_by?: readonly string[];
  having?: string;
  order_by?: readonly OrderByItem[];
  /** Structural controls are bound as parameters, not interpolated into SQL. */
  limit?: number;
  offset?: number;
  values?: QueryValues;
  /** Optional allow-listed relationships; arbitrary join predicates do not exist. */
  relationships?: readonly string[];
}

export interface RowsQuery extends QueryBase {
  select?: readonly string[];
  count?: never;
  stats?: never;
}

export interface CountQuery extends QueryBase {
  count: true;
  select?: never;
  stats?: never;
}

export interface StatsQuery extends QueryBase {
  stats: Readonly<Record<string, readonly StatRequest[]>>;
  select?: never;
  count?: never;
}

export type QueryRequest = RowsQuery | CountQuery | StatsQuery;

export type SourceSpan = {
  start: number;
  end: number;
};

/** Expressions intentionally have no literal node. */
export type ExpressionAST =
  | { kind: "identifier"; name: string; span: SourceSpan }
  | { kind: "variable"; name: string; span: SourceSpan }
  | {
      kind: "function";
      name: string;
      arguments: readonly ExpressionAST[];
      span: SourceSpan;
    }
  | {
      kind: "not";
      operand: ExpressionAST;
      span: SourceSpan;
    }
  | {
      kind: "logical";
      operator: "and" | "or";
      left: ExpressionAST;
      right: ExpressionAST;
      span: SourceSpan;
    }
  | {
      kind: "comparison";
      operator: "==" | "!=" | "<" | "<=" | ">" | ">=" | "in";
      left: ExpressionAST;
      right: ExpressionAST;
      span: SourceSpan;
    };

export interface ValidatedQuery {
  request: QueryRequest;
  where?: ExpressionAST;
  having?: ExpressionAST;
  resolvedDataset: string;
  resolvedRelationships: readonly string[];
}

export interface CompiledDuckDBQuery {
  sql: string;
  /** Ordered values corresponding to DuckDB positional placeholders. */
  bindings: readonly QueryValue[];
  outputColumns: readonly string[];
}

export type QueryErrorStage =
  | "request"
  | "parse"
  | "validate"
  | "compile"
  | "execute";

export interface QueryError {
  code: string;
  stage: QueryErrorStage;
  message: string;
  /** JSON Pointer for structure errors, such as /values/year. */
  path?: string;
  expression?: "where" | "having";
  span?: SourceSpan;
  retryable: boolean;
}

export type QueryResult =
  | {
      ok: true;
      columns: readonly string[];
      rows: readonly Readonly<Record<string, JSONScalar | object>>[];
    }
  | { ok: false; error: QueryError };

export interface EmailAnalyticsQueryAPI {
  query(requestJSON: string): Promise<QueryResult>;
}
