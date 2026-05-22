// Entry point for the importmap-managed JavaScript bundle.
document.querySelectorAll(".card").forEach((card) => {
  card.dataset.ready = "true";
});

// `Array.prototype.findLast` is a relatively recent addition — eslint-plugin-compat
// will flag it against older browser targets.
const lastBig = [1, 2, 3].findLast((n) => n > 1);
console.log(lastBig);
