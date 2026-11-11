// Lee-Su-Threads: MIT license in LeeSu-LICENSE.txt
(() => {
/**
 * Profile parsing utilities for Threads API responses
 * Extracted for testability
 */

function extractProfileInfo(obj, result = {}) {
  if (!obj || typeof obj !== 'object') return result;

  // Initialize array to collect all label-value pairs
  if (result._pairs === undefined) {
    result._pairs = [];
    result._currentLabel = null;
  }

  if (obj['bk.components.Text']) {
    const textComp = obj['bk.components.Text'];
    let text = textComp.text;
    const style = textComp.text_style;
    const onBind = textComp.on_bind;

    // Handle dynamic text binding (e.g., location privacy)
    // Format: (bk.action.core.If, condition, "Value1", "Value2")
    if (!text && onBind && typeof onBind === 'string') {
      // Extract both values from the conditional
      const match = onBind.match(/"([^"]*)"\s*,\s*"([^"]+)"/);
      if (match) {
        let value1 = match[1];
        let value2 = match[2];

        // Decode Unicode escape sequences for both values
        value1 = value1.replace(/\\u([0-9a-fA-F]{4})/g, (_, hex) => {
          return String.fromCharCode(parseInt(hex, 16));
        });
        value2 = value2.replace(/\\u([0-9a-fA-F]{4})/g, (_, hex) => {
          return String.fromCharCode(parseInt(hex, 16));
        });

        // If first value is empty, use second value (e.g., "未分享" / "Not shared")
        // Otherwise use first value (the actual location)
        text = value1 || value2;
      }
    }

    if (style === 'semibold' && text) {
      // This is a label - store it
      result._currentLabel = text;
    } else if (style === 'normal' && text && result._currentLabel) {
      // This is a value - pair it with the label
      result._pairs.push({ label: result._currentLabel, value: text });
      result._currentLabel = null;
    }
  }

  if (obj['bk.components.RichText']) {
    const children = obj['bk.components.RichText'].children || [];
    let fullText = '';
    for (const child of children) {
      if (child['bk.components.TextSpan']) {
        fullText += child['bk.components.TextSpan'].text || '';
      }
    }
    // Try multiple patterns for name/username extraction
    // Support both half-width ( and full-width （ parentheses
    // Pattern 1: "Name (@username)" with closing paren
    let match = fullText.match(/^(.+?)\s*[（(]@([\w.]+)[)）]$/);
    // Pattern 2: "Name (@username" without closing paren (sometimes the ) is in a separate span)
    if (!match) {
      match = fullText.match(/^(.+?)\s*[（(]@([\w.]+)/);
    }
    // Pattern 3: Just "@username" somewhere in the text
    if (!match) {
      match = fullText.match(/@([\w.]+)/);
      if (match) {
        result.username = match[1];
        // Try to get display name from the part before @
        const nameMatch = fullText.match(/^(.+?)\s*[（(]@/);
        if (nameMatch) {
          result.displayName = nameMatch[1].trim();
        }
      }
    }
    if (match && match[2]) {
      result.displayName = match[1]?.trim();
      result.username = match[2];
    }
  }

  if (obj['bk.components.Image']) {
    const url = obj['bk.components.Image'].url;
    if (url && url.includes('cdninstagram.com')) {
      result.profileImage = url;
    }
  }

  for (const key of Object.keys(obj)) {
    const value = obj[key];
    if (Array.isArray(value)) {
      for (const item of value) {
        extractProfileInfo(item, result);
      }
    } else if (typeof value === 'object' && value !== null) {
      extractProfileInfo(value, result);
    }
  }

  return result;
}

function parseProfileResponse(responseText) {
  try {
    let jsonStr = responseText;
    if (jsonStr.startsWith('for (;;);')) {
      jsonStr = jsonStr.substring(9);
    }
    const data = JSON.parse(jsonStr);
    const profileInfo = extractProfileInfo(data);

    // Process pairs after all extraction is complete
    if (profileInfo._pairs && profileInfo._pairs.length > 0) {
      const pairs = profileInfo._pairs;

      // Define label patterns for different languages
      const joinedLabels = ['Joined', '已加入', '参加日', '가입일', '가입 날짜'];
      const locationLabels = ['Based in', '所在地點', '所在地', '위치', '거주지'];
      const verifiedLabels = ['Verified by Meta', 'Meta 驗證', 'Meta 验证', 'Metaにより認証', 'Metaにより認証済み', 'Meta認証', 'Meta 인증', 'Meta 인증 완료'];
      const nameLabels = ['Name', '名稱', '名前', '이름']; // Exclude these
      const formerUsernameLabels = ['Former usernames', 'Previous usernames', '先前的用戶名稱', '先前的使用者名稱', '先前的用户名称', '以前のユーザーネーム', '이전 사용자 이름']; // Exclude these

      // Filter out name and former username fields
      const relevantPairs = pairs.filter(p =>
        !nameLabels.includes(p.label) && !formerUsernameLabels.includes(p.label)
      );

      // Primary: Label-based matching
      const joinedPair = relevantPairs.find(p => joinedLabels.includes(p.label));
      if (joinedPair) {
        // Remove everything after · (user number like "100M+", "#2,697,767")
        profileInfo.joined = joinedPair.value.split(/\s*[·•]\s*/)[0].trim();
      }

      const locationPair = relevantPairs.find(p => locationLabels.includes(p.label));
      if (locationPair) {
        profileInfo.location = locationPair.value;
      }

      const verifiedPair = relevantPairs.find(p => verifiedLabels.includes(p.label));
      if (verifiedPair) {
        profileInfo.isVerified = true;
        profileInfo.verifiedDate = verifiedPair.value; // e.g., "May 2021"
      }

      // Fallback: Position-based (for backward compatibility if labels don't match)
      if (!joinedPair && relevantPairs.length >= 1) {
        // First relevant pair is likely joined date
        profileInfo.joined = relevantPairs[0].value.split(/\s*[·•]\s*/)[0].trim();
      }

      if (!locationPair && relevantPairs.length >= 2) {
        // Second relevant pair is likely location (only if not verified)
        const secondPair = relevantPairs[1];
        if (!verifiedLabels.includes(secondPair.label)) {
          profileInfo.location = secondPair.value;
        }
      }
    }

    // Clean up internal properties
    delete profileInfo._pairs;
    delete profileInfo._currentLabel;
    delete profileInfo._pairsProcessed;

    return profileInfo;
  } catch (e) {
    console.error('Failed to parse response:', e);
    return null;
  }
}

// Export for testing (ESM)

// Parse joined date string and return Date object
// Handles formats like: "2024年1月", "January 2024", "2024년 1월", "2024年1月"
function parseJoinedDate(joinedStr) {
  if (!joinedStr) return null;

  // Month name mappings for different locales
  const monthMap = {
    // English
    'january': 0, 'february': 1, 'march': 2, 'april': 3, 'may': 4, 'june': 5,
    'july': 6, 'august': 7, 'september': 8, 'october': 9, 'november': 10, 'december': 11,
    'jan': 0, 'feb': 1, 'mar': 2, 'apr': 3, 'jun': 5, 'jul': 6, 'aug': 7, 'sep': 8, 'oct': 9, 'nov': 10, 'dec': 11,
    // Japanese
    '1月': 0, '2月': 1, '3月': 2, '4月': 3, '5月': 4, '6月': 5,
    '7月': 6, '8月': 7, '9月': 8, '10月': 9, '11月': 10, '12月': 11,
    // Korean
    '1월': 0, '2월': 1, '3월': 2, '4월': 3, '5월': 4, '6월': 5,
    '7월': 6, '8월': 7, '9월': 8, '10월': 9, '11월': 10, '12월': 11,
  };

  // Extract year (4 digits)
  const yearMatch = joinedStr.match(/(\d{4})/);
  if (!yearMatch) return null;
  const year = parseInt(yearMatch[1], 10);

  // Try to find month
  let month = null;

  // Check for CJK month format (e.g., "1月", "12月")
  const cjkMonthMatch = joinedStr.match(/(\d{1,2})[月월]/);
  if (cjkMonthMatch) {
    month = parseInt(cjkMonthMatch[1], 10) - 1; // 0-indexed
  } else {
    // Check for English month names
    const lowerStr = joinedStr.toLowerCase();
    for (const [name, idx] of Object.entries(monthMap)) {
      if (lowerStr.includes(name)) {
        month = idx;
        break;
      }
    }
  }

  if (month === null) return null;

  return new Date(year, month, 1);
}

// Check if user joined within the last N months
// Note: Uses local timezone for date comparison. Since we only have month/year precision
// from the API and a 2-month threshold, timezone differences have minimal impact.
function isNewUser(joinedStr, monthsThreshold = 2, referenceDate = new Date()) {
  const joinedDate = parseJoinedDate(joinedStr);
  if (!joinedDate) return false;

  const thresholdDate = new Date(referenceDate.getFullYear(), referenceDate.getMonth() - monthsThreshold, 1);

  return joinedDate >= thresholdDate;
}

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
  let cachedSession = null;
  let sessionExpires = 0;
  function session() {
    if (cachedSession && Date.now() < sessionExpires) return cachedSession;
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
    if (tokens.fb_dtsg && tokens.__user && tokens.__user !== '0') {
      cachedSession = tokens;
      sessionExpires = Date.now() + 60000;
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
        if (response.status === 401 || response.status === 403) {
          cachedSession = null; sessionExpires = 0;
          return {_loginRequired: true};
        }
        if (!response.ok) return {_error: 'http'};
        const info = parseProfileResponse(await response.text());
        if (!info || (!info.joined && !info.location)) return {_error: 'unavailable'};
        // Only the public profile fields leave the web view. Never return tokens/cookies.
        return {username: info.username || '', displayName: info.displayName || '', location: info.location || '', joined: info.joined || '', isNew: isNewUser(info.joined)};
      } catch (_) { return {_error: 'network'}; }
      finally { clearTimeout(timer); }
    }
  };
  // Document-end can precede slow image/resource loads and didFinishNavigation.
  // Send only readiness, never authentication material, across the native bridge.
  if (window.TPLeeSu.ready()) window.webkit?.messageHandlers?.TPLeeSuReady?.postMessage(true);
})();

})();
