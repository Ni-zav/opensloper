// The engine's JSON-RPC replies, checked before they are used: JSON.parse
// gives an untyped value, so each field is tested for the type it should have.

export type JsonRecord = Record<string, unknown>;

export interface RpcError {
  code: number;
  message: string;
}

export interface Reply {
  result: JsonRecord | undefined;
  error: RpcError | undefined;
  // How long the engine took, as the worker measured it
  ms: number;
}

export function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function parseReply(text: string, ms: number): Reply {
  const parsed: unknown = JSON.parse(text);
  if (!isRecord(parsed)) {
    throw new Error(`not a JSON-RPC reply: ${text.slice(0, 80)}`);
  }
  const { result, error } = parsed;
  let rpcError: RpcError | undefined;
  if (isRecord(error)) {
    rpcError = {
      code: typeof error.code === 'number' ? error.code : 0,
      message: typeof error.message === 'string' ? error.message : 'unknown error',
    };
  }
  return { result: isRecord(result) ? result : undefined, error: rpcError, ms };
}

export function numberField(result: JsonRecord | undefined, name: string): number | undefined {
  const value = result?.[name];
  return typeof value === 'number' ? value : undefined;
}

export function stringField(result: JsonRecord | undefined, name: string): string | undefined {
  const value = result?.[name];
  return typeof value === 'string' ? value : undefined;
}

export function booleanField(result: JsonRecord | undefined, name: string): boolean | undefined {
  const value = result?.[name];
  return typeof value === 'boolean' ? value : undefined;
}

export function stringsField(result: JsonRecord | undefined, name: string): string[] | undefined {
  const value = result?.[name];
  return Array.isArray(value) && value.every((item) => typeof item === 'string') ? value : undefined;
}

export function numbersField(result: JsonRecord | undefined, name: string): number[] | undefined {
  const value = result?.[name];
  return Array.isArray(value) && value.every((item) => typeof item === 'number') ? value : undefined;
}

// The objects in a list field, leaving out anything else
export function recordsField(result: JsonRecord | undefined, name: string): JsonRecord[] {
  const value = result?.[name];
  return Array.isArray(value) ? value.filter(isRecord) : [];
}

// An object's ID: a number, or the key of a repeat's point not yet given one
export function idField(result: JsonRecord | undefined, name: string): string | undefined {
  const value = result?.[name];
  if (typeof value === 'number') {
    return String(value);
  }
  return typeof value === 'string' ? value : undefined;
}

// A list of object IDs, as editor_objects_at gives them
export function idsField(result: JsonRecord | undefined, name: string): string[] {
  const value = result?.[name];
  if (!Array.isArray(value)) {
    return [];
  }
  return value.flatMap((item: unknown) => {
    if (typeof item === 'number') {
      return [String(item)];
    }
    return typeof item === 'string' ? [item] : [];
  });
}
