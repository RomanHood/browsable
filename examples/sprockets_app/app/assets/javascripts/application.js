// Sprockets manifest-style entry point. The `//= require` lines below are
// Sprockets directives — they are JS comments, so eslint (and any other JS
// tool) ignores them. browsable does not parse Sprockets manifests; runtime
// mode reads what Rails actually renders, which is the authoritative answer
// for "which assets ship?".
//= require rails-ujs
//= require_tree .

document.querySelectorAll(".card").forEach((card) => {
  card.dataset.ready = "true";
});

// `Array.prototype.findLast` is recent — eslint-plugin-compat flags it
// against older browser targets, exactly like in the Propshaft fixture.
const lastBig = [1, 2, 3].findLast((n) => n > 1);
console.log(lastBig);
