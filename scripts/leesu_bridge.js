// Session scan and request adapted from Lee-Su-Threads (MIT, vendor/lee-su-threads).
// This runs in a dedicated Threads WKWebView. Tokens never cross the native bridge.
(() => {
  if (location.hostname !== 'www.threads.com' && location.hostname !== 'threads.com') return;
  const patterns = {
    fb_dtsg: [/"fb_dtsg"\s*:\s*"([^"]+)"/, /"DTSGInitialData"[^}]*"token"\s*:\s*"([^"]+)"/, /\["DTSGInitData",\[\],\{"token":"([^"]+)"/],
    lsd: [/"lsd"\s*:\s*"([^"]+)"/, /"LSD"[^}]*"token"\s*:\s*"([^"]+)"/],
    jazoest: [/"jazoest"\s*:\s*"?(\d+)"?/],
    __user: [/"viewer"\s*:\s*\{[^}]*"id"\s*:\s*"(\d+)"/, /"USER_ID"\s*:\s*"(\d+)"/, /"(?:viewer_id|current_user_id|userID|viewerID|__user)"\s*:\s*"?(\d{5,})"?/]
  };
  function session() {
    const tokens = {};
    for (const input of document.querySelectorAll('input[name="fb_dtsg"], input[name="lsd"], input[name="jazoest"]')) {
      if (input.value) tokens[input.name] = input.value;
    }
    for (const script of document.querySelectorAll('script:not([src])')) {
      for (const [name, regexes] of Object.entries(patterns)) {
        if (tokens[name]) continue;
        for (const regex of regexes) {
          const match = (script.textContent || '').match(regex);
          if (match) { tokens[name] = match[1]; break; }
        }
      }
    }
    return tokens;
  }
  window.TPLeeSu = {
    ready() { const s = session(); return !!(s.fb_dtsg && s.__user && s.__user !== '0'); },
    async profile(userID) {
      if (!/^\d{1,30}$/.test(userID)) return {_error: 'invalid_id'};
      const s = session();
      if (!s.fb_dtsg || !s.__user || s.__user === '0') return {_loginRequired: true};
      const body = new URLSearchParams({
        __user: '0', __a: '1', __comet_req: '29', __d: 'www', dpr: '2',
        fb_dtsg: s.fb_dtsg, lsd: s.lsd || '', jazoest: s.jazoest || '',
        params: JSON.stringify({atpTriggerSessionID: crypto.randomUUID(), referer_type: 'TextPostAppProfileOverflow', target_user_id: userID})
      });
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 15000);
      try {
        const response = await fetch('/async/wbloks/fetch/?appid=com.bloks.www.text_post_app.about_this_profile_async_action&type=app&__bkv=22713cafbb647b89c4e9c1acdea97d89c8c2046e2f4b18729760e9b1ae0724f7', {
          method: 'POST', credentials: 'include', signal: controller.signal,
          headers: {'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8', 'X-FB-Friendly-Name': 'BarcelonaProfileAboutThisProfileAsyncActionQuery'}, body
        });
        if (response.status === 429) return {_rateLimited: true};
        if (response.status === 401 || response.status === 403) return {_loginRequired: true};
        if (!response.ok) return {_error: 'http'};
        const info = parseProfileResponse(await response.text());
        if (!info || (!info.joined && !info.location)) return {_error: 'unavailable'};
        // Only the public profile fields leave the web view. Never return tokens/cookies.
        return {username: info.username || '', displayName: info.displayName || '', location: info.location || '', joined: info.joined || '', isNew: isNewUser(info.joined)};
      } catch (_) { return {_error: 'network'}; }
      finally { clearTimeout(timer); }
    }
  };
})();
