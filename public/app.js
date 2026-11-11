const $ = (id) => document.getElementById(id);
const form = $("feedback-form");
const labels = [
  "Your honest take",
  "Needs work",
  "Could be better",
  "Pretty good",
  "Really good",
  "Love it!",
];
const colors = [
  "#e3e7dd",
  "#c6715a",
  "#c38e43",
  "#bea34a",
  "#91a35d",
  "#608547",
];
let selected = 0;
let projects = [];
const paintRating = (rating) => {
  $("stars").style.setProperty("--star-color", colors[rating]);
  document
    .querySelectorAll(".star-option")
    .forEach((star, index) => star.classList.toggle("active", index < rating));
  $("rating-caption").textContent = labels[rating];
};
document.querySelectorAll(".star-option").forEach((star) => {
  star.addEventListener("mouseenter", () =>
    paintRating(Number(star.querySelector("input").value)),
  );
  star.querySelector("input").addEventListener("change", (event) => {
    selected = Number(event.target.value);
    paintRating(selected);
  });
});
$("stars").addEventListener("mouseleave", () => paintRating(selected));
for (const field of ["likes", "improvements"])
  $(field).addEventListener("input", () => {
    $(field + "-count").textContent =
      `${$(field).value.length.toLocaleString()} / 2,000`;
    $(field).setCustomValidity("");
  });
function updateProject() {
  const project = projects.find((item) => item.id === $("project").value);
  if (!project) return;
  $("project-description").textContent = project.description;
  $("project-link").hidden = !project.url;
  $("url-unavailable").hidden = !!project.url;
  if (project.url) $("project-link").href = project.url;
  else $("project-link").removeAttribute("href");
}
$("project").addEventListener("change", updateProject);
form.addEventListener("submit", async (event) => {
  event.preventDefault();
  for (const field of ["likes", "improvements"]) {
    $(field).setCustomValidity(
      $(field).value.trim() ? "" : "Please share a few words.",
    );
  }
  if (!form.reportValidity()) return;
  $("submit-button").disabled = true;
  $("submit-button").firstElementChild.textContent = "Sending your thoughts…";
  $("form-error").hidden = true;
  try {
    const response = await fetch("/api/feedback", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        project: $("project").value,
        rating: selected,
        likes: $("likes").value,
        improvements: $("improvements").value,
      }),
      signal: AbortSignal.timeout(15000),
    });
    const result = await response.json();
    if (!response.ok)
      throw new Error(
        result.error || "Something went wrong. Please try again.",
      );
    $("success-message").textContent =
      result.mode === "demo"
        ? "Thanks for taking it for a spin! This was a demo submission. Your feedback was not stored or delivered."
        : "Your feedback has been sent. Thank you for helping shape the next chapter of FootieLineup.";
    form.hidden = true;
    $("success-panel").hidden = false;
    $("success-panel").focus();
  } catch (error) {
    $("form-error").textContent =
      error.name === "TimeoutError"
        ? "Delivery took too long to confirm. Your text is still here. Please check before submitting again."
        : error instanceof TypeError
          ? "We couldn’t connect. Your text is still here; check your connection and try again."
          : error.message;
    $("form-error").hidden = false;
  } finally {
    $("submit-button").disabled = false;
    $("submit-button").firstElementChild.textContent = "Send feedback";
  }
});
$("send-another").addEventListener("click", () => {
  form.reset();
  selected = 0;
  paintRating(0);
  for (const field of ["likes", "improvements"]) {
    $(field).setCustomValidity("");
    $(field + "-count").textContent = "0 / 2,000";
  }
  updateProject();
  $("success-panel").hidden = true;
  form.hidden = false;
  $("project").focus();
});
$("year").textContent = new Date().getFullYear();
try {
  const response = await fetch("/api/config", {
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error("Configuration unavailable");
  const config = await response.json();
  projects = config.projects;
  for (const project of projects) {
    const option = document.createElement("option");
    option.value = project.id;
    option.textContent = project.name;
    option.title = project.name;
    $("project").append(option);
  }
  updateProject();
  $("demo-note").hidden = config.mode !== "demo";
  $("loading-message").hidden = true;
  form.hidden = false;
} catch {
  $("loading-message").textContent =
    "We couldn’t load the projects. Please refresh to try again.";
}
