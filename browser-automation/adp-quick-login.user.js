// ==UserScript==
// @name         ADP Quick Login
// @namespace    some username
// @version      1.2
// @description  ADP: fill user ID -> Need help -> Email -> Show options -> Mobile app
// @match        https://*.adp.com/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
  'use strict';

  const USERNAME = 'some username';
  const EMAIL = 'example@example.com';
  const REMEMBER_USER_ID = true;

  const log = (...a) => console.log('[ADP Quick Login]', ...a);
  const done = {};
  log('script loaded on', location.href);

  function deepQueryAll(selector, root = document) {
    const out = [...root.querySelectorAll(selector)];
    root.querySelectorAll('*').forEach(el => {
      if (el.shadowRoot) out.push(...deepQueryAll(selector, el.shadowRoot));
    });
    return out;
  }

  function toInput(el) {
    if (!el) return null;
    if (el instanceof HTMLInputElement) return el;
    return deepQueryAll('input', el.shadowRoot || el)[0] || null;
  }

  const visible = el => el && el.getClientRects().length > 0 && !el.disabled &&
    el.getAttribute('aria-disabled') !== 'true';

  function fill(input, value) {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    input.focus();
    setter.call(input, value);
    ['input', 'change'].forEach(t =>
      input.dispatchEvent(new Event(t, { bubbles: true, composed: true })));
    input.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, composed: true }));
  }

  // Find the clickable element whose text matches, picking the most specific (shortest text)
  function findByText(regex) {
    const sel = 'button, a, label, sdf-button, [role="button"], [role="radio"], [role="link"], [role="option"], [tabindex]';
    return deepQueryAll(sel)
      .filter(el => visible(el) && regex.test((el.innerText || el.textContent || '').trim()))
      .sort((a, b) => (a.innerText || '').length - (b.innerText || '').length)[0] || null;
  }

  function clickByText(regex) {
    const el = findByText(regex);
    if (el) { log('clicking', JSON.stringify((el.innerText || '').trim())); el.click(); return true; }
    return false;
  }

  // Retry a click for a few seconds (buttons can be disabled until the form validates)
  function clickWhenReady(regex, tries = 20) {
    if (clickByText(regex) || tries <= 0) return;
    setTimeout(() => clickWhenReady(regex, tries - 1), 300);
  }

  function findField(selectors) {
    for (const el of deepQueryAll(selectors)) {
      const input = toInput(el);
      if (input && visible(input) && !['password', 'checkbox', 'radio'].includes(input.type)) return input;
    }
    return null;
  }

  const passwordVisible = () => deepQueryAll('input[type="password"]').some(visible);

  function step() {
    try {
      // 4. Verify Your Identity: expand options, then choose mobile app
      if (!done.mobile) {
        if (!done.moreOptions && clickByText(/^show additional options$/i)) {
          done.moreOptions = true;
          return;
        }
        if (clickByText(/mobile app|adp app|push notification|approve.*app|use .*app/i)) {
          done.mobile = true;
          log('mobile app option selected — approve it on your phone');
          return;
        }
      }

      // 3. Forgot Password dialog: choose Email Address, fill it, Next
      if (!done.emailRadio) {
        const radio = findByText(/^email address$/i);
        if (radio) {
          radio.click();
          done.emailRadio = true;
          log('selected Email Address');
          return;
        }
      }
      if (done.emailRadio && !done.email) {
        const e = findField('input[type="email"], [name*="email" i], [id*="email" i], [placeholder*="email" i]');
        if (e) {
          fill(e, EMAIL);
          done.email = true;
          log('filled email');
          setTimeout(() => clickWhenReady(/^next$/i), 400);
          return;
        }
      }

      // 2. Password screen: open "Need help signing in?"
      if (!done.help && !done.emailRadio && passwordVisible()) {
        if (clickByText(/need help signing in/i)) { done.help = true; return; }
      }

      // 1. User ID screen: fill and press Next
      if (!done.user && !passwordVisible()) {
        const u = findField('#login-form_username, [name="username"], [autocomplete="username"], [id*="user" i]');
        if (u) {
          if (u.value !== USERNAME) fill(u, USERNAME);
          done.user = true;
          log('filled user ID');
          if (REMEMBER_USER_ID) {
            const cb = deepQueryAll('input[type="checkbox"]').find(visible);
            if (cb && !cb.checked) cb.click();
          }
          setTimeout(() => clickWhenReady(/^next$/i), 400);
        }
      }
    } catch (err) {
      log('error:', err);
    }
  }

  let timer;
  new MutationObserver(() => {
    clearTimeout(timer);
    timer = setTimeout(step, 300);
  }).observe(document.documentElement, { childList: true, subtree: true });

  // Backup polling for 2 minutes
  let tries = 0;
  const poll = setInterval(() => { step(); if (++tries > 240) clearInterval(poll); }, 500);
})();
