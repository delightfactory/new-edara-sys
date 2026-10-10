import assert from 'node:assert/strict'
import { test } from 'node:test'
import { fixtureResponse, realtimeReply } from './synthetic-fixtures.mjs'

test('unknown endpoints and writes fail closed instead of returning synthetic success', () => {
  for (const [method, path] of [['GET', '/rest/v1/unqualified'], ['POST', '/rest/v1/customers'], ['DELETE', '/rest/v1/profiles']]) {
    const request = { url: () => `http://127.0.0.1:5197${path}`, method: () => method }
    assert.throws(() => fixtureResponse(request, { kind: 'admin' }, { profileAttempts: 0 }), /Unqualified fixture/)
  }
})

test('unknown realtime topics and mutation events cannot receive success acknowledgments', () => {
  for (const [topic, event] of [['realtime:unqualified', 'phx_join'], ['realtime:global-realtime', 'broadcast']]) {
    assert.throws(() => realtimeReply(JSON.stringify([null, '1', topic, event, {}])), /Unqualified realtime/)
  }
})
