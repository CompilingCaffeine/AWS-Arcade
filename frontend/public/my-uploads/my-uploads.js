(async () => {
  const REDIRECT = `${window.location.origin}/my-uploads/`;
  if (!(await window.HerziAuth.bootstrapPage(REDIRECT))) return;

  const { escapeHtml, apiCall } = window.HerziAuth;

  function renderItem(item) {
    const previewHref = item.status === "published" ? item.url_path : item.staging_url_path;
    return `
      <article class="game-card">
        <div class="game-card-body">
          <h2>${escapeHtml(item.title || item.game_id)}</h2>
          <p>${escapeHtml(item.description || "")}</p>
          <p>Status: <strong>${escapeHtml(item.status || "unknown")}</strong></p>
          ${item.reject_reason ? `<p>Reason: ${escapeHtml(item.reject_reason)}</p>` : ""}
          ${previewHref ? `<a class="play-link" href="${escapeHtml(previewHref)}">Open</a>` : ""}
        </div>
      </article>
    `;
  }

  const status = document.getElementById("status");
  status.textContent = "Loading…";
  const response = await apiCall("/me/uploads", { method: "GET" });
  if (!response.ok) {
    status.textContent = `Could not load submissions (HTTP ${response.status}).`;
    return;
  }

  const { items } = await response.json();
  status.textContent = "";
  const container = document.getElementById("items");
  if (!items.length) {
    container.innerHTML = "<p>No submissions yet.</p>";
    return;
  }
  container.innerHTML = `<div class="game-grid">${items.map(renderItem).join("")}</div>`;
})();
