(async () => {
  const REDIRECT = `${window.location.origin}/upload/`;
  if (!(await window.HerziAuth.bootstrapPage(REDIRECT))) return;

  document.getElementById("upload-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const file = document.getElementById("file").files[0];
    const status = document.getElementById("status");
    if (!file) {
      status.textContent = "Pick a ZIP first.";
      return;
    }

    status.textContent = "Requesting upload URL…";
    const presignResponse = await window.HerziAuth.apiCall("/uploads", { method: "POST" });
    if (!presignResponse.ok) {
      status.textContent = `Could not start upload (HTTP ${presignResponse.status}).`;
      return;
    }
    const { upload_url, key } = await presignResponse.json();

    status.textContent = `Uploading ${file.name}…`;
    const putResponse = await fetch(upload_url, {
      method: "PUT",
      headers: { "Content-Type": "application/zip" },
      body: file,
    });

    if (!putResponse.ok) {
      status.textContent = `Upload failed (HTTP ${putResponse.status}).`;
      return;
    }

    status.textContent = `Upload received. Your submission is pending review.`;
    console.log("Uploaded as", key);
  });
})();
