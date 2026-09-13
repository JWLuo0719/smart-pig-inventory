export type TokenPair = {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt: string;
  refreshTokenExpiresAt: string;
};

export class BackendApiError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export type BackendFetcher = (
  path: string,
  token: string | null,
  init?: RequestInit,
) => Promise<Response>;

export function newIdempotencyKey(): string {
  if (typeof globalThis.crypto?.randomUUID === "function") return globalThis.crypto.randomUUID();
  const bytes = new Uint8Array(16);
  if (typeof globalThis.crypto?.getRandomValues === "function") globalThis.crypto.getRandomValues(bytes);
  else for (let index = 0; index < bytes.length; index++) bytes[index] = Math.floor(Math.random() * 256);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export async function fetchBackend(path: string, token: string | null, init?: RequestInit): Promise<Response> {
  const headers = new Headers(init?.headers);
  if (token) headers.set("Authorization", `Bearer ${token}`);
  return fetch(`/api/backend/${path}`, {
    ...init,
    headers,
    cache: "no-store",
  });
}

export async function readResponseData<T>(response: Response): Promise<T> {
  if (!response.ok) {
    const body = await response.json().catch(() => null) as { detail?: string; message?: string } | null;
    throw new BackendApiError(response.status, body?.detail ?? body?.message ?? `请求失败（HTTP ${response.status}）`);
  }
  return response.json() as Promise<T>;
}

export class AuthenticatedBackendClient {
  private tokens: TokenPair | null = null;
  private refreshPromise: Promise<TokenPair> | null = null;
  private sessionGeneration = 0;
  private readonly onTokensChanged: (tokens: TokenPair | null) => void;
  private readonly backendFetcher: BackendFetcher;

  constructor(
    onTokensChanged: (tokens: TokenPair | null) => void,
    backendFetcher: BackendFetcher = fetchBackend,
  ) {
    this.onTokensChanged = onTokensChanged;
    this.backendFetcher = backendFetcher;
  }

  installTokens(tokens: TokenPair | null): void {
    this.sessionGeneration += 1;
    this.refreshPromise = null;
    this.tokens = tokens;
    this.onTokensChanged(tokens);
  }

  async authorizedResponse(path: string, init?: RequestInit): Promise<Response> {
    const current = this.tokens;
    const generation = this.sessionGeneration;
    if (!current) throw new BackendApiError(401, "请先登录。");
    let response = await this.backendFetcher(path, current.accessToken, init);
    this.assertSession(generation);
    if (response.status !== 401) return response;
    const rotated = this.tokens !== current ? this.tokens! : await this.rotateTokens(generation);
    this.assertSession(generation);
    response = await this.backendFetcher(path, rotated.accessToken, init);
    this.assertSession(generation);
    if (response.status === 401 && this.tokens === rotated) this.installTokens(null);
    return response;
  }

  private assertSession(generation: number): void {
    if (generation !== this.sessionGeneration) throw new BackendApiError(401, "登录会话已更换，请重新操作。");
  }

  private async rotateTokens(generation: number): Promise<TokenPair> {
    if (this.refreshPromise) return this.refreshPromise;
    const current = this.tokens;
    if (!current) throw new BackendApiError(401, "登录会话已失效，请重新登录。");
    const rotation = (async () => {
      try {
        const response = await this.backendFetcher("auth/refresh", null, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Idempotency-Key": newIdempotencyKey() },
        body: JSON.stringify({ refreshToken: current.refreshToken }),
        });
        const pair = await readResponseData<TokenPair>(response);
        this.assertSession(generation);
        this.tokens = pair;
        this.onTokensChanged(pair);
        return pair;
      } catch (cause) {
        if (generation === this.sessionGeneration) this.installTokens(null);
        throw cause;
      }
    })();
    this.refreshPromise = rotation;
    try {
      return await rotation;
    } finally {
      if (this.refreshPromise === rotation) this.refreshPromise = null;
    }
  }
}
