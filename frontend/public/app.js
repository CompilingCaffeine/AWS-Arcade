const gamesEl = document.getElementById("games");
const emptyEl = document.getElementById("empty");
const countEl = document.getElementById("count");
const searchEl = document.getElementById("search");

let games = [];

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function render() {
  const query = searchEl.value.trim().toLowerCase();
  const filtered = games.filter((game) => {
    const haystack = [game.title, game.description, ...(game.tags || [])].join(" ").toLowerCase();
    return haystack.includes(query);
  });

  countEl.textContent = `${filtered.length} game${filtered.length === 1 ? "" : "s"}`;
  emptyEl.hidden = filtered.length !== 0;

  gamesEl.innerHTML = filtered
    .map((game) => {
      const title = escapeHtml(game.title || game.game_id);
      const description = escapeHtml(game.description || "Static HTML5 arcade game.");
      const url = escapeHtml(game.url_path || `/games/${game.game_id}/`);
      const tags = (game.tags || [])
        .slice(0, 4)
        .map((tag) => `<span class="tag">${escapeHtml(tag)}</span>`)
        .join("");
      const thumbnail = game.thumbnail_url
        ? `<img src="${escapeHtml(game.thumbnail_url)}" alt="">`
        : `<div class="thumbnail-placeholder" aria-hidden="true">${title.slice(0, 1)}</div>`;

      return `
        <article class="game-card">
          ${thumbnail}
          <div class="game-card-body">
            <h2>${title}</h2>
            <p>${description}</p>
            <div class="tags">${tags}</div>
            <a class="play-link" href="${url}">Play</a>
          </div>
        </article>
      `;
    })
    .join("");
}

async function loadCatalog() {
  try {
    const response = await fetch("/catalog/catalog.json", { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Catalog request failed: ${response.status}`);
    }

    const catalog = await response.json();
    games = Array.isArray(catalog.games) ? catalog.games : [];
    render();
  } catch (error) {
    console.error(error);
    countEl.textContent = "Catalog unavailable";
    emptyEl.hidden = false;
    emptyEl.textContent = "The game catalog could not be loaded.";
  }
}

searchEl.addEventListener("input", render);
loadCatalog();

