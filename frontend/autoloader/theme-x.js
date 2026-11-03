// Jailbreak shared UI — WebKit side. Runs after upstream's app.js through the PAGE_JS
// hook, so app.js stays untouched. Adds the header (icon, wordmark, variant line) above
// the log; styles live in theme-x.css. The Y2JB loader draws the same header.
(function () {
  'use strict';
  var loader = document.getElementById('loader');
  if (!loader || document.getElementById('xHeader')) return;

  function part(tag, cls, text) {
    var node = document.createElement(tag);
    node.className = cls;
    if (text) node.textContent = text;
    return node;
  }

  var header = document.createElement('header');
  header.id = 'xHeader';
  header.appendChild(part('div', 'x-logo'));
  header.appendChild(part('div', 'x-title', 'JAILBREAK'));
  header.appendChild(part('div', 'x-sub', 'WebKit · Payload Manager X'));
  loader.insertBefore(header, loader.firstChild);
})();
