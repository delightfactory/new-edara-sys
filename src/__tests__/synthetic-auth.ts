/** Inert SDK fixtures only: these tokens have no valid signature or backend. */
export function syntheticAuthSession(id: string, expiresIn = 3600) {
  const expiresAt = Math.floor(Date.now() / 1000) + expiresIn
  const encode = (value: unknown) => btoa(JSON.stringify(value)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
  return {
    access_token: `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ sub: id, aud: 'authenticated', role: 'authenticated', exp: expiresAt })}.c3ludGhldGlj`,
    refresh_token: `synthetic-refresh-${id}`,
    expires_in: expiresIn, expires_at: expiresAt, token_type: 'bearer',
    user: { id, aud: 'authenticated', role: 'authenticated', email: `${id}@example.invalid`, app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' },
  }
}

export function syntheticTokenActor(headers?: HeadersInit) {
  const token = new Headers(headers).get('authorization')?.replace(/^Bearer /, '')
  if (!token) throw new Error('Synthetic authenticated request has no bearer token')
  return JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))) as { sub: string }
}
