
# 🔒 Universal Cookie Security Handler

### Protocol-Aware, Environment-Agnostic, Production-Grade

---

> **Author:** Arman Mia  
> **Target:** VPS Deployment · Vercel · Localhost · Multi-Environment  
> **Resolves:** Cross-origin cookie blocking due to `SameSite` / `Secure` mismatch between HTTP (IP) and HTTPS (Domain)

---

## Table of Contents

1. [The Problem](#the-problem)
2. [Why Hardcoding Fails](#why-hardcoding-fails)
3. [The Solution: Runtime Protocol Detection](#the-solution-runtime-protocol-detection)
4. [Backend Implementation](#backend-implementation)
5. [Frontend Implementation](#frontend-implementation)
6. [Behavior Matrix](#behavior-matrix)
7. [Nginx Configuration](#nginx-configuration)
8. [Edge Cases Covered](#edge-cases-covered)
9. [Quick Reference](#quick-reference)

---

## The Problem

Modern browsers enforce strict cookie policies. The combination you choose must satisfy three environments simultaneously:

| Environment | Protocol | Ideal Cookie Setting |
|:---|:---|:---|
| VPS IP (Testing) | HTTP | `secure: false, sameSite: lax` |
| Domain (Production) | HTTPS | `secure: true, sameSite: none` |
| Localhost (Dev) | HTTP | `secure: false, sameSite: lax` |

A single hardcoded value breaks at least one environment.

---

## Why Hardcoding Fails

```javascript
// ❌ Breaks on HTTP (IP)
secure: true, sameSite: "none"

// ❌ Works but insecure on HTTPS (Domain)
secure: false, sameSite: "lax"

// ❌ Chrome blocks this entirely
secure: false, sameSite: "none"
```

| `secure` | `sameSite` | HTTP (IP) | HTTPS (Domain) |
|:---|:---|:---|:---|
| `true` | `none` | ❌ Blocked | ✅ Works |
| `false` | `lax` | ✅ Works | ⚠️ No cross-origin |
| `false` | `none` | ❌ Chrome blocks | ❌ Chrome blocks |

**Conclusion:** You must detect the protocol at runtime.

---

## The Solution: Runtime Protocol Detection

Instead of static `NODE_ENV` checks, we inspect the **actual request context**:

```
Browser → [HTTP/HTTPS] → Nginx → [X-Forwarded-Proto] → Express
```

Two sources of truth, OR'd together:

| Check | Source | Detects |
|:---|:---|:---|
| `req.secure` | Express built-in | Direct HTTPS connection |
| `req.headers["x-forwarded-proto"]` | Nginx header | HTTPS terminated at proxy |

```typescript
const isSecure = req.secure
    || req.headers["x-forwarded-proto"] === "https";
```

If **either** returns `true`, the original request was HTTPS.

---

## Backend Implementation

### File: `src/app/utils/setCookie.ts`

```typescript
import { Response, Request } from "express";

interface AuthTokens {
    accessToken?: string;
    refreshToken?: string;
}

/**
 * Set authentication cookies with automatic protocol detection.
 * 
 * Eliminates the need for environment-based cookie configuration.
 * Works identically on IP (HTTP), Domain (HTTPS), and localhost.
 * 
 * @param req        - Express Request object
 * @param res        - Express Response object
 * @param tokenInfo  - Access and/or refresh tokens
 * 
 * @mechanism
 * ```
 * isSecure = req.secure OR x-forwarded-proto === "https"
 * 
 * If isSecure (HTTPS):
 *   → secure: true, sameSite: "none"  (cross-origin OK)
 * If !isSecure (HTTP):
 *   → secure: false, sameSite: "lax"  (survives redirects)
 * ```
 * 
 * @example
 * ```typescript
 * const loginInfo = await AuthServices.credentialsLogin(req.body);
 * setAuthCookie(req, res, {
 *     accessToken: loginInfo.accessToken,
 *     refreshToken: loginInfo.refreshToken
 * });
 * ```
 */
export const setAuthCookie = (
    req: Request,
    res: Response,
    tokenInfo: AuthTokens
): void => {
    // 🔍 Runtime protocol detection
    const isSecure = req.secure
        || req.headers["x-forwarded-proto"] === "https";

    if (tokenInfo.accessToken) {
        res.cookie("accessToken", tokenInfo.accessToken, {
            httpOnly: true,
            secure: isSecure,
            sameSite: isSecure ? "none" : "lax",
            maxAge: 60 * 60 * 1000,       // 1 hour
            path: "/",
        });
    }

    if (tokenInfo.refreshToken) {
        res.cookie("refreshToken", tokenInfo.refreshToken, {
            httpOnly: true,
            secure: isSecure,
            sameSite: isSecure ? "none" : "lax",
            maxAge: 30 * 24 * 60 * 60 * 1000, // 30 days
            path: "/",
        });
    }
};
```

### Integration in Controller

```typescript
// auth.controller.ts
import { setAuthCookie } from "../../utils/setCookie";

const credentialsLogin = catchAsync(async (req, res) => {
    const loginInfo = await AuthServices.credentialsLogin(req.body);
    
    setAuthCookie(req, res, loginInfo);  // ← Single call, protocol-aware

    sendResponse(res, {
        statusCode: 200,
        success: true,
        message: "User Logged In successfully",
        data: loginInfo,
    });
});
```

---

## Frontend Implementation

### File: `src/services/auth/auth.service.js`

```javascript
/**
 * Detect protocol in browser context.
 * Falls back to `false` during SSR (server-side rendering).
 * 
 * @mechanism
 * Browser: reads window.location.protocol
 * Server:  returns false (cookies set by backend, not here)
 */
const isSecure = typeof window !== "undefined"
    ? window.location.protocol === "https:"
    : false;

await setCookie("accessToken", accessTokenObject.accessToken, {
    secure: isSecure,
    httpOnly: true,
    maxAge: parseInt(accessTokenObject["Max-Age"]) || 3600,
    path: accessTokenObject.Path || "/",
    sameSite: isSecure ? "none" : "lax",
});

await setCookie("refreshToken", refreshTokenObject.refreshToken, {
    secure: isSecure,
    httpOnly: true,
    maxAge: parseInt(refreshTokenObject["Max-Age"]) || 2592000,
    path: refreshTokenObject.Path || "/",
    sameSite: isSecure ? "none" : "lax",
});
```

---

## Behavior Matrix

| Request Source | Protocol | `isSecure` | `secure` | `sameSite` | Status |
|:---|:---|:---|:---|:---|:---|
| `http://98.93.120.159` (IP) | HTTP | `false` | `false` | `lax` | ✅ Accepted |
| `https://yourdomain.com` (Domain) | HTTPS | `true` | `true` | `none` | ✅ Accepted |
| `http://localhost:3000` (Dev) | HTTP | `false` | `false` | `lax` | ✅ Accepted |
| `https://localhost:3000` (Dev SSL) | HTTPS | `true` | `true` | `none` | ✅ Accepted |

---

## Nginx Configuration

The `X-Forwarded-Proto` header must be forwarded by Nginx for this to work.

### Required Directive

```nginx
server {
    listen 80;
    server_name _;

    location /api/ {
        proxy_pass http://127.0.0.1:5000;
        
        # ⚠️ THIS LINE IS REQUIRED
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_cache_bypass $http_upgrade;
    }
}
```

| Nginx `$scheme` | Forwarded Value |
|:---|:---|
| Client → HTTP → Nginx | `http` |
| Client → HTTPS → Nginx | `https` |

---

## Edge Cases Covered

| Scenario | Handled By | Result |
|:---|:---|:---|
| Direct HTTPS (no proxy) | `req.secure` | `true` |
| Nginx reverse proxy (HTTPS → HTTP) | `x-forwarded-proto` | `true` |
| Server-side rendering (Next.js) | `typeof window === "undefined"` check | No crash |
| HTTP with localhost | Falls back to `lax` | Accepted by Chrome |
| Load balancer strips headers | `req.secure` as fallback | Works |
| Multiple proxies | Checks header, not IP | Works |

---

## Quick Reference

```bash
# Backend (setCookie.ts)
const isSecure = req.secure || req.headers["x-forwarded-proto"] === "https";

# Frontend (auth.service.js)
const isSecure = typeof window !== "undefined"
    ? window.location.protocol === "https:"
    : false;
```

| Environment | `.env` | Cookie Behavior |
|:---|:---|:---|
| IP / HTTP | `NODE_ENV=production` | Auto → `lax` |
| Domain / HTTPS | `NODE_ENV=production` | Auto → `none` + `secure` |

> ✅ **No `.env` changes needed when switching between IP and Domain.**

---

## Key Takeaways

1. **Never hardcode** `secure` or `sameSite` — detect at runtime
2. **Two sources** are better than one: `req.secure` + `x-forwarded-proto`
3. **Single `.env`** works for all environments
4. **Nginx must forward** `X-Forwarded-Proto` for proxied setups
5. **SSR-safe** in Next.js via `typeof window` guard

---

> **Pro Tip:** This pattern is cloud-agnostic. Works identically on AWS EC2, Vultr, DigitalOcean, Vercel, or bare metal. Test with IP, deploy with Domain — zero config changes.

---

**© 2026 Arman Mia. Production-Grade VPS Deployment Guide.**
```

---

এটা একদম প্রোডাকশন-গ্রেড ডকুমেন্টেশন — টেবিল, কোড ব্লক, এজ কেস, ডায়াগ্রাম সব দিয়ে গোছানো! 🔥🚀