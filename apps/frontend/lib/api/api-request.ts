import { getApiBaseUrl } from "../env/api-base-url";

export async function apiRequest<T>(
  path: string,
  options?: RequestInit,
): Promise<T> {
  const base = getApiBaseUrl();
  const url = `${base}${path}`;
  const res = await fetch(url, { credentials: "include", ...options });
  if (!res.ok) {
    throw new Error(`API request failed: ${res.status}`);
  }
  return res.json();
}
