import { getApiBaseUrl } from "../env/api-base-url";

export async function apiRequest<T>(
  path: string,
  options?: RequestInit,
): Promise<T> {
  const base = getApiBaseUrl().replace(/\/+$/, "");
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  const url = `${base}${normalizedPath}`;
  const res = await fetch(url, { credentials: "include", ...options });
  if (!res.ok) {
    throw new Error(`API request failed: ${res.status}`);
  }
  return res.json();
}
