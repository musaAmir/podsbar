'use strict';
const modeSelect = document.querySelector('#demo-mode');
const modeButtons = [...document.querySelectorAll('[data-display]')];
const descriptions = { both: 'Both buds: left 88 percent, right 84 percent.', lowest: 'Lowest bud: right 84 percent.', none: 'Just the pods: two battery capsules with no numbers.' };
function setDisplayMode(mode) {
  if (!Object.hasOwn(descriptions, mode)) return;
  document.querySelectorAll('.pod-reading').forEach(reading => reading.dataset.mode = mode);
  modeButtons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.display === mode)));
  modeSelect.value = mode;
  document.querySelector('#display-description').textContent = descriptions[mode];
}
modeButtons.forEach(button => button.addEventListener('click', () => setDisplayMode(button.dataset.display)));
modeSelect.addEventListener('change', event => setDisplayMode(event.target.value));
const trigger = document.querySelector('.menu-trigger');
const popover = document.querySelector('#app-popover');
trigger.addEventListener('click', () => {
  const expanded = trigger.getAttribute('aria-expanded') === 'true';
  trigger.setAttribute('aria-expanded', String(!expanded));
  popover.hidden = expanded;
});
popover.addEventListener('keydown', event => {
  if (event.key !== 'Escape') return;
  popover.hidden = true;
  trigger.setAttribute('aria-expanded', 'false');
  trigger.focus();
});
document.querySelector('.demo-refresh').addEventListener('click', () => {
  document.querySelector('#demo-freshness').textContent = 'Example refreshed just now';
});
function openLinkedDetail() {
  if (location.hash !== '#install-note') return;
  document.querySelector('#install-note').open = true;
}
document.querySelectorAll('a[href="#install-note"]').forEach(link => link.addEventListener('click', () => {
  document.querySelector('#install-note').open = true;
}));
window.addEventListener('hashchange', openLinkedDetail);
openLinkedDetail();
