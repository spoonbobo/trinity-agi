/**
 * WebSocket wire format — 1:1 port of models/ws_frame.dart
 *
 * Three frame types: req, res, event
 * Requests/responses correlated by UUID id.
 * Protocol: symmetric JSON, discriminated by `type` field.
 */

export type FrameType = 'req' | 'res' | 'event';

/* ------------------------------------------------------------------ */
/*  WsRequest                                                          */
/* ------------------------------------------------------------------ */

export interface WsRequest {
  id: string;
  method: string;
  params: Record<string, any>;
}

export function encodeRequest(req: WsRequest): string {
  return JSON.stringify({
    type: 'req',
    id: req.id,
    method: req.method,
    params: req.params,
  });
}

/* ------------------------------------------------------------------ */
/*  WsResponse                                                         */
/* ------------------------------------------------------------------ */

export interface WsResponse {
  id: string;
  ok: boolean;
  payload?: Record<string, any>;
  error?: Record<string, any>;
}

export function parseResponse(json: Record<string, any>): WsResponse {
  return {
    id: json.id ?? '',
    ok: json.ok === true,
    payload: json.ok === true ? json.payload ?? json : undefined,
    error: json.ok !== true ? json.error ?? json : undefined,
  };
}

/* ------------------------------------------------------------------ */
/*  WsEvent                                                            */
/* ------------------------------------------------------------------ */

export interface WsEvent {
  event: string;
  payload: Record<string, any>;
  seq?: number;
  stateVersion?: number;
}

export function parseEvent(json: Record<string, any>): WsEvent {
  return {
    event: json.event ?? '',
    payload: json.payload ?? {},
    seq: json.seq,
    stateVersion: json.stateVersion,
  };
}

/* ------------------------------------------------------------------ */
/*  WsFrame — union-like container                                     */
/* ------------------------------------------------------------------ */

export type WsFrame =
  | { type: 'req'; request: WsRequest }
  | { type: 'res'; response: WsResponse }
  | { type: 'event'; event: WsEvent };

/**
 * Parse a raw JSON string into a typed WsFrame.
 * Throws on unknown frame type.
 */
export function parseFrame(raw: string): WsFrame {
  const json = JSON.parse(raw);
  const type = json.type as string;

  switch (type) {
    case 'req':
      return {
        type: 'req',
        request: {
          id: json.id ?? '',
          method: json.method ?? '',
          params: json.params ?? {},
        },
      };

    case 'res':
      return {
        type: 'res',
        response: parseResponse(json),
      };

    case 'event':
      return {
        type: 'event',
        event: parseEvent(json),
      };

    default:
      throw new Error(`Unknown frame type: ${type}`);
  }
}
