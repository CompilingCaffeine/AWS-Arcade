(async () => {
  const REDIRECT = `${window.location.origin}/admin/`;
  if (!(await window.HerziAuth.bootstrapPage(REDIRECT, { requireAdmin: true }))) return;

  const { escapeHtml, apiCall } = window.HerziAuth;

  function renderItem(item) {
    return `
      <article class="game-card" data-upload-id="${escapeHtml(item.upload_id)}" data-game-id="${escapeHtml(item.game_id)}">
        <div class="game-card-body">
          <h2>${escapeHtml(item.title || item.game_id)}</h2>
          <p>${escapeHtml(item.description || "")}</p>
          <p>Game ID: <code>${escapeHtml(item.game_id)}</code></p>
          <p>Uploader: <code>${escapeHtml(item.source_user_sub || "(legacy)")}</code></p>
          ${item.staging_url_path ? `<p><a class="play-link" href="${escapeHtml(item.staging_url_path)}" target="_blank" rel="noopener">Preview</a></p>` : ""}
          <p>
            <button data-action="promote">Promote</button>
            <button data-action="reject">Reject</button>
          </p>
        </div>
      </article>
    `;
  }

  async function load() {
    const status = document.getElementById("status");
    status.textContent = "Loading…";
    const response = await apiCall("/admin/pending", { method: "GET" });
    if (!response.ok) {
      status.textContent = `Could not load pending (HTTP ${response.status}).`;
      return;
    }
    const { items } = await response.json();
    status.textContent = "";
    const container = document.getElementById("items");
    if (!items.length) {
      container.innerHTML = "<p>Nothing pending.</p>";
      return;
    }
    container.innerHTML = `<div class="game-grid">${items.map(renderItem).join("")}</div>`;
  }

  document.getElementById("items").addEventListener("click", async (event) => {
    const button = event.target.closest("button[data-action]");
    if (!button) return;
    const card = button.closest("[data-upload-id]");
    const uploadId = card.getAttribute("data-upload-id");
    const gameId = card.getAttribute("data-game-id");
    const action = button.getAttribute("data-action");
    const status = document.getElementById("status");

    let body;
    if (action === "reject") {
      const reason = prompt("Reason for rejection?", "") || "";
      body = JSON.stringify({ reason });
    }

    status.textContent = `${action}ing ${gameId}…`;
    const response = await apiCall(`/admin/submissions/${encodeURIComponent(uploadId)}/${action}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    });
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      status.textContent = `${action} failed (HTTP ${response.status}): ${detail.error || ""}`;
      return;
    }
    status.textContent = `${action}d ${gameId}.`;
    load();
  });

  load();
})();
