async function loadCount() {
  const countEl = document.getElementById("count");
  const errorEl = document.getElementById("error");
  errorEl.textContent = "";
  try {
    const res = await fetch("/api/visits", { method: "POST" });
    const data = await res.json();
    if (data.status === "ok") {
      countEl.textContent = data.count;
    } else {
      errorEl.textContent = data.message;
    }
  } catch (e) {
    errorEl.textContent = "Could not reach backend: " + e.message;
  }
}
loadCount();