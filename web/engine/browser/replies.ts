// The engine's JSON-RPC replies, checked before they are used: JSON.parse
// gives an untyped value, so each field is tested for the type it should have.

export interface RpcError {
  code: number;
  message: string;
}

export interface Reply {
  result: Record<string, unknown> | undefined;
  error: RpcError | undefined;
  // How long the engine took, as the worker measured it
  ms: number;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
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

export function numberField(result: Record<string, unknown> | undefined, name: string): number | undefined {
  const value = result?.[name];
  return typeof value === 'number' ? value : undefined;
}

export function stringField(result: Record<string, unknown> | undefined, name: string): string | undefined {
  const value = result?.[name];
  return typeof value === 'string' ? value : undefined;
}

export function stringsField(result: Record<string, unknown> | undefined, name: string): string[] | undefined {
  const value = result?.[name];
  return Array.isArray(value) && value.every((item) => typeof item === 'string') ? value : undefined;
}
