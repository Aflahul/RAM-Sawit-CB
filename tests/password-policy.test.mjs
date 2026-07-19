import assert from 'node:assert/strict';
import test from 'node:test';
import { isStrongPassword } from '../lib/password-policy.mjs';

test('accepts a password that satisfies every required group', () => {
  assert.equal(isStrongPassword('Strong!Pass123'), true);
});

test('rejects missing, short, or incomplete passwords', () => {
  for (const password of [
    null,
    '',
    'Short!1A',
    'NOLOWERCASE!123',
    'nouppercase!123',
    'NoDigits!Password',
    'NoSymbols123Password',
    'Space IsNotASymbol123',
    'EmojiIsNotASymbol123🙂',
  ]) {
    assert.equal(isStrongPassword(password), false, `expected rejection for ${String(password)}`);
  }
});
