// Cognito Hosted UI OAuth code flow + API helper.

const STORAGE_KEY = "herzi.tokens";

function loadConfig() {
  if (!window.AppConfig) {
    throw new Error("AppConfig not loaded; include /config.js before auth.js");
  }
  return window.AppConfig;
}

function loadTokens() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function saveTokens(tokens) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(tokens));
}

function clearTokens() {
  localStorage.removeItem(STORAGE_KEY);
}

function loginUrl(redirectUri) {
  const cfg = loadConfig();
  const params = new URLSearchParams({
    response_type: "code",
    client_id: cfg.cognitoClientId,
    scope: "openid email profile",
    redirect_uri: redirectUri,
  });
  return `https://${cfg.cognitoDomain}/login?${params.toString()}`;
}

async function exchangeCode(code, redirectUri) {
  const cfg = loadConfig();
  const response = await fetch(`https://${cfg.cognitoDomain}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      client_id: cfg.cognitoClientId,
      code,
      redirect_uri: redirectUri,
    }).toString(),
  });
  if (!response.ok) throw new Error(`Token exchange failed: ${response.status}`);
  return response.json();
}

async function handleCallback(redirectUri) {
  const url = new URL(window.location.href);
  const code = url.searchParams.get("code");
  if (!code) return null;
  const tokens = await exchangeCode(code, redirectUri);
  saveTokens(tokens);
  window.history.replaceState({}, "", url.pathname);
  return tokens;
}

function getIdToken() {
  const tokens = loadTokens();
  return tokens ? tokens.id_token : null;
}

function decodeJwt(token) {
  try {
    const payload = token.split(".")[1];
    return JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
  } catch {
    return null;
  }
}

function getClaims() {
  const token = getIdToken();
  return token ? decodeJwt(token) : null;
}

function isAdmin() {
  const claims = getClaims();
  if (!claims) return false;
  const groups = claims["cognito:groups"] || [];
  return Array.isArray(groups) ? groups.includes("admins") : false;
}

async function apiCall(path, opts = {}) {
  const cfg = loadConfig();
  const token = getIdToken();
  const headers = { ...(opts.headers || {}) };
  if (token) headers["Authorization"] = `Bearer ${token}`;
  return fetch(`${cfg.apiEndpoint}${path}`, { ...opts, headers });
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

// bootstrapPage handles the shared per-page setup for /upload, /my-uploads, /admin:
// token exchange on OAuth return, the "logged out" / "not admin" / "logged in"
// section swap, and the logout wiring. Returns true when the caller should
// continue with the authenticated path, false otherwise.
async function bootstrapPage(redirectUri, options = {}) {
  const { requireAdmin = false } = options;

  try {
    await handleCallback(redirectUri);
  } catch (error) {
    console.error("OAuth callback failed", error);
  }

  const loggedOut = document.getElementById("logged-out");
  const loggedIn = document.getElementById("logged-in");
  const notAdmin = document.getElementById("not-admin");

  if (!loadTokens()) {
    if (loggedOut) loggedOut.hidden = false;
    const loginLink = document.getElementById("login-link");
    if (loginLink) loginLink.href = loginUrl(redirectUri);
    return false;
  }

  if (requireAdmin && !isAdmin()) {
    if (notAdmin) notAdmin.hidden = false;
    return false;
  }

  if (loggedIn) loggedIn.hidden = false;

  const emailEl = document.getElementById("email");
  if (emailEl) emailEl.textContent = (getClaims() || {}).email || "(unknown)";

  const logoutLink = document.getElementById("logout-link");
  if (logoutLink) {
    logoutLink.addEventListener("click", (event) => {
      event.preventDefault();
      clearTokens();
      window.location.href = "/";
    });
  }

  return true;
}

window.HerziAuth = {
  loginUrl,
  handleCallback,
  loadTokens,
  saveTokens,
  clearTokens,
  getIdToken,
  getClaims,
  isAdmin,
  apiCall,
  decodeJwt,
  escapeHtml,
  bootstrapPage,
};
